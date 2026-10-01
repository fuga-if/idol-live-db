import SwiftUI

/// ChatGPT 側の使用状況ページ。OpenAI の UI/UX ガイドラインに沿って、入力欄の近くから行けるようにする。
let chatGPTUsageURL = URL(string: "https://chatgpt.com/settings/usage")!

// MARK: - 吹き出し

/// 発言 1 つ。相手側 (AI / キャラ) は左、自分は右。
/// `avatar` を渡すと相手側の吹き出しの左にアイコンと名前を出す (キャラとのトーク用)。
struct AssistantBubble<Avatar: View>: View {
    let message: AssistantMessage
    var partnerName: String?
    var partnerTint: Color = DS.surface
    @ViewBuilder var avatar: () -> Avatar

    var body: some View {
        HStack(alignment: .top, spacing: DS.sp3) {
            if message.role == .user {
                Spacer(minLength: DS.sp9)
                bubble(fill: AnyShapeStyle(.tint), foreground: .white)
            } else {
                avatar()
                VStack(alignment: .leading, spacing: DS.sp2) {
                    if let partnerName {
                        Text(partnerName).font(.imasCaption).foregroundStyle(DS.ink2)
                    }
                    bubble(fill: AnyShapeStyle(partnerTint), foreground: DS.ink)
                }
                Spacer(minLength: DS.sp9)
            }
        }
    }

    private func bubble(fill: AnyShapeStyle, foreground: Color) -> some View {
        Text(message.text)
            .font(.imasBody)
            .foregroundStyle(foreground)
            .textSelection(.enabled)
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, DS.sp3 + 2)
            .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension AssistantBubble where Avatar == EmptyView {
    init(message: AssistantMessage) {
        self.init(message: message, avatar: { EmptyView() })
    }
}

/// ツール実行中に吹き出しの上に出す小さな札。
struct AssistantToolChip: View {
    let label: String

    var body: some View {
        HStack(spacing: DS.sp2) {
            ProgressView().controlSize(.mini)
            Text(label).font(.imasCaption)
        }
        .foregroundStyle(DS.ink2)
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, DS.sp2 + 2)
        .background(DS.fill, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// 生成中の吹き出し (まだ文字が無いときは点を出す)。
struct AssistantStreamingBubble<Avatar: View>: View {
    let text: String
    var partnerTint: Color = DS.surface
    @ViewBuilder var avatar: () -> Avatar

    var body: some View {
        HStack(alignment: .top, spacing: DS.sp3) {
            avatar()
            Group {
                if text.isEmpty {
                    Image(systemName: "ellipsis")
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .foregroundStyle(DS.ink2)
                } else {
                    Text(text).font(.imasBody).foregroundStyle(DS.ink)
                }
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, DS.sp3 + 2)
            .background(partnerTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: DS.sp9)
        }
    }
}

/// 失敗した応答の吹き出し。
struct AssistantFailedBubble: View {
    let message: String?
    let onRetry: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: DS.sp3) {
                Label(message ?? "応答を受け取れませんでした", systemImage: "exclamationmark.triangle")
                    .font(.imasCaption)
                    .foregroundStyle(DS.warning)
                Button("もう一度", action: onRetry)
                    .font(.imasCaption.weight(.semibold))
            }
            .padding(DS.sp4)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: DS.sp9)
        }
    }
}

// MARK: - 入力欄

struct AssistantInputBar: View {
    @Binding var text: String
    let placeholder: String
    let isRunning: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: DS.sp2) {
            HStack(alignment: .bottom, spacing: DS.sp3) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(.imasBody)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, DS.sp4)
                    .padding(.vertical, DS.sp3)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Button {
                    isRunning ? onStop() : onSend()
                } label: {
                    Image(systemName: isRunning ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(isRunning || canSend ? AnyShapeStyle(.tint) : AnyShapeStyle(DS.ink3))
                }
                .disabled(!isRunning && !canSend)
                .accessibilityLabel(isRunning ? "止める" : "送信")
            }
            AssistantPlanFooter()
        }
        .padding(.horizontal, DS.sp5)
        .padding(.top, DS.sp3)
        .padding(.bottom, DS.sp3)
        .background(DS.bg)
    }
}

/// 「Using ChatGPT plan · Manage usage」(OpenAI の UI/UX ガイドラインの表記)。
struct AssistantPlanFooter: View {
    var body: some View {
        HStack(spacing: DS.sp2) {
            Image(systemName: "sparkles")
            Text("Using ChatGPT plan")
            Text("·")
            Link("Manage usage", destination: chatGPTUsageURL)
        }
        .font(.imasCaption2)
        .foregroundStyle(DS.ink3)
    }
}

// MARK: - 案内

/// 利用上限に当たったときの案内。主ボタンは Manage usage。
struct AssistantUsageLimitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: DS.sp5) {
            Image(systemName: "gauge.with.dots.needle.100percent")
                .font(.system(size: 40))
                .foregroundStyle(DS.ink2)
                .padding(.top, DS.sp7)
            Text("ChatGPT プランの上限に達しました")
                .font(.imasTitle3)
            Text("このアプリは ChatGPT のプランを使って応答しています。上限や、このアプリに使える量は ChatGPT の設定で確認・変更できます。")
                .font(.imasCallout)
                .foregroundStyle(DS.ink2)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                openURL(chatGPTUsageURL)
                dismiss()
            } label: {
                Text("Manage usage")
                    .font(.imasHeadline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Capsule())
            Button("閉じる") { dismiss() }
                .font(.imasCallout)
                .padding(.bottom, DS.sp5)
        }
        .padding(.horizontal, DS.sp6)
        .presentationDetents([.medium])
    }
}

/// サインインしていない / プランの利用許可が無いときの導線。
struct AssistantSignInGate: View {
    private var session: ChatGPTPlanSession { .shared }
    @AppStorage("chatgpt_plan.browser_mode") private var browserModeRaw = ChatGPTPlanBrowser.Mode.authSession.rawValue
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: DS.sp5) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("ChatGPT で AI と話す")
                .font(.imasTitle2)
            Text("ChatGPT Plus / Pro のプランを使って、ライブやセトリ、あなたの参戦記録について質問できます。料金は ChatGPT のプランに含まれ、このアプリからの請求はありません。")
                .font(.imasCallout)
                .foregroundStyle(DS.ink2)
                .multilineTextAlignment(.center)
            Button {
                errorMessage = nil
                Task {
                    do {
                        let mode = ChatGPTPlanBrowser.Mode(rawValue: browserModeRaw) ?? .authSession
                        try await session.signIn(mode: mode, intent: session.isSignedIn ? .enablePlan : .signIn)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } label: {
                HStack(spacing: DS.sp3) {
                    if session.isSigningIn { ProgressView().tint(.white) } else { Image(systemName: "sparkles") }
                    Text(session.isSignedIn ? "ChatGPT プランの利用を許可する" : "Continue with ChatGPT")
                        .font(.imasHeadline)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(.white)
                .background(Color.black, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(session.isSigningIn)
            if let errorMessage {
                Text(errorMessage).font(.imasCaption).foregroundStyle(DS.warning).multilineTextAlignment(.center)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, DS.sp7)
    }
}
