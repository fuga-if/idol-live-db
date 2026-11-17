import SwiftUI

/// 設定の「ChatGPT」の行。状態を出して、案内の画面へ進む。
struct ChatGPTSettingsRow: View {
    private var session: ChatGPTPlanSession { .shared }

    var body: some View {
        NavigationLink {
            ChatGPTSettingsView()
        } label: {
            ImasNavRow(
                title: session.isSignedIn ? (session.registration?.email ?? "ChatGPT") : "ChatGPT とつなぐ",
                subtitle: session.isSignedIn
                    ? "文で探せます"
                    : "文で探せるようになります",
                systemImage: "text.magnifyingglass",
                value: session.isSignedIn ? "連携中" : nil,
                showsChevron: false
            )
        }
    }
}

/// ChatGPT 連携の案内と状態。
///
/// 推論は利用者の ChatGPT プランで回る (このアプリからの請求は無い)。使えるのは
/// ChatGPT Plus / Pro のアカウントだけで、プラン外は推論時に ChatGPT 側で弾かれる。
struct ChatGPTSettingsView: View {
    private var session: ChatGPTPlanSession { .shared }

    @State private var errorMessage: String?
    @State private var signOutNote: String?
    @State private var confirmSignOut = false
    @State private var searchQuery: NaturalSearchQuery?
    @State private var assistantOrder: AssistantOrder?
    /// タブバーの並び (設定の「タブバー」と同じ保存先)。
    @AppStorage(TabBarSettings.storageKey) private var tabBarOrder: String = ""
    @State private var offersChatTab = false

    /// チャットをタブバーにどう入れられるか (入れ替えられる枠・空きの有無はコアが決める)。
    private var chatTab: ChatTabOffer {
        chatTabOffer(lyricsAvailable: LyricsFeature.isAvailable, tabKeys: TabBarSettings.keys(tabBarOrder))
    }

    private func putChatInTabBar(replacing key: String?) {
        AppAnalytics.tap(key == nil ? "assistant.tab_add" : "assistant.tab_replace")
        tabBarOrder = tabBarKeysWithChat(lyricsAvailable: LyricsFeature.isAvailable,
                                         tabKeys: TabBarSettings.keys(tabBarOrder), replaceKey: key)
            .joined(separator: ",")
    }

    private static let usageURL = URL(string: "https://chatgpt.com/#settings")!

    var body: some View {
        List {
            if session.isSignedIn {
                connectedSections
            } else {
                setupSections
            }
        }
        .listStyle(.insetGrouped)
        .imasForm()
        .navigationTitle("ChatGPT")
        .navigationBarTitleDisplayMode(.inline)
        .imasErrorAlert("ChatGPT とつなげませんでした", message: $errorMessage)
        .sheet(item: $searchQuery) { NaturalSearchSheet(initialQuery: $0.text) }
        .sheet(item: $assistantOrder) { AssistantSheet(initialOrder: $0.text) }
        .task { try? await session.loadModelsIfNeeded() }
        // つないだら 1 回、チャットをタブバーに入れるかを訊く (勝手には入れ替えない)。
        .onChange(of: session.canUsePlan) { old, new in
            if !old, new, !chatTab.alreadyIn { offersChatTab = true }
        }
        .confirmationDialog("チャットをタブバーに入れますか？", isPresented: $offersChatTab, titleVisibility: .visible) {
            if chatTab.hasRoom {
                Button("空いている枠に入れる") { putChatInTabBar(replacing: nil) }
            }
            ForEach(chatTab.replaceable, id: \.analyticsKey) { item in
                Button("「\(item.label)」と入れ替える") { putChatInTabBar(replacing: item.analyticsKey) }
            }
            Button("入れない", role: .cancel) {}
        } message: {
            Text("タブバーに置けるのは 5 つまでです。入れ替えた画面は、プロデュースの「そのほか」から開けます。あとで設定の「タブバー」で変えられます。")
        }
        .trackScreen("chatgpt_settings")
    }

    // MARK: - 連携中

