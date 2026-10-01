import SwiftUI

/// ChatGPT 側の使用状況ページ。OpenAI の UI/UX ガイドラインに沿って、入力欄の近くから行けるようにする。
let chatGPTUsageURL = URL(string: "https://chatgpt.com/settings/usage")!

/// `AssistantMessage.Role` → DS のチャット役割 (ユーザー / 相手)。
extension AssistantMessage.Role {
    var chatRole: ImasChatRole { self == .user ? .user : .assistant }
}

// MARK: - 案内

/// 「Using ChatGPT plan · Manage usage」(OpenAI の UI/UX ガイドラインの表記)。
struct AssistantPlanFooter: View {
    var body: some View {
        HStack(spacing: DS.Space.gapTight) {
            Image(systemName: "sparkles")
            Text("Using ChatGPT plan")
            Text("·")
            Link("Manage usage", destination: chatGPTUsageURL)
        }
        .imasText(.meta)
    }
}

/// 利用上限に当たったときの案内。主ボタンは Manage usage。
struct AssistantUsageLimitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.gapLoose) {
                ImasIconTile(systemImage: "gauge.with.dots.needle.100percent", size: .s56, tone: .neutral)
                    .padding(.top, DS.Space.gapLoose)
                Text("ChatGPT プランの上限に達しました").imasText(.sectionTitle)
                Text("このアプリは ChatGPT のプランを使って応答しています。上限や、このアプリに使える量は ChatGPT の設定で確認・変更できます。")
                    .imasText(.body, color: DS.ink2)
                    .multilineTextAlignment(.center)
                Spacer()
                ImasButton(title: "Manage usage", role: .primary, size: .large) {
                    openURL(chatGPTUsageURL)
                    dismiss()
                }
            }
            .padding(.horizontal, DS.Space.section)
            .padding(.bottom, DS.Space.gapLoose)
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
        }
        .presentationDetents([.medium])
    }
}

/// サインインしていない / プランの利用許可が無いときの導線。
struct AssistantSignInGate: View {
    private var session: ChatGPTPlanSession { .shared }
    @AppStorage("chatgpt_plan.browser_mode") private var browserModeRaw = ChatGPTPlanBrowser.Mode.authSession.rawValue
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: DS.Space.gapLoose) {
            Spacer()
            ImasIconTile(systemImage: "sparkles", size: .s56, tone: .solid)
            Text("ChatGPT で AI と話す").imasText(.sectionTitle)
            Text("ChatGPT Plus / Pro のプランを使って、ライブやセトリ、あなたの参戦記録について質問できます。料金は ChatGPT のプランに含まれ、このアプリからの請求はありません。")
                .imasText(.body, color: DS.ink2)
                .multilineTextAlignment(.center)
            ImasButton(
                title: session.isSignedIn ? "ChatGPT プランの利用を許可する" : "Continue with ChatGPT",
                systemImage: "sparkles",
                role: .primary, size: .large, fillsWidth: true,
                isLoading: session.isSigningIn
            ) {
                errorMessage = nil
                Task {
                    do {
                        let mode = ChatGPTPlanBrowser.Mode(rawValue: browserModeRaw) ?? .authSession
                        try await session.signIn(mode: mode, intent: session.isSignedIn ? .enablePlan : .signIn)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage).imasText(.note, color: DS.warning).multilineTextAlignment(.center)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, DS.Space.section)
    }
}
