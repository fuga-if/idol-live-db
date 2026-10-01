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
            if !session.log.isEmpty || signInError != nil {
                logSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle("ChatGPT 連携 (試作)")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - アカウント

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if session.isSignedIn {
                HStack(spacing: DS.sp4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.imasTitle2)
                        .foregroundStyle(DS.ink2)
                    VStack(alignment: .leading, spacing: DS.sp1) {
                        Text(session.registration?.email ?? "ChatGPT アカウント")
                            .font(.imasHeadline)
                        if session.canUsePlan {
                            Text("Using ChatGPT plan")
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink2)
                        }
                        if let expires = session.tokens?.expiresAt {
                            Text("アクセストークン期限 \(expires.formatted(date: .omitted, time: .shortened))")
                                .font(.imasCaption2)
                                .foregroundStyle(DS.ink3)
                        }
                    }
                }
                Button("トークンを更新") {
                    Task {
                        do { try await session.refresh() } catch { signInError = error.localizedDescription }
                    }
                }
                Link("ChatGPT の使用状況を見る (Manage usage)", destination: chatGPTUsageURL)
                Button("サインアウト", role: .destructive) {
                    Task {
                        let revoked = await session.signOut()
                        signOutNote = revoked ? nil : "ChatGPT 側の失効は確認できませんでした。ChatGPT の設定から連携を解除できます。"
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: DS.sp4) {
                    Text("ChatGPT Plus / Pro のプランで AI 機能を使います。料金は ChatGPT のプランに含まれ、このアプリからの請求はありません。")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                    continueButton
                    if session.registration != nil, !session.isSigningIn {
                        Button("別のアカウントで登録") { startSignIn(.newAccount) }
                            .font(.imasCaption)
                    }
                    if session.isSigningIn {
                        Button("中止", role: .cancel) { session.cancelSignIn() }
                            .font(.imasCaption)
                    }
                }
                .padding(.vertical, DS.sp2)

                Picker("ブラウザ", selection: browserMode) {
                    ForEach(ChatGPTPlanBrowser.Mode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .font(.imasCaption)
            }
        } header: {
            Text("ChatGPT")
        } footer: {
            if let signOutNote {
                Text(signOutNote)
            } else if !session.isSignedIn {
                Text("ブラウザで ChatGPT にサインインして許可すると、自動でアプリに戻ります。うまく戻らないときはブラウザの方式を切り替えて試してください。")
            }
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    private var continueButton: some View {
        Button {
            startSignIn(.signIn)
        } label: {
            HStack(spacing: DS.sp3) {
                if session.isSigningIn {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "sparkles")
                }
                Text("Continue with ChatGPT")
                    .font(.imasHeadline)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(.white)
            .background(Color.black, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(session.isSigningIn)
    }

    @ViewBuilder
    private var planDisabledSection: some View {
        Section {
            Text("このサインインには ChatGPT プランの利用許可 (chatgpt.tokens.use.direct) が含まれていません。")
                .font(.imasCaption)
                .foregroundStyle(DS.ink2)
            Button("ChatGPT プランの利用を許可する") { startSignIn(.enablePlan) }
                .disabled(session.isSigningIn)
        }
        .listRowBackground(DS.surface)
    }

    @ViewBuilder
    private var logSection: some View {
        Section {
            ForEach(Array(session.log.enumerated()), id: \.offset) { _, line in
                Text(line).font(.imasCaption2.monospaced()).foregroundStyle(DS.ink2)
            }
            if let signInError {
                Text(signInError).font(.imasCaption).foregroundStyle(DS.warning).textSelection(.enabled)
            }
        } header: {
            Text("接続の記録")
        }
        .listRowBackground(DS.surface)
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
