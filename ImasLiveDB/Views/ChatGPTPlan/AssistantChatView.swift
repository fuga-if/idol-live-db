import SwiftUI

/// ChatGPT プランで DB に質問するチャット (試作)。メイン画面のナビゲーションバー右上から開く。
///
/// ツール (曲・公演・セトリ・参戦記録の読み取り) はコアの MCP と同じツール面。
/// 会話は端末内に保存し、毎回 input に積み直す (store: false)。
struct AssistantChatView: View {
    @Environment(\.dismiss) private var dismiss
    private var session: ChatGPTPlanSession { .shared }

    var body: some View {
        NavigationStack {
            Group {
                if session.isSignedIn, session.canUsePlan {
                    AssistantHome()
                } else {
                    AssistantSignInGate()
                        .background(DS.bg.ignoresSafeArea())
                }
            }
            .imasSheetToolbar(.read(onClose: { dismiss() }))
        }
    }
}

/// サインイン済みの中身。キャラ機能を有効にしていれば、質問 / トーク / タイムラインを切り替える。
private struct AssistantHome: View {
    enum Mode: String, CaseIterable, Identifiable {
        case ask, talk, timeline
        var id: String { rawValue }
        var label: String {
            switch self {
            case .ask: "質問"
            case .talk: "トーク"
            case .timeline: "タイムライン"
            }
        }
    }

    private var session: ChatGPTPlanSession { .shared }
    @AppStorage(CharacterFeatures.enabledKey) private var characterFeatures = false
    @AppStorage("chatgpt_plan.home_mode") private var modeRaw = Mode.ask.rawValue
    @AppStorage("chatgpt_plan.model") private var selectedModel = ""
    @AppStorage("chatgpt_plan.plan_notice_seen") private var planNoticeSeen = false
    @State private var modelsError: String?

    private var mode: Mode { characterFeatures ? Mode(rawValue: modeRaw) ?? .ask : .ask }

    var body: some View {
        VStack(spacing: 0) {
            if characterFeatures {
                ImasSegmented(
                    options: Mode.allCases.map(\.rawValue),
                    selection: $modeRaw
                ) { raw in Mode(rawValue: raw)?.label ?? raw }
                .padding(.horizontal, DS.Space.screen)
                .padding(.vertical, DS.Space.gap)
            }
            if let modelsError {
                HStack(alignment: .firstTextBaseline) {
                    Text("モデルの一覧を読み込めませんでした: \(modelsError)").imasText(.note, color: DS.warning)
                    Spacer()
                    Button("再読み込み") { Task { await loadModels() } }
                        .font(.imasFootnote.weight(.semibold))
                }
                .padding(.horizontal, DS.Space.screen)
            }
            switch mode {
            case .ask: AssistantChatScreen()
            case .talk: CharacterTalkListView()
            case .timeline: CharacterTimelineView()
            }
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { modelMenu }
        }
        .task { await loadModels() }
        .alert("ChatGPT プランを使っています", isPresented: Binding(get: { !planNoticeSeen }, set: { if !$0 { planNoticeSeen = true } })) {
            Button("Got it") { planNoticeSeen = true }
        } message: {
            Text("ここでの応答は、サインインした ChatGPT アカウントのプランで生成されます。質問に答えるため、あなたの参戦記録をアプリから ChatGPT に送ることがあります。")
        }
    }

    private var modelMenu: some View {
        Menu {
            Picker("モデル", selection: $selectedModel) {
                ForEach(session.models) { model in
                    Text(model.label).tag(model.slug)
                }
            }
        } label: {
            HStack(spacing: DS.Space.gapTight) {
                Text(session.models.first { $0.slug == selectedModel }?.label ?? "モデル")
                    .font(.imasSubhead.weight(.semibold))
                Image(systemName: "chevron.down").font(.imasCaption2.weight(.bold))
            }
            .foregroundStyle(DS.ink)
        }
        .accessibilityLabel("モデルを選ぶ")
    }

    private func loadModels() async {
        modelsError = nil
        do {
            try await session.loadModelsIfNeeded()
            if !session.models.contains(where: { $0.slug == selectedModel }) {
                selectedModel = session.models.first?.slug ?? ""
            }
        } catch {
            modelsError = error.localizedDescription
        }
    }
}

/// 質問 (DB を引いて答える) のチャット。
private struct AssistantChatScreen: View {
    private var session: ChatGPTPlanSession { .shared }
    private var store: AssistantConversationStore { .chat }

