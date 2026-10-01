import Foundation
import Observation

/// チャット 1 画面ぶんの状態。普通のチャットとキャラとのトークで共用する
/// (違うのは指示文とツールと保存先だけ)。
@MainActor
@Observable
final class AssistantChatModel {
    struct Config {
        var store: AssistantConversationStore
        var instructions: () -> String?
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
        guard !isRunning, let found = config.store.conversation(id) else { return }
        conversation = found
        errorMessage = nil
    }

    func startNew() {
        stop()
        conversation = AssistantConversation(title: "", idolID: config.idolID)
        errorMessage = nil
    }

    func send(_ text: String, model: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning, !model.isEmpty else { return }
        if conversation.title.isEmpty { conversation.title = config.newTitle(text) }
        conversation.messages.append(AssistantMessage(role: .user, text: text))
        conversation.items.append(ChatGPTPlanClient.userMessage(text))
        config.store.upsert(conversation)
        run(model: model)
    }

    /// 失敗した応答をやり直す (最後の発言はそのまま)。
    func retry(model: String) {
        guard !isRunning else { return }
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
        let history = conversation.items
        task = Task {
            defer {
                isRunning = false
                toolLabel = nil
            }
            do {
                let added = try await AssistantTurnRunner.run(
                    model: model,
                    history: history,
                    instructions: config.instructions(),
                    toolsJSON: config.toolsJSON
                ) { event in
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
                conversation.items += added
                conversation.messages.append(AssistantMessage(role: .assistant, text: streamingText))
                streamingText = ""
                config.store.upsert(conversation)
            } catch is CancellationError {
                keepPartialAnswer()
            } catch {
                if Task.isCancelled {
                    keepPartialAnswer()
                    return
                }
                streamingText = ""
                if let clientError = error as? ChatGPTPlanClient.ClientError, clientError.isUsageLimit {
                    usageLimitHit = true
                }
                errorMessage = error.localizedDescription
                conversation.messages.append(AssistantMessage(role: .assistant, text: "", failed: true))
            }
        }
    }

    /// 止めた応答は、出たところまでを発言として残し、次の input にも積む。
    private func keepPartialAnswer() {
        guard !streamingText.isEmpty else { return }
        conversation.messages.append(AssistantMessage(role: .assistant, text: streamingText))
        conversation.items.append(ChatGPTPlanClient.jsonString([
            "role": "assistant", "content": streamingText,
        ]))
        streamingText = ""
        config.store.upsert(conversation)
    }
}