    @ViewBuilder
    private var connectedSections: some View {
        ImasListSection("ChatGPT", footer: signOutNote) {
            ImasRow(
                title: session.registration?.email ?? "ChatGPT アカウント",
                subtitle: session.canUsePlan ? "連携中" : "プランの利用が許可されていません",
                leading: .icon(session.canUsePlan ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", tone: .solid),
                titleRole: .rowLabel
            )
            if !session.canUsePlan {
                ImasActionRow(title: "ChatGPT プランの利用を許可する", systemImage: "checkmark.seal",
                              isLoading: session.isSigningIn) {
                    startSignIn(.enablePlan)
                }
            } else if session.models.count > 1 {
                ImasMenuRow(title: "モデル", systemImage: "cpu",
                            options: session.models.map(\.slug),
                            selection: modelSelection) { slug in
                    session.models.first { $0.slug == slug }?.label ?? slug
                }
            }
        }
        if session.canUsePlan {
            ImasListSection("文で探す", footer: "曲・アイドル・ライブの一覧の検索欄に文を打つと、「文で探す」が出ます。出てくるのはデータベースにあるものだけです。ライブのセトリ画面の ♪ メニューにある「予習 DJ」では、注文を聞いて曲を並べ、1 曲ごとの語りを付けます。") {
                ForEach(naturalSearchExamples(), id: \.self) { example in
                    Button {
                        AppAnalytics.tap("natural_search.example")
                        searchQuery = NaturalSearchQuery(text: example)
                    } label: {
                        ImasNavRow(title: example, systemImage: "text.magnifyingglass", iconTone: .neutral)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if session.canUsePlan {
            ImasListSection("チャット", footer: "データベースを引いて質問に答えます。参加の記録・お気に入り・プレイリスト・収支など、アプリの中で自分でできる操作も頼めます。頼んだ操作は一覧で確かめてから実行します。歌詞やコールのように人が書くものは、その画面を開くところまでです。あなたの記録 (参加・お気に入り・担当・収支など) は、訊かれたことに答えるのに要るときだけ ChatGPT に送ります。") {
                Button {
                    AppAnalytics.tap("assistant.open")
                    assistantOrder = AssistantOrder(text: "")
                } label: {
                    ImasNavRow(title: "チャットを開く", systemImage: "bubble.left.and.text.bubble.right", iconTone: .neutral)
                }
                .buttonStyle(.plain)
                if !chatTab.alreadyIn {
                    ImasActionRow(title: "チャットをタブバーに入れる", systemImage: "dock.rectangle") {
                        offersChatTab = true
                    }
                }
            }
        }
        ImasListSection(footer: "探すたび・話すたびに ChatGPT のプランの利用量を使います。このアプリからの請求はありません。") {
            Link(destination: Self.usageURL) {
                ImasNavRow(title: "ChatGPT の設定を開く", systemImage: "arrow.up.right.square", showsChevron: false)
            }
            ImasActionRow(title: "連携を解除", systemImage: "rectangle.portrait.and.arrow.right", kind: .destructive) {
                confirmSignOut = true
            }
        }
        .confirmationDialog("ChatGPT との連携を解除しますか？", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("解除する", role: .destructive) {
                Task {
                    let revoked = await session.signOut()
                    signOutNote = revoked ? nil : "ChatGPT 側の解除は確認できませんでした。ChatGPT の設定から連携を外せます。"
                }
            }
            Button("やめる", role: .cancel) {}
        }
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: {
                naturalSearchPickModel(available: session.models.map(\.slug), saved: session.savedModel) ?? ""
            },
            set: { session.savedModel = $0 }
        )
    }

    // MARK: - つなぐ

    @ViewBuilder
    private var setupSections: some View {
        ImasListSection {
            Text("ChatGPT とつなぐと、「去年の合同ライブに出たシャニマスのアイドル」のような文で探せるようになります。")
                .imasText(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, DS.Space.gapTight)
        }
        ImasListSection("つなぐ", footer: "ブラウザで ChatGPT にログインして許可すると、自動でアプリに戻ります。") {
            ImasPointList(points: [
                .init("waveform", "ライブ前の「予習 DJ」で、注文どおりに曲を並べて語りを付けてもらえます。"),
                .init("person.crop.circle.badge.checkmark", "ChatGPT Plus か Pro のアカウントが要ります。"),
                .init("yensign.circle", "料金は ChatGPT のプランに含まれます。このアプリからの請求はありません。"),
                .init("lock", "ログインの情報はこの端末の中にだけ保存します。"),
            ])
            .padding(.vertical, DS.Space.gapTight)
            ImasButton(title: "ChatGPT でログイン", systemImage: "person.crop.circle.badge.checkmark",
                       role: .primary, size: .large, fillsWidth: true, isLoading: session.isSigningIn) {
                startSignIn(.signIn)
            }
            .padding(.vertical, DS.Space.gapTight)
            if session.isSigningIn {
                ImasActionRow(title: "ログインをやめる", systemImage: "xmark") { session.cancelSignIn() }
            } else if session.registration != nil {
                ImasActionRow(title: "別のアカウントでログイン", systemImage: "person.2") { startSignIn(.newAccount) }
            }
        }
    }

    // MARK: - 処理

    private func startSignIn(_ intent: ChatGptSignInIntent) {
        errorMessage = nil
        signOutNote = nil
        AppAnalytics.tap("chatgpt.sign_in")
        Task {
            do {
                try await session.signIn(intent: intent)
                try? await session.loadModelsIfNeeded()
            } catch LoopbackCallbackServer.ServerError.cancelled {
                // 自分でやめた。何も出さない。
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