    @State private var chat = AssistantChatModel(config: .init(
        store: .chat,
        instructions: { _ in assistantInstructions() },
        toolsJSON: assistantToolsJson(),
        idolID: nil,
        newTitle: { String($0.prefix(40)) }
    ))
    @AppStorage("chatgpt_plan.model") private var selectedModel = ""
    @State private var input = ""
    @State private var showHistory = false

    private let examples = assistantExamplePrompts()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.Space.gap) {
                        if chat.isEmpty {
                            emptyState
                        }
                        ForEach(chat.conversation.messages) { message in
                            if message.failed {
                                ImasChatBubble(role: .assistant,
                                               content: .failed(message: chat.errorMessage) { chat.retry(model: selectedModel) })
                            } else {
                                ImasChatBubble(role: message.role.chatRole, content: .text(message.text))
                            }
                        }
                        if chat.isRunning {
                            if let label = chat.toolLabel { ImasChatToolChip(label: label) }
                            ImasChatBubble(role: .assistant, content: .streaming(chat.streamingText))
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, DS.Space.screen)
                    .padding(.vertical, DS.Space.gap)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.streamingText) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: chat.conversation.messages.count) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            ImasChatComposer(
                text: $input,
                placeholder: "ライブやセトリについて質問",
                isRunning: chat.isRunning,
                canSend: !selectedModel.isEmpty && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onSend: send,
                onStop: { chat.stop() }
            ) {
                AssistantPlanFooter()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("会話の履歴")
                Button { chat.startNew(); input = "" } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("新しい会話")
                    .disabled(chat.conversation.messages.isEmpty)
            }
        }
        .sheet(isPresented: $showHistory) {
            AssistantHistoryView(store: store) { id in chat.open(id) }
        }
        .sheet(isPresented: $chat.usageLimitHit) { AssistantUsageLimitSheet() }
        // モードを切り替えるとこの画面ごと作り直されるので、走っている応答はここで止めて残す。
        .onDisappear { chat.leave() }
    }

    // MARK: - 部品

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            Text("何でも聞いてください")
                .imasText(.sectionTitle)
                .padding(.top, DS.Space.section)
            Text("曲・ライブ・セトリ・あなたの参戦記録をデータベースから調べて答えます。参戦記録を使うときは、その内容を ChatGPT に送ります。")
                .imasText(.note)
            FlowChips(items: examples, isEnabled: !selectedModel.isEmpty) { example in
                input = ""
                chat.send(example, model: selectedModel)
            }
            .padding(.top, DS.Space.gapTight)
        }
    }

    private func send() {
        let text = input
        input = ""
        chat.send(text, model: selectedModel)
    }
}

/// 質問例のチップ。幅に合わせて折り返す。
private struct FlowChips: View {
    let items: [String]
    let isEnabled: Bool
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    ImasCard {
                        Text(item).imasText(.body).multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.imasPress)
                .disabled(!isEnabled)
            }
        }
    }
}

/// 会話の履歴。
struct AssistantHistoryView: View {
    let store: AssistantConversationStore
    let onOpen: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ImasListSection {
                    if store.sorted.isEmpty {
                        ImasEmptyState(systemImage: "clock", title: "まだ会話がありません")
                    }
                    ForEach(store.sorted) { conversation in
                        Button {
                            onOpen(conversation.id)
                            dismiss()
                        } label: {
                            ImasRow(
                                title: conversation.title.isEmpty ? "新しい会話" : conversation.title,
                                subtitle: conversation.updatedAt.formatted(date: .abbreviated, time: .shortened),
                                titleRole: .rowLabel
                            )
                        }
                        .buttonStyle(.imasRow)
                        .swipeActions {
                            Button("削除", role: .destructive) { store.delete(conversation.id) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .imasForm()
            .navigationTitle("会話の履歴")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
        }
    }
}

/// メイン画面のナビゲーションバー右上に置く入口。開発ビルドと TestFlight だけに出す。
struct AssistantToolbarButton: View {
    var body: some View {
        if ChatGPTPlanSession.isPrototypeVisible {
            Button {
                NotificationCenter.default.post(name: .openAssistant, object: nil)
            } label: {
                Image(systemName: "sparkles")
            }
            .accessibilityLabel("ChatGPT に質問")
        }
    }
}

extension Notification.Name {
    static let openAssistant = Notification.Name("ImasLiveDB.openAssistant")
}
