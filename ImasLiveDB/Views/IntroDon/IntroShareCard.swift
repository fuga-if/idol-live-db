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
///
/// 画像化とシェアシートの起動そのものは共有カード共通基盤 (`ShareCardRenderer`/`SystemShare`) に寄せ、
/// ここはサイズ固定の `frame` 付与と「画像 + 文面」の items 組み立てだけを持つ。
enum IntroShareImageRenderer {
    @MainActor
    static func render<Content: View>(size: CGSize, @ViewBuilder content: () -> Content) -> UIImage? {
        ShareCardRenderer.render(content().frame(width: size.width, height: size.height))
    }

    @MainActor
    static func share(image: UIImage?, text: String) {
        let items: [Any] = image.map { [ShareCardImageSource($0), text] } ?? [text]
        SystemShare.present(items: items)
    }
}
