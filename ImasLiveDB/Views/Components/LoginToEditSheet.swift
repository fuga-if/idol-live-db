import SwiftUI

/// 未ログインユーザーが編集 / 新規作成導線を押した時に出すログイン誘導 sheet。
///
/// 確定モデルでは「ログイン済み全ユーザーがオープン編集可能」。未ログインでも導線は見えるが、
/// 押下時にここへ誘導する。ログイン完了 (`AuthService.shared.isSignedIn` が true) を監視して
/// 自動で dismiss し、呼び出し側が保持していた編集対象を再 present できるようにする。
struct LoginToEditSheet: View {
    /// ログイン完了時に呼ばれる。呼び出し側はここで元の編集対象を再 present する。
    var onSignedIn: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ImasFormPage {
                ImasSetupHeader(
                    systemImage: "square.and.pencil",
                    title: "ログインして編集に参加",
                    message: "ライブ・公演・セトリ・楽曲の情報は、ログインしたユーザーみんなで編集できます。誤りの修正や新しいライブの追加に、ぜひ協力してください。"
                )

                ImasStepList(steps: [
                    .init(title: "編集は承認待ちなし", detail: "すぐ全員に反映されます"),
                    .init(title: "変更履歴が残ります", detail: "間違えてもいつでも戻せます"),
                    .init(title: "閲覧はログイン不要", detail: "編集する時だけログインします"),
                ])

                AppleSignInButton()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("login_sheet")
            .imasSheetToolbar(.read(onClose: { dismiss() }))
            // ログイン完了を監視。サインインすると即 dismiss → 呼び出し側が編集対象を再 present。
            .onChange(of: AuthService.shared.isSignedIn) { _, signedIn in
                if signedIn {
                    onSignedIn()
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// ログインが必要なコンポーネント内に表示するインライン導線。
/// 未ログイン (セッション失効を含む) のときだけ表示し、タップで LoginToEditSheet を開く。
/// セッションが自動リフレッシュ不能になると AuthService.isSignedIn=false になり、ここが現れる。
struct InlineLoginPrompt: View {
    var message: String = "投稿・投票にはログインが必要です"
    var seed: String? = nil
    @Environment(\.colorScheme) private var scheme
    @State private var showLogin = false

    var body: some View {
        if !AuthService.shared.isSignedIn {
            let t = ImasTheme.derive(seed: seed, scheme: scheme)
            Button {
                AppAnalytics.tap("inline_login.open")
                showLogin = true
            } label: {
                HStack(spacing: DS.sp2) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.imasScaled( 15, weight: .semibold))
                    Text(message).font(.imasFootnote.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text("ログイン")
                        .font(.imasFootnote.weight(.bold))
                        .padding(.horizontal, DS.sp4).padding(.vertical, 6)
                        .foregroundStyle(t.onAccent)
                        .background(t.accent, in: Capsule())
                }
                .foregroundStyle(DS.ink2)
                .padding(.horizontal, DS.sp4).padding(.vertical, DS.sp3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showLogin) { LoginToEditSheet() }
        }
    }
}
