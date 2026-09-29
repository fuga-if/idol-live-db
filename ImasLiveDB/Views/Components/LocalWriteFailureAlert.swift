import UIKit

/// 端末ローカルの書き込み失敗を、システムのアラートで知らせる (`LocalWriteFailure.presenter`)。
///
/// 失敗はシートの中 (メモ・座席・参加の選択・曲やアイドルの詳細) で起きることが多い。
/// SwiftUI の `.alert` は、付けた View がシートに覆われていると出ないので、
/// アプリの画面とは別の最前面のウィンドウに出す。
/// 出ている間に続けて失敗しても重ねない (同じ知らせを何度も閉じさせない)。
@MainActor
enum LocalWriteFailureAlert {
    private static var window: UIWindow?

    static func present(_ notice: LocalWriteFailure.Notice) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState == .foregroundActive })
        else { return }
        let previousKey = scene.keyWindow
        let host = UIViewController()
        host.view.backgroundColor = .clear
        let overlay = UIWindow(windowScene: scene)
        overlay.windowLevel = .alert
        overlay.backgroundColor = .clear
        overlay.rootViewController = host
        overlay.makeKeyAndVisible()
        window = overlay

        let alert = UIAlertController(title: notice.title, message: notice.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            MainActor.assumeIsolated {
                window?.isHidden = true
                window = nil
                previousKey?.makeKey()
            }
        })
        host.present(alert, animated: true)
    }
}
