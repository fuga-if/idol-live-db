import Nuke
import OSLog
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "share_card")

// =============================================================================
// シェアカードの画像化とシェア起動まわりの共通インフラ
// =============================================================================

/// SwiftUI カード View → UIImage (1080×1080px)。
/// ImageRenderer は @MainActor 必須なのでここも MainActor に寄せる。
@MainActor
enum ShareCardRenderer {
    /// カードを scale 2x でレンダリングする (カード View が自前で frame を持つ前提)。
    static func render(_ card: some View) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// シェアカードに焼き込むジャケット画像のローダ。
/// ImageRenderer は非同期ロードを待たないため、カード View には必ず
/// ここでロード済みの UIImage? を渡す (カード内で AsyncImage / LazyImage は使わない)。
enum ShareCardArtwork {
    /// songs.artwork_url から UIImage を取得。シート表示時 (.task) に呼ぶ。
    /// URL なし / 不正 / ロード失敗はすべて nil → ジャケ無しデザインにフォールバック。
    static func load(from urlString: String?) async -> UIImage? {
        guard let urlString,
              let url = URL.safeHTTP(string: highResolution(urlString)) else { return nil }
        do {
            return try await ImagePipeline.shared.image(for: url)
        } catch {
            logger.error("share_card_artwork_load_failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// mzstatic 形式の末尾 `/{w}x{h}bb....jpg` が 600px 未満なら 600x600 に引き上げる。
    /// (DB 上はほぼ 600x600 だが、低解像度 URL が混ざっても焼き込みがボケないように)
    static func highResolution(_ urlString: String) -> String {
        guard let match = urlString.firstMatch(of: #/\/(\d+)x(\d+)(bb[^\/]*)$/#),
              let w = Int(match.1), let h = Int(match.2),
              w < 600 || h < 600 else { return urlString }
        return urlString.replacingCharacters(in: match.range, with: "/600x600\(match.3)")
    }
}

/// シェアカード用ジャケ写ロードの状態を 1 箇所に集約した `@State` 用モデル。
/// 各シート/完了画面は `@State private var artwork = ShareArtworkLoader()` を持ち、
/// `.task { await artwork.load(from: url) }` を呼ぶだけでよい。
@MainActor @Observable
final class ShareArtworkLoader {
    /// ロード済みジャケ写。プレビューと生成画像の両方に同じ UIImage を使う。
    private(set) var image: UIImage?
    /// ロード完了フラグ (成功/失敗問わず)。URL なしなら最初から完了扱い。
    private(set) var isFinished = false

    /// ジャケ写の準備待ちか。URL なしの曲は最初から false (ジャケ無しデザイン確定)。
    func isPreparing(urlString: String?) -> Bool {
        urlString != nil && !isFinished
    }

    /// シート/完了画面表示時に呼ぶ。失敗時は image=nil のままジャケ無しデザインに
    /// フォールバックし、isFinished=true でシェアボタンを有効化する。
    func load(from urlString: String?) async {
        if urlString != nil {
            image = await ShareCardArtwork.load(from: urlString)
        }
        isFinished = true
    }
}

/// OS 標準のシェアシートをそのまま出す。
///
/// 以前は `UIActivityViewController` を `UIViewControllerRepresentable` にして
/// SwiftUI の `.sheet` + `presentationDetents` で包んでいた。 これだと
/// **シェアシートの上に SwiftUI のシート外装がもう一枚乗る**ため、
/// グラバーが二重に出たり、 中身が medium detent に押し込められて
/// アプリ候補が数個しか見えなかったりと、 標準の見え方から外れていた。
///
/// シェアシート自身が detent と presentation を持っているので、 包まずに
/// 最前面の ViewController から直接 present するのが正しい。
enum SystemShare {
    @MainActor
    static func present(items: [Any]) {
        guard !items.isEmpty else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else {
            logger.error("system_share_no_root_vc")
            return
        }
        // シートの上から呼ばれることがあるので、 最前面まで辿ってから present する
        // (root に出すと「別のシートが出ている」と怒られて何も出ない)。
        var top = root
        while let presented = top.presentedViewController { top = presented }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad は popover 必須。 アンカーが無いとクラッシュする。
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}

/// 共有カード画像を確実に「画像」として供給するアイテムソース。
///
/// activityItems に生 UIImage や file URL を並べるだけだと、X / Instagram 等の共有
/// エクステンションは添付の型を判別できず画像を落とすことがある。UIActivityItemSource
/// で UTType.png を明示し、placeholder にも UIImage を返すことで添付を保証する。
final class ShareCardImageSource: NSObject, UIActivityItemSource {
    private let image: UIImage

    init(_ image: UIImage) {
        self.image = image
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        image
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.png.identifier
    }
}

/// カードの実寸を親幅に合わせて縮小表示するライブプレビュー。
/// レンダリング済み画像ではなく実 View を縮小するので、入力中の更新が即反映される。
/// カードは自前で frame(width:height:) を持つ前提なので、size で比率を合わせる。
struct ShareCardPreview<Card: View>: View {
    var size: ShareCard.Size = ShareCard.portrait
    @ViewBuilder var card: Card

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / size.width
            card
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}

/// プレビュー + シェア実行ボタンの共通ボディ。
/// 各エントリポイントの sheet / 完了画面に埋め込んで使う。
///
/// カードは `ShareCard.Size` を受け取って組み立てるので、`card` は
/// 「サイズを受け取ってカードを返すビルダー」で受け取る。
/// プレビューと生成画像が必ず同じサイズで作られることを保証するため。
struct ShareCardActionPane<Card: View>: View {
    /// サイズを受け取りカードを構築するビルダー。
    @ViewBuilder let card: (ShareCard.Size) -> Card
    /// ジャケット画像のロード待ちなど、カードがまだ完成形でない間 true を渡すと
    /// シェアボタンが「準備中」になる (中途半端なカードが焼かれるのを防ぐ)。
    var isPreparingCard: Bool = false

    @State private var showRenderError = false

    // 比率は既定 (縦長) 固定。 1:1 / 4:5 / 9:16 を選ばせていたが、 どれを選んでも
    // 同じ内容が出るだけで判断の助けにならず、 シートの一番目立つ位置を占めていた。
    private var cardSize: ShareCard.Size { ShareCard.defaultRatio.size }

    var body: some View {
        VStack(spacing: DS.sp5) {
            ShareCardPreview(size: cardSize) { card(cardSize) }

            Button {
                AppAnalytics.tap("share_card.share")
                guard let image = ShareCardRenderer.render(card(cardSize)) else {
                    logger.error("share_card_render_failed: ImageRenderer returned nil")
                    showRenderError = true
                    return
                }
                SystemShare.present(items: [ShareCardImageSource(image)])
            } label: {
                HStack(spacing: DS.sp3) {
                    if isPreparingCard {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("画像を準備中…")
                    } else {
                        Label("シェアする", systemImage: "square.and.arrow.up")
                    }
                }
                .font(.imasHeadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPreparingCard)
        }
        .alert("シェア画像の生成に失敗しました", isPresented: $showRenderError) {
            Button("OK") {}
        } message: {
            Text("もう一度試すか、アプリを再起動してください。")
        }
    }

}

/// シェアカードを出すシートの外枠。
///
/// 回収率 / 年まとめ / タグ / 感想 の 4 つが NavigationStack + ScrollView + 背景 +
/// タイトル + 「閉じる」を各自で書いていて、閉じるの位置が leading と trailing で
/// 割れていたり、trackScreen を付け忘れていたりした。枠はここに一本化する。
struct ShareCardSheet<Content: View>: View {
    let title: String
    /// AppAnalytics の画面名 (例: "collection_share")。
    let screenName: String
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(DS.sp5)
            }
            .background(DS.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .trackScreen(screenName)
        }
    }
}
