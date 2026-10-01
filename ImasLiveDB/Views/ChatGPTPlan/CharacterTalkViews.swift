import SwiftUI

/// キャラ機能で出すアイドルの引き当て (アイコン・名前・色)。id → Idol を覚えておく。
@MainActor
@Observable
final class CharacterIdolCache {
    static let shared = CharacterIdolCache()
    private(set) var idols: [String: Idol] = [:]

    func load(_ ids: some Sequence<String>) async {
        let missing = Set(ids).subtracting(idols.keys)
        guard !missing.isEmpty,
              let found = try? await AppContainer.shared.idolReading.idols(ids: Array(missing)) else { return }
        for idol in found { idols[idol.id] = idol }
    }
}

/// 画面上部の小さな断り (「AI・非公式」)。
struct CharacterDisclaimerBadge: View {
    var body: some View {
        HStack(spacing: DS.Space.gapTight) {
            Image(systemName: "sparkles")
            Text("AI・非公式").fontWeight(.semibold)
            Text("公式の発言ではありません")
        }
        .imasText(.meta)
        .padding(.horizontal, DS.Space.card)
        .padding(.vertical, DS.Space.gapTight)
        .background(DS.fill, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - トーク一覧

/// キャラとのトークの一覧 (1 人 1 本)。
struct CharacterTalkListView: View {
    @Environment(AppDatabase.self) private var database
    private var store: AssistantConversationStore { .talk }
    private var cache: CharacterIdolCache { .shared }
    @State private var showPicker = false
    @State private var openIdolID: String?

    var body: some View {
        List {
            ImasListSection {
                CharacterDisclaimerBadge()
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if store.sorted.isEmpty {
                ImasListSection {
                    VStack(spacing: DS.Space.gap) {
                        Text("好きなアイドルとメッセージでおしゃべりできます")
                            .imasText(.body, color: DS.ink2)
                            .multilineTextAlignment(.center)
                        ImasButton(title: "アイドルを選ぶ", role: .primary, size: .medium) { showPicker = true }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.section)
                }
            }
            ImasListSection {
                ForEach(store.sorted) { conversation in
                    if let idolID = conversation.idolID {
                        Button { openIdolID = idolID } label: { row(conversation, idolID: idolID) }
                            .buttonStyle(.imasRow)
                            .swipeActions {
                                Button("削除", role: .destructive) { store.delete(conversation.id) }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .imasForm()
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button { showPicker = true } label: { Label("新しいトーク", systemImage: "plus.bubble") }
            }
        }
        .task(id: store.conversations.count) { await cache.load(store.conversations.compactMap(\.idolID)) }
        .navigationDestination(item: $openIdolID) { idolID in
            CharacterTalkView(idolID: idolID)
        }
        .sheet(isPresented: $showPicker) {
            IdolPickerView(title: "トーク相手", mode: .single) { selection in
                if let id = selection.first { openIdolID = id }
            }
            .environment(database)
        }
    }

    @ViewBuilder
    private func row(_ conversation: AssistantConversation, idolID: String) -> some View {
        let timeLabel = conversation.updatedAt.formatted(.relative(presentation: .numeric))
        if let idol = cache.idols[idolID] {
            ImasIdolRow(idol: idol, subtitle: conversation.messages.last?.text ?? "") {
                Text(timeLabel).imasText(.meta)
            }
        } else {
            ImasRow(
                title: conversation.title,
                subtitle: conversation.messages.last?.text ?? "",
                leading: .icon("person.fill", tone: .neutral)
            ) {
                Text(timeLabel).imasText(.meta)
            }
        }
    }
}

// MARK: - トーク

/// キャラ 1 人とのトーク。LINE のように相手側にアイコンと名前を出す。
struct CharacterTalkView: View {
    let idolID: String
    private var cache: CharacterIdolCache { .shared }
    private var session: ChatGPTPlanSession { .shared }
    @AppStorage("chatgpt_plan.model") private var selectedModel = ""
    @State private var chat: AssistantChatModel?
    @State private var input = ""
    @State private var loadError: String?

    private var idol: Idol? { cache.idols[idolID] }

    var body: some View {
        VStack(spacing: 0) {
            if let chat {
                messages(chat)
                ImasChatComposer(
                    text: $input,
                    placeholder: "メッセージ",
                    isRunning: chat.isRunning,
                    canSend: !selectedModel.isEmpty && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onSend: {
                        let text = input
                        input = ""
                        chat.send(text, model: selectedModel)
                    },
                    onStop: { chat.stop() }
                ) {
                    AssistantPlanFooter()
                }
            } else if let loadError {
                ImasEmptyState(systemImage: "person.crop.circle.badge.exclamationmark", title: loadError)
                    .frame(maxHeight: .infinity)
            } else {
                ImasLoadingState()
            }
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle(idol?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { chat?.usageLimitHit ?? false }, set: { chat?.usageLimitHit = $0 })) {
            AssistantUsageLimitSheet()
        }
        .task { await prepare() }
        // 戻るときは走っている応答を止めて残す (開き直したときに古い応答が後から書き込まないように)。
        .onDisappear { chat?.leave() }
    }

    private func messages(_ chat: AssistantChatModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.gap) {
                    CharacterDisclaimerBadge()
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, DS.Space.gapTight)
                    ForEach(chat.conversation.messages) { message in
                        if message.failed {
                            ImasChatBubble(role: .assistant,
                                           content: .failed(message: chat.errorMessage) { chat.retry(model: selectedModel) },
                                           partnerName: idol?.name, seed: idol?.color) { avatar }
                        } else {
                            ImasChatBubble(role: message.role.chatRole, content: .text(message.text),
                                           partnerName: idol?.name, seed: idol?.color) { avatar }
                        }
                    }
                    if chat.isRunning {
                        if let label = chat.toolLabel {
                            ImasChatToolChip(label: label).padding(.leading, DS.Size.touch)
                        }
                        ImasChatBubble(role: .assistant, content: .streaming(chat.streamingText),
                                       partnerName: idol?.name, seed: idol?.color) { avatar }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.vertical, DS.Space.gap)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.streamingText) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.conversation.messages.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let idol {
            IdolAvatarView(idol: idol, size: 34, reservesPickRing: false)
        } else {
            ImasIconTile(systemImage: "person.fill", size: .s32, tone: .neutral)
        }
    }

    /// 人格の指示文をコアで組み、このアイドルとの会話 (あれば続き) を開く。
    private func prepare() async {
        guard chat == nil else { return }
        await cache.load([idolID])
        // モデル一覧が取れなくても、前に選んだモデルがあればそのまま話せる。
        try? await session.loadModelsIfNeeded()
        if !session.models.isEmpty, !session.models.contains(where: { $0.slug == selectedModel }) {
            selectedModel = session.models.first?.slug ?? ""
        }
        do {
            let store = try await AppContainer.shared.coreSnapshot.loadedStore()
            guard try store.assistantTalkInstructions(idolId: idolID, recentReplies: []) != nil else {
                loadError = "このアイドルのデータが見つかりませんでした"
                return
            }
            let idolID = idolID
            let name = idol?.name ?? ""
            let existing = AssistantConversationStore.talk.conversations.first { $0.idolID == idolID }
            chat = AssistantChatModel(
                config: .init(
                    store: .talk,
                    // 直近の返信に出た口癖は、今回は使わないよう指示文に添える (コアが判定する)。
                    instructions: { messages in
                        let recent = messages.filter { $0.role == .assistant && !$0.failed }.suffix(5).map(\.text)
                        return try? store.assistantTalkInstructions(idolId: idolID, recentReplies: Array(recent)) ?? nil
                    },
                    toolsJSON: assistantToolsJson(),
                    idolID: idolID,
                    newTitle: { _ in name }
                ),
                conversationID: existing?.id
            )
        } catch {
            loadError = error.localizedDescription
        }
    }
}
