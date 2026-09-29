import SwiftUI
import UIKit

/// 結果を「映える画像」でシェアするためのレンダラ (カードはミニゲーム共通の `QuizShareCard`)。
///
/// NOTE: このファイルのフォントは意図的に `.font(.system(size:))` の固定 pt を使う。
/// `ImageRenderer` で固定 CGSize のキャンバスへ焼くため、Dynamic Type やアプリ内文字サイズ
/// 倍率に追随させると出力画像でレイアウトが破綻する。画面表示用の文字は `.imasScaled` を使うこと。
/// /dev/intro (本家 IntroQuiz) の ShareImage / SoloShareCard の手法を踏襲:
/// ImageRenderer で SwiftUI カードを UIImage 化 → UIActivityViewController で共有。
/// カード下部に本家アプリ「イントロクイズ」のダウンロード導線を載せ、広告も兼ねる。
enum IntroShareImageRenderer {
    @MainActor
    static func render<Content: View>(size: CGSize, @ViewBuilder content: () -> Content) -> UIImage? {
        let renderer = ImageRenderer(content: content().frame(width: size.width, height: size.height))
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }

    @MainActor
    static func share(image: UIImage?, text: String) {
        let items: [Any] = image.map { [$0, text] } ?? [text]
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                    ?? scene.windows.first?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        presenter.present(vc, animated: true)
    }
}
