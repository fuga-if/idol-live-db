import SwiftUI
import WebKit

/// 参考動画を再生する YouTube の埋め込みプレーヤー。大きさと角は置く側 (小窓) が決める。
///
/// ページの中身 (IFrame Player API・開始秒・名乗る origin) はコア
/// (`youtubeEmbedPlayer`) が組む。ここは WKWebView に読ませて、ページからの
/// 知らせ (`youtubePlayerEvent`) を受けるだけ。
/// 埋め込みを止めている動画 (公式 MV に多い) は YouTube の仕様で再生できないので、
/// `onUnplayable` で親に返し、親が「YouTube で開く」案内に替える。
struct YouTubeInlinePlayer: View {
    let player: YouTubeEmbedPlayer
    let onUnplayable: () -> Void

    @State private var isReady = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black)
            YouTubeWebView(player: player,
                           onReady: { isReady = true },
                           onUnplayable: onUnplayable)
                .opacity(isReady ? 1 : 0)
            if !isReady {
                ProgressView().tint(.white)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("動画プレーヤー")
    }
}

/// 埋め込みを止めている動画の案内 (小窓の中と、一覧のサムネの場所)。
/// 一言と「YouTube で開く」(押すとアプリ外へ)。大きさは置く側が決める。
struct YouTubeUnplayableNotice: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            ZStack {
                Rectangle().fill(DS.surface2)
                VStack(spacing: DS.sp2) {
                    Text("この動画はアプリ内で再生できません")
                        .imasText(.meta, color: DS.ink2)
                    Label("YouTube で開く", systemImage: "arrow.up.right.square")
                        .imasText(.value, color: DS.danger)
                }
                .multilineTextAlignment(.center)
                .padding(DS.sp4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("この動画はアプリ内で再生できません。YouTube で開く")
    }
}

private struct YouTubeWebView: UIViewRepresentable {
    let player: YouTubeEmbedPlayer
    let onReady: () -> Void
    let onUnplayable: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // 押した操作で開くプレーヤーなので、読み込んだらそのまま再生する。
        config.mediaTypesRequiringUserActionForPlayback = []
        // 弱参照の中継を挟む (WKUserContentController はハンドラを強参照し、循環する)。
        config.userContentController.add(WeakMessageHandler(context.coordinator),
                                          name: player.bridgeName)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.parent = self
        webView.loadHTMLString(player.html, baseURL: URL(string: player.baseUrl))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // 画面から外れたら音を止める (WebView が残っても鳴り続けないように)。
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: YouTubeWebView?

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let text = message.body as? String else { return }
            switch youtubePlayerEvent(message: text) {
            case .ready: parent?.onReady()
            case .unplayable: parent?.onUnplayable()
            case .other: break
            }
        }

        /// プレーヤーの中のリンク (YouTube のロゴ・タイトル・関連動画) は WebView の中で
        /// 開かず、YouTube アプリ / Safari に渡す。
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// `WKUserContentController` の強参照を切るための中継。
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
