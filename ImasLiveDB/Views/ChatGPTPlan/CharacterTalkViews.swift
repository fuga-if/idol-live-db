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
        HStack(spacing: DS.sp2) {
            Image(systemName: "sparkles")
            Text("AI・非公式")
                .fontWeight(.semibold)
            Text("公式の発言ではありません")
        }
        .font(.imasCaption2)
        .foregroundStyle(DS.ink2)
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, DS.sp2)
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
            Section {
                CharacterDisclaimerBadge()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            if store.sorted.isEmpty {
                Section {
                    VStack(spacing: DS.sp4) {
                        Text("好きなアイドルとメッセージでおしゃべりできます")
                            .font(.imasCallout)
                            .foregroundStyle(DS.ink2)
                            .multilineTextAlignment(.center)
                        Button("アイドルを選ぶ") { showPicker = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.sp7)
                    .listRowBackground(DS.surface)
                }
            }
            Section {
                ForEach(store.sorted) { conversation in
                    if let idolID = conversation.idolID {
                        Button { openIdolID = idolID } label: { row(conversation, idolID: idolID) }
                            .listRowBackground(DS.surface)
                            .swipeActions {
                                Button("削除", role: .destructive) { store.delete(conversation.id) }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DS.bg.ignoresSafeArea())
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

    private func row(_ conversation: AssistantConversation, idolID: String) -> some View {
        HStack(spacing: DS.sp4) {
            if let idol = cache.idols[idolID] {
                IdolAvatarView(idol: idol, size: 44, reservesPickRing: false)
            } else {
                Circle().fill(DS.fill).frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: DS.sp1) {
                HStack {
                    Text(cache.idols[idolID]?.name ?? conversation.title)
                        .font(.imasHeadline)
                        .foregroundStyle(DS.ink)
                    Spacer()
                    Text(conversation.updatedAt.formatted(.relative(presentation: .numeric)))
                        .font(.imasCaption2)
                        .foregroundStyle(DS.ink3)
                }
                Text(conversation.messages.last?.text ?? "")
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink2)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, DS.sp2)
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
    private var partnerTint: Color {
        Color(hexString: idol?.color, default: DS.surface).opacity(0.18)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let chat {
                messages(chat)
                AssistantInputBar(
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
                )
            } else if let loadError {
                ContentUnavailableView(loadError, systemImage: "person.crop.circle.badge.exclamationmark")
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle(idol?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { chat?.usageLimitHit ?? false }, set: { chat?.usageLimitHit = $0 })) {
            AssistantUsageLimitSheet()
        }
        .task { await prepare() }
    }

    private func messages(_ chat: AssistantChatModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.sp4) {
                    CharacterDisclaimerBadge()
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, DS.sp2)
                    ForEach(chat.conversation.messages) { message in
                        if message.failed {
                            AssistantFailedBubble(message: chat.errorMessage) { chat.retry(model: selectedModel) }
                        } else {
                            AssistantBubble(message: message, partnerName: idol?.name, partnerTint: partnerTint) { avatar }
                        }
                    }
                    if chat.isRunning {
                        if let label = chat.toolLabel { AssistantToolChip(label: label).padding(.leading, 44) }
                        AssistantStreamingBubble(text: chat.streamingText, partnerTint: partnerTint) { avatar }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp4)
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
            Circle().fill(DS.fill).frame(width: 34, height: 34)
        }
    }

    /// 人格の指示文をコアで組み、このアイドルとの会話 (あれば続き) を開く。
    private func prepare() async {
        guard chat == nil else { return }
        await cache.load([idolID])
        do {
            try await session.loadModelsIfNeeded()
            if !session.models.contains(where: { $0.slug == selectedModel }) {
                selectedModel = session.models.first?.slug ?? ""
            }
            let store = try await AppContainer.shared.coreSnapshot.loadedStore()
            guard let instructions = try store.assistantTalkInstructions(idolId: idolID) else {
                loadError = "このアイドルのデータが見つかりませんでした"
                return
            }
            let name = idol?.name ?? ""
            let existing = AssistantConversationStore.talk.conversations.first { $0.idolID == idolID }
            chat = AssistantChatModel(
                config: .init(
                    store: .talk,
                    instructions: { instructions },
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
