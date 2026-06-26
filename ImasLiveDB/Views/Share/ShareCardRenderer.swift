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

/// テキスト + 画像を一緒に渡せる UIActivityViewController ラッパー。
/// (ShareLink は異種 item の同時シェアが不安定なためこちらを使う)
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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

/// アスペクト比トグル。選択中の比率を強調表示する小さなセグメント。
/// ラベル (1:1 / 4:5 / 9:16) + 用途キャプションを縦に並べ、押下で切替。
struct ShareRatioToggle: View {
    @Binding var ratio: ShareCard.Ratio

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ShareCard.Ratio.allCases) { option in
                let selected = option == ratio
                Button {
                    ratio = option
                } label: {
                    VStack(spacing: 2) {
                        Text(option.label)
                            .font(.imasSubhead.weight(.bold))
                        Text(option.caption)
                            .font(.imasScaled( 10, weight: .medium))
                            .opacity(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: DS.rMD, style: .continuous)
                            .fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(DS.surface))
                    )
                    .foregroundStyle(selected ? Color.white : DS.ink2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.label) \(option.caption)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// プレビュー + 比率トグル + シェア実行ボタンの共通ボディ。
/// 各エントリポイントの sheet / 完了画面に埋め込んで使う。
///
/// カードは選択中の比率 (`ShareCard.Size`) で都度ビルドし直すため、
/// `card` は「サイズを受け取ってカードを返すビルダー」で受け取る。
/// プレビューも生成画像も常に選択中の比率で生成される。
struct ShareCardActionPane<Card: View>: View {
    /// 選択中のサイズを受け取りカードを構築するビルダー。
    @ViewBuilder let card: (ShareCard.Size) -> Card
    /// 比率トグルを表示するか (固定比率で使いたい場合は false)。
    var showsRatioToggle: Bool = true
    /// ジャケット画像のロード待ちなど、カードがまだ完成形でない間 true を渡すと
    /// シェアボタンが「準備中」になる (中途半端なカードが焼かれるのを防ぐ)。
    var isPreparingCard: Bool = false

    @State private var ratio: ShareCard.Ratio = ShareCard.defaultRatio
    @State private var renderedImage: UIImage?
    @State private var showActivity = false
    @State private var showRenderError = false

    private var cardSize: ShareCard.Size { ratio.size }

    var body: some View {
        VStack(spacing: DS.sp5) {
            if showsRatioToggle {
                ShareRatioToggle(ratio: $ratio)
            }

            ShareCardPreview(size: cardSize) { card(cardSize) }
                // 比率切替時にプレビューがふわっと差し替わるように。
                .animation(.easeInOut(duration: 0.2), value: ratio)

            Button {
                AppAnalytics.tap("share_card.share")
                let image = ShareCardRenderer.render(card(cardSize))
                if image == nil {
                    logger.error("share_card_render_failed: ImageRenderer returned nil")
                    showRenderError = true
                    return
                }
                renderedImage = image
                showActivity = true
            } label: {
                HStack(spacing: 8) {
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
        .sheet(isPresented: $showActivity) {
            ActivityShareSheet(items: activityItems)
                .presentationDetents([.medium, .large])
        }
        .alert("シェア画像の生成に失敗しました", isPresented: $showRenderError) {
            Button("OK") {}
        } message: {
            Text("もう一度試すか、アプリを再起動してください。")
        }
    }

    private var activityItems: [Any] {
        // 画像のみを渡す。X はテキスト同梱だと画像を落とすため、キャプションは
        // クリップボード経由 (ボタン押下時にコピー済み) にしている。
        guard let renderedImage else { return [] }
        return [ShareCardImageSource(renderedImage)]
    }
}
