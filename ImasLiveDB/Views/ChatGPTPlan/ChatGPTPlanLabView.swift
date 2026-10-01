import SwiftUI

/// Sign in with ChatGPT の試作画面。サインイン → モデル一覧 → ストリーミング推論まで通す。
///
/// 使えるのは ChatGPT Plus / Pro のアカウントだけ (プラン外は推論時に
/// `subscription_sharing_user_not_eligible` で弾かれる)。
struct ChatGPTPlanLabView: View {
    private var session: ChatGPTPlanSession { .shared }

    @AppStorage("chatgpt_plan.browser_mode") private var browserModeRaw = ChatGPTPlanBrowser.Mode.authSession.rawValue
    @State private var signInError: String?
    @State private var models: [ChatGPTPlanClient.Model] = []
    @State private var modelsError: String?
    @AppStorage("chatgpt_plan.model") private var selectedModel = ""
    @State private var prompt = "アイドルマスターのライブで定番の曲を3つ、1行ずつ挙げて"
    @State private var output = ""
    @State private var outputError: String?
    @State private var isStreaming = false
    @State private var completed = false
    @State private var streamTask: Task<Void, Never>?
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
            if session.isSignedIn {
                if session.canUsePlan {
                    trySection
                } else {
                    planDisabledSection
                }
            }
            if !session.log.isEmpty || signInError != nil {
                logSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle("ChatGPT で AI (試作)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.isSignedIn) {
            if session.isSignedIn, session.canUsePlan, models.isEmpty { await loadModels() }
        }
        .onDisappear { streamTask?.cancel() }
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
                Link("ChatGPT の使用状況を見る", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                Button("サインアウト", role: .destructive) {
                    streamTask?.cancel()
                    Task {
                        let revoked = await session.signOut()
                        models = []
                        signOutNote = revoked ? nil : "ChatGPT 側の失効は確認できませんでした。ChatGPT の設定から連携を解除できます。"
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: DS.sp4) {
                    Text("ChatGPT Plus / Pro のプランで AI 機能を使います。料金は ChatGPT のプランに含まれ、このアプリからの請求はありません。")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                    continueButton
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
            signInError = nil
            signOutNote = nil
            Task {
                do {
                    try await session.signIn(mode: browserMode.wrappedValue)
                } catch {
                    signInError = error.localizedDescription
                }
            }
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

    // MARK: - 試す

    @ViewBuilder
    private var trySection: some View {
        Section {
            if let modelsError {
                Text(modelsError).font(.imasCaption).foregroundStyle(DS.warning)
            }
            Picker("モデル", selection: $selectedModel) {
                if models.isEmpty { Text("読み込み中…").tag(selectedModel) }
                ForEach(models) { model in
                    Text(model.label).tag(model.slug)
                }
            }
            TextField("聞きたいこと", text: $prompt, axis: .vertical)
                .lineLimit(2...6)
            Button {
                isStreaming ? streamTask?.cancel() : send()
            } label: {
                Label(isStreaming ? "止める" : "送信", systemImage: isStreaming ? "stop.circle" : "paperplane")
            }
            .disabled(!isStreaming && (selectedModel.isEmpty || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

            if !output.isEmpty || isStreaming {
                VStack(alignment: .leading, spacing: DS.sp3) {
                    Text(output.isEmpty ? "…" : output)
                        .font(.imasBody)
                        .textSelection(.enabled)
                    HStack(spacing: DS.sp2) {
                        if isStreaming { ProgressView().controlSize(.mini) }
                        Text(isStreaming ? "生成中" : completed ? "Using ChatGPT plan ・ 完了" : "未完了")
                            .font(.imasCaption2)
                            .foregroundStyle(DS.ink3)
                    }
                }
                .padding(.vertical, DS.sp2)
            }
            if let outputError {
                Text(outputError).font(.imasCaption).foregroundStyle(DS.warning)
            }
        } header: {
            Text("試す")
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    @ViewBuilder
    private var planDisabledSection: some View {
        Section {
            Text("このサインインには ChatGPT プランの利用許可 (chatgpt.tokens.use.direct) が含まれていません。サインアウトしてもう一度許可してください。")
                .font(.imasCaption)
                .foregroundStyle(DS.ink2)
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

    private func loadModels() async {
        modelsError = nil
        do {
            let token = try await session.validAccessToken()
            models = try await ChatGPTPlanClient.listModels(accessToken: token)
            if !models.contains(where: { $0.slug == selectedModel }) {
                selectedModel = models.first?.slug ?? ""
            }
        } catch {
            modelsError = error.localizedDescription
        }
    }

    private func send() {
        output = ""
        outputError = nil
        completed = false
        isStreaming = true
        let model = selectedModel
        let text = prompt
        streamTask = Task {
            defer { isStreaming = false }
            do {
                let token = try await session.validAccessToken()
                for try await event in ChatGPTPlanClient.stream(model: model, prompt: text, accessToken: token) {
                    switch event {
                    case .delta(let delta): output += delta
                    case .completed: completed = true
                    }
                }
            } catch is CancellationError {
                outputError = "止めました"
            } catch {
                outputError = error.localizedDescription
            }
        }
    }
}
