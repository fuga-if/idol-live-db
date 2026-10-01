import Foundation
import Observation

/// チャット 1 画面ぶんの状態。普通のチャットとキャラとのトークで共用する
/// (違うのは指示文とツールと保存先だけ)。
@MainActor
@Observable
final class AssistantChatModel {
    struct Config {
        var store: AssistantConversationStore
        /// 送るたびに呼ぶ。引数はこれまでの発言 (キャラとのトークは直近の返信から口癖の重なりを避ける)。
        var instructions: ([AssistantMessage]) -> String?
        var toolsJSON: String?
        var idolID: String?
        var newTitle: (String) -> String
    }

    let config: Config
    private(set) var conversation: AssistantConversation
    private(set) var isRunning = false
    /// 応答の生成中に積んでいる文字列 (確定したら conversation.messages に入る)。
    private(set) var streamingText = ""
    /// 実行中のツールの一言 (「セトリを調べています…」)。
    private(set) var toolLabel: String?
    var errorMessage: String?
    /// 利用上限に当たった (Manage usage を主ボタンにして案内する)。
    var usageLimitHit = false

    private var task: Task<Void, Never>?

    init(config: Config, conversationID: UUID? = nil) {
        self.config = config
        conversation = conversationID.flatMap(config.store.conversation)
            ?? AssistantConversation(title: "", idolID: config.idolID)
    }

    var isEmpty: Bool { conversation.messages.isEmpty && !isRunning }

    func open(_ id: UUID) {
        guard let found = config.store.conversation(id) else { return }
        detachRunning()
        conversation = found
        errorMessage = nil
    }

    func startNew() {
        detachRunning()
        conversation = AssistantConversation(title: "", idolID: config.idolID)
        errorMessage = nil
    }

    /// 画面を離れるとき。走っている応答は止め、出たところまでを会話に残す。
    func leave() {
        detachRunning()
    }

    /// 走っている応答を止めて、出たところまでを元の会話に残す (別の会話に切り替える前に呼ぶ)。
    private func detachRunning() {
        guard isRunning else { return }
        let id = conversation.id
        stop()
        keepPartialAnswer(for: id)
        isRunning = false
        toolLabel = nil
    }

    func send(_ text: String, model: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning, !model.isEmpty else { return }
        // 失敗の吹き出しは表示だけのもの。次の発言で片付ける (保存に混ぜない)。
        conversation.messages.removeAll { $0.failed }
        if conversation.title.isEmpty { conversation.title = config.newTitle(text) }
        conversation.messages.append(AssistantMessage(role: .user, text: text))
        conversation.items.append(ChatGPTPlanClient.userMessage(text))
        config.store.upsert(conversation)
        run(model: model)
    }

    /// 失敗した応答をやり直す (最後の発言はそのまま)。
    func retry(model: String) {
        guard !isRunning, !model.isEmpty else { return }
        conversation.messages.removeAll { $0.failed }
        run(model: model)
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func run(model: String) {
        isRunning = true
        streamingText = ""
        toolLabel = nil
        errorMessage = nil
        // 書き戻し先はこの id の会話。走っている間に「新しい会話」や履歴で別の会話に
        // 切り替わっても、結果はこの会話に入る。
        let id = conversation.id
        let history = Self.compacted(conversation.items, keepingReasoning: conversation.model == nil || conversation.model == model)
        task = Task {
            defer {
                if conversation.id == id {
                    isRunning = false
                    toolLabel = nil
                }
            }
            do {
                let added = try await AssistantTurnRunner.run(
                    model: model,
                    history: history,
                    instructions: config.instructions(conversation.messages),
                    toolsJSON: config.toolsJSON
                ) { event in
                    guard conversation.id == id else { return }
                    switch event {
                    case .delta(let text):
                        toolLabel = nil
                        streamingText += text
                    case .toolStarted(let label):
                        toolLabel = label
                    case .toolFinished:
                        // ツールを挟んだら、それまでの前置きは消して答えを書き直させる。
                        streamingText = ""
                    }
                }
                let answer = streamingText
                write(to: id) { conversation in
                    conversation.items = history + added
                    conversation.model = model
                    conversation.messages.append(AssistantMessage(role: .assistant, text: answer))
                }
            } catch {
                if error is CancellationError || Task.isCancelled {
                    keepPartialAnswer(for: id)
                    return
                }
                guard conversation.id == id else { return }
                streamingText = ""
                if let clientError = error as? ChatGPTPlanClient.ClientError, clientError.isUsageLimit {
                    usageLimitHit = true
                }
                errorMessage = error.localizedDescription
                conversation.messages.append(AssistantMessage(role: .assistant, text: "", failed: true))
            }
            if conversation.id == id { streamingText = "" }
        }
    }

    /// 止めた応答は、出たところまでを発言として残し、次の input にも積む。
    private func keepPartialAnswer(for id: UUID) {
        let partial = conversation.id == id ? streamingText : ""
        if conversation.id == id { streamingText = "" }
        guard !partial.isEmpty else { return }
        write(to: id) { conversation in
            conversation.messages.append(AssistantMessage(role: .assistant, text: partial))
            conversation.items.append(ChatGPTPlanClient.jsonString(["role": "assistant", "content": partial]))
        }
    }

    /// id の会話に書いて保存する。いま開いている会話ならそれを、別の会話に切り替わっていれば
    /// 保存済みの最新版を書き換える (開いている会話を巻き込まない)。
    private func write(to id: UUID, _ change: (inout AssistantConversation) -> Void) {
        if conversation.id == id {
            change(&conversation)
            config.store.upsert(conversation)
        } else if var saved = config.store.conversation(id) {
            change(&saved)
            config.store.upsert(saved)
        }
    }

    /// 送る履歴を軽くする。直近 2 回の発言より前の往復からは、関数呼び出しとその結果・推論を落とす
    /// (答えの発言は残るので話の流れは保てる)。ツールの結果は 1 件で数十 KB になりうるので、
    /// 落とさないと長い会話がコンテキストに収まらなくなる。
    /// モデルを変えたときは、前のモデルの暗号化された推論項目も落とす。
    static func compacted(_ items: [String], keepingReasoning: Bool) -> [String] {
        let parsed = items.map { ($0, ChatGPTPlanClient.jsonObject($0)) }
        let userIndexes = parsed.indices.filter { parsed[$0].1?["role"] as? String == "user" }
        let cutoff = userIndexes.count >= 2 ? userIndexes[userIndexes.count - 2] : 0
        return parsed.enumerated().compactMap { index, entry in
            let type = entry.1?["type"] as? String
            if type == "reasoning", !keepingReasoning { return nil }
            if index < cutoff, ["function_call", "function_call_output", "reasoning"].contains(type) { return nil }
            return entry.0
        }
    }
}
