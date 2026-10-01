import SwiftUI

/// Sign in with ChatGPT の管理画面 (試作)。サインイン / サインアウト / 使用状況 / 接続の記録。
/// 質問するのはメイン画面右上から開くチャット (`AssistantChatView`)。
///
/// 使えるのは ChatGPT Plus / Pro のアカウントだけ (プラン外は推論時に
/// `subscription_sharing_user_not_eligible` で弾かれる)。
struct ChatGPTPlanLabView: View {
    private var session: ChatGPTPlanSession { .shared }

    @AppStorage("chatgpt_plan.browser_mode") private var browserModeRaw = ChatGPTPlanBrowser.Mode.authSession.rawValue
    @State private var signInError: String?
    @State private var signOutNote: String?
    @AppStorage(CharacterFeatures.enabledKey) private var characterFeatures = false
    @State private var confirmCharacterFeatures = false

    private var browserMode: Binding<ChatGPTPlanBrowser.Mode> {
        Binding(
            get: { ChatGPTPlanBrowser.Mode(rawValue: browserModeRaw) ?? .authSession },
            set: { browserModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        List {
            accountSection
            if session.isSignedIn, !session.canUsePlan {
                planDisabledSection
            }
            characterSection
            if !session.log.isEmpty || signInError != nil {
                logSection
            }
        }
        .listStyle(.insetGrouped)
        .imasForm()
        .navigationTitle("ChatGPT 連携 (試作)")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - アカウント

    @ViewBuilder
    private var accountSection: some View {
        ImasListSection(
            "ChatGPT",
            footer: signOutNote ?? (session.isSignedIn ? nil : "ブラウザで ChatGPT にサインインして許可すると、自動でアプリに戻ります。うまく戻らないときはブラウザの方式を切り替えて試してください。")
        ) {
            if session.isSignedIn {
                ImasRow(
                    title: session.registration?.email ?? "ChatGPT アカウント",
                    subtitle: session.canUsePlan ? "Using ChatGPT plan" : nil,
                    leading: .icon("checkmark.seal.fill", tone: .positive),
                    titleRole: .rowLabel
                )
                if let expires = session.tokens?.expiresAt {
                    ImasValueRow(key: "アクセストークン期限", value: expires.formatted(date: .omitted, time: .shortened))
                }
                ImasActionRow(title: "トークンを更新", systemImage: "arrow.clockwise") {
                    Task {
                        do { try await session.refresh() } catch { signInError = error.localizedDescription }
                    }
                }
                Link(destination: chatGPTUsageURL) {
                    ImasNavRow(title: "ChatGPT の使用状況を見る (Manage usage)", systemImage: "chart.bar")
                }
                ImasActionRow(title: "サインアウト", systemImage: "rectangle.portrait.and.arrow.right", kind: .destructive) {
                    Task {
                        let revoked = await session.signOut()
                        signOutNote = revoked ? nil : "ChatGPT 側の失効は確認できませんでした。ChatGPT の設定から連携を解除できます。"
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    Text("ChatGPT Plus / Pro のプランで AI 機能を使います。料金は ChatGPT のプランに含まれ、このアプリからの請求はありません。")
                        .imasText(.note)
                    continueButton
                    if session.registration != nil, !session.isSigningIn {
                        Button("別のアカウントで登録") { startSignIn(.newAccount) }
                            .font(.imasFootnote.weight(.semibold))
                    }
                    if session.isSigningIn {
                        Button("中止", role: .cancel) { session.cancelSignIn() }
                            .font(.imasFootnote.weight(.semibold))
                    }
                }
                .padding(.vertical, DS.Space.gapTight)

                ImasMenuRow(
                    title: "ブラウザ",
                    options: ChatGPTPlanBrowser.Mode.allCases,
                    selection: browserMode
                ) { mode in mode.label }
            }
        }
    }

    private var continueButton: some View {
        ImasButton(title: "Continue with ChatGPT", systemImage: "sparkles", role: .primary, size: .large,
                   fillsWidth: true, isLoading: session.isSigningIn) {
            startSignIn(.signIn)
        }
    }

    /// キャラとのトーク・タイムライン。既定 OFF のオプトイン。有効にする前に非公式であることを確かめる。
    @ViewBuilder
    private var characterSection: some View {
        ImasListSection(
            "キャラ機能 (試作)",
            footer: "好きなアイドルとメッセージでおしゃべりしたり、アイドルどうしの SNS 風のやりとりを見たりできます。\(CharacterFeatures.disclaimer) 使うと ChatGPT のプランの利用量を消費します。"
        ) {
            ImasToggleRow(title: "キャラとのトーク・タイムライン", isOn: Binding(
                get: { characterFeatures },
                set: { on in
                    if on { confirmCharacterFeatures = true } else { characterFeatures = false }
                }
            ))
        }
        .alert("キャラ機能を有効にしますか？", isPresented: $confirmCharacterFeatures) {
            Button("有効にする") { characterFeatures = true }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("アイドルの発言はすべて \(CharacterFeatures.disclaimer) 会話は端末内に保存されます。")
        }
    }

    @ViewBuilder
    private var planDisabledSection: some View {
        ImasListSection {
            ImasNote("このサインインには ChatGPT プランの利用許可 (chatgpt.tokens.use.direct) が含まれていません。")
                .padding(.horizontal, DS.Space.rowH)
                .padding(.vertical, DS.Space.gapTight)
            ImasActionRow(title: "ChatGPT プランの利用を許可する", systemImage: "checkmark.seal") {
                startSignIn(.enablePlan)
            }
            .disabled(session.isSigningIn)
        }
    }

    @ViewBuilder
    private var logSection: some View {
        ImasListSection("接続の記録") {
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                ForEach(Array(session.log.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.imasCaption2.monospaced()).foregroundStyle(DS.ink2)
                }
                if let signInError {
                    Text(signInError).imasText(.note, color: DS.warning).textSelection(.enabled)
                }
            }
            .padding(.horizontal, DS.Space.rowH)
            .padding(.vertical, DS.Space.gapTight)
        }
    }

    // MARK: - 処理

    private func startSignIn(_ intent: ChatGPTPlanSession.Intent) {
        signInError = nil
        signOutNote = nil
        Task {
            do {
                try await session.signIn(mode: browserMode.wrappedValue, intent: intent)
            } catch {
                signInError = error.localizedDescription
            }
        }
    }
}
