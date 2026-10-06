import SwiftUI

// =============================================================================
// 紙に刷る P名刺 (91×55mm、日本の名刺の大きさ)。
//
// 表・裏の組みは画面の P名刺と同じ部品 (`ImasMeishiFront` / `ImasMeishiBack`、docs/DESIGN_SYSTEM.md §6.13)。
// 違うのは色 (固定色の紙と墨) と画像の渡し方だけ: ImageRenderer は画像の読み込みを待たないので、
// 担当の写真・名刺の写真は書き出す前に UIImage に読んでから渡す (URL を渡すと焼かれない)。
// 表 = デザインごとの組み。名前・P歴・担当 (写真か判子、多いときは数で畳む)・ハンドル・名刺の写真。
//      自作の画像の名刺は、その画像をそのまま刷る (`ProducerCardPrintImage`)。
// 裏 = QR (既定はアプリの交換と同じ中身。自分の QR も選べる)・参加公演数と回収曲数・「YYYY.MM.DD 時点」。
// =============================================================================

enum ProducerCardPrint {
    /// 91:55 の紙 (pt)。4.5 倍で焼いて 1638×990px (350dpi 相当)。
    static let size = ShareCard.Size(width: ImasMeishi.canvas.width, height: ImasMeishi.canvas.height)
    static let renderScale: CGFloat = 4.5

    static let paper = ShareInk.offWhite
    static let ink = ShareInk.nearBlack
    static let sub = Color(.sRGB, red: 0x5A / 255, green: 0x57 / 255, blue: 0x55 / 255)

    /// 紙と墨 (固定色)。担当の色は帯・罫・判子の縁だけ。
    static func colors(seed: String?) -> ImasMeishiInk {
        ImasMeishiInk(paper: paper, ink: ink, sub: sub, line: sub.opacity(0.35),
                      accent: seed == nil ? ink : ShareCardPalette(seed: seed).accent,
                      onAccent: seed == nil ? paper : ink)
    }

    /// 担当の判子の色。
    static func stampColor(seed: String?) -> Color {
        seed == nil ? ink : ShareCardPalette(seed: seed).accent
    }

    @MainActor
    static func render(_ card: some View) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = renderScale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// 紙に刷る担当のブランドごとのまとまり (コアの `CardFaceOshiGroup`)。
struct ProducerCardPrintOshiGroup {
    let label: String
    let oshi: [ProducerCardPrintOshi]
}

/// 紙に刷る担当 1 人 (写真は読み込み済みのものだけ)。
struct ProducerCardPrintOshi: Identifiable {
    let id: String
    let name: String
    let shortName: String
    var seed: String? = nil
    var image: UIImage? = nil
}

/// 表。デザイン (入場証・かしこまった名刺・ポップ) ごとに組みを変える。載せるものは画面の名刺と同じ。
struct ProducerCardPrintFront: View {
    var look: ImasMeishiFront.Look = .pass
    let name: String
    /// 「SINCE 2014」(コアの `CardFace.sinceImprint`)。
    var sinceImprint: String? = nil
    /// 表に並べる担当のブランドごとのまとまり (コアの `CardFace.oshiGroups` の順)。
    var groups: [ProducerCardPrintOshiGroup] = []
    /// 判子の下の 1 行 (コアの `CardFace.oshiCaption`)。
    var caption: String? = nil
    var moreOshi: Int = 0
    /// 担当の色 (帯・罫)。先頭の担当の色。
    var seed: String? = nil
    /// 右下に刷るハンドル (「@fuga_p」)。
    var handle: String? = nil
    /// 名前の書体の PostScript 名 (コアのデザインの書体)。
    var nameFont: String? = nil
    /// 名刺の写真 (右に正方形の枠で刷る)。
    var portrait: UIImage? = nil
    /// 名刺の写真を丸く切る (X のアイコン)。
    var portraitRound = false

    var body: some View {
        ImasMeishiFront(
            look: look, name: name, sinceImprint: sinceImprint,
            oshiGroups: groups.map { group in
                ImasMeishiOshiGroup(label: group.label, oshi: group.oshi.map {
                    ImasMeishiOshi(id: $0.id, name: $0.name, shortName: $0.shortName,
                                   color: ProducerCardPrint.stampColor(seed: $0.seed),
                                   picture: $0.image.map { .image($0) })
                })
            },
            oshiCaption: caption,
            moreOshi: moreOshi, handle: handle, nameFont: nameFont,
            portrait: portrait.map { .image($0) },
            portraitRound: portraitRound,
            ink: ProducerCardPrint.colors(seed: seed)
        )
    }
}

/// 自作の名刺の画像 (表・裏) を 91:55 の紙に刷る。比率が違う画像は切らずに収め、余りは紙の色。
/// 縦の名刺 (55:91) は 90° 回して横の版面に収める (入稿の版面は横に揃える)。
struct ProducerCardPrintImage: View {
    let image: UIImage

    private var isPortrait: Bool { image.size.height > image.size.width }

    var body: some View {
        let size = ProducerCardPrint.size
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: isPortrait ? size.height : size.width, height: isPortrait ? size.width : size.height)
            .rotationEffect(.degrees(isPortrait ? -90 : 0))
            .frame(width: size.width, height: size.height)
            .background(ProducerCardPrint.paper)
    }
}

/// 裏。
struct ProducerCardPrintBack: View {
    /// QR にする中身 (交換用の名刺の URL か、自分の QR の URL)。
    let url: String
    /// QR の横に刷る案内 (「読み取るとアプリの名刺入れに入ります…」)。
    var note: String = "読み取るとアプリの名刺入れに入ります。アプリが無ければ Web で開きます。"
    var showCount: UInt32? = nil
    var songCount: UInt32? = nil
    /// 「2026.10.06 時点」(コアの `CardFace.issuedLabel`)。
    let issuedLabel: String
    var qrImage: UIImage?

    var body: some View {
        ImasMeishiBack(qr: qrImage, note: note, showCount: showCount, songCount: songCount,
                       issuedLabel: issuedLabel, ink: ProducerCardPrint.colors(seed: nil))
    }
}

/// 実寸のカードを親の幅に合わせて縮めて見せる (影は付けず、細い線で縁取る)。
struct ProducerCardPrintPreview<Card: View>: View {
    @ViewBuilder var card: Card

    var body: some View {
        GeometryReader { geo in
            card.scaleEffect(geo.size.width / ProducerCardPrint.size.width, anchor: .topLeading)
        }
        .aspectRatio(ProducerCardPrint.size.width / ProducerCardPrint.size.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: DS.rInner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.rInner, style: .continuous).strokeBorder(DS.line, lineWidth: 1))
    }
}
