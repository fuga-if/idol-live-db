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

                // 手順ではなく特徴の列挙なので、番号 (ImasStepList) でなく記号の箇条書きにする。
                ImasPointList(points: [
                    .init("bolt.fill", "編集は承認待ちなし。すぐ全員に反映されます"),
                    .init("clock.arrow.circlepath", "変更履歴が残り、間違えてもいつでも戻せます"),
                    .init("eye", "閲覧はログイン不要。編集する時だけログインします"),
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
