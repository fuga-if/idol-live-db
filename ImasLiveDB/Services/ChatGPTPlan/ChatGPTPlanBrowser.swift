import AuthenticationServices
import SafariServices
import UIKit

/// 認可ページをシステムのブラウザで開く。WKWebView は Google ログインが弾かれるので使わない。
///
/// どちらの方式でも callback はブラウザが `http://127.0.0.1` を読みに行くことで
/// `LoopbackCallbackServer` に届く。ブラウザ側で URL を横取りする仕組みは使わないので、
/// 受け取ったらこちらから閉じる。
@MainActor
final class ChatGPTPlanBrowser: NSObject {
    enum Mode: String, CaseIterable, Identifiable {
        case authSession
        case safariView

        var id: String { rawValue }
        var label: String {
            switch self {
            case .authSession: "ASWebAuthenticationSession"
            case .safariView: "SFSafariViewController"
            }
        }
    }

    private var authSession: ASWebAuthenticationSession?
    private var safari: SFSafariViewController?
    private var onUserCancel: (() -> Void)?
    private var closingByApp = false
    private var sessionCounter = 0
    private var currentSessionID = 0

    /// - Parameter onUserCancel: 利用者がブラウザを閉じたとき (アプリから閉じたときは呼ばない)。
    func open(_ url: URL, mode: Mode, onUserCancel: @escaping () -> Void) -> Bool {
        self.onUserCancel = onUserCancel
        closingByApp = false
        switch mode {
        case .authSession:
            // 前の試行の完了通知が後から届いても、今のセッションを壊さないよう番号で見分ける。
            sessionCounter += 1
            let sessionID = sessionCounter
            currentSessionID = sessionID
            // 横取り用のスキームは実際には使わない (callback はループバックで受ける)。
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "imaslivedb-chatgpt-unused"
            ) { [weak self] _, _ in
                Task { @MainActor in self?.authSessionDidComplete(id: sessionID) }
            }
            // ChatGPT に Safari でログイン済みならその Cookie を使いたいので ephemeral にしない。
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            authSession = session
            return session.start()
        case .safariView:
            guard let presenter = Self.topViewController() else { return false }
            let controller = SFSafariViewController(url: url)
            controller.delegate = self
            controller.dismissButtonStyle = .cancel
            safari = controller
            presenter.present(controller, animated: true)
            return true
        }
    }

    func close() {
        closingByApp = true
        authSession?.cancel()
        authSession = nil
        safari?.dismiss(animated: true)
        safari = nil
        onUserCancel = nil
    }

    private func authSessionDidComplete(id: Int) {
        guard id == currentSessionID else { return }
        browserDidClose()
    }

    private func browserDidClose() {
        authSession = nil
        safari = nil
        guard !closingByApp else { return }
        onUserCancel?()
        onUserCancel = nil
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension ChatGPTPlanBrowser: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .keyWindow ?? ASPresentationAnchor()
        }
    }
}

extension ChatGPTPlanBrowser: SFSafariViewControllerDelegate {
    nonisolated func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        MainActor.assumeIsolated { browserDidClose() }
    }
}
