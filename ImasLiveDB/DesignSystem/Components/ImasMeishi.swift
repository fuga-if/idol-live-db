import NukeUI
import SwiftUI

// =============================================================================
// 名刺の紙 (91:55) の表と裏 (docs/DESIGN_SYSTEM.md §6.13)
//
// 画面の P名刺 (`ImasProducerCard`) と紙に刷る画像 (`ProducerCardPrintFront` / `Back`) が同じ組みで描く。
// 違うのは紙と墨の色 (`ImasMeishiInk`: 画面はチケットの紙、紙に刷る画像は固定色) と、
// 画像の渡し方 (`ImasMeishiPicture`: 画面は URL を読み込み、刷る画像は読み込み済みの UIImage。
// ImageRenderer は読み込みを待たないので、刷る側は必ず UIImage で渡す) だけ。
//
// 寸法は名刺の紙の上の寸法 (`ImasMeishi.canvas` = 364×220pt の紙) で決め、`scale` 倍して描く。
// 画面は幅に合わせた倍率、紙に刷る画像は 1 倍の紙を 4.5 倍で焼く (1638×990px)。
// 文字も紙の上の大きさで固定する (名刺は物。読み上げと大きな文字は名刺の下の詳細が受け持つ)。
//
// ImasMeishiFront  表。名前 (デザインの書体)・P歴・名刺の写真 (正方形の枠。X のアイコンは丸)・担当 (判子か写真を
//                  ブランドごとにまとめて小さく並べ、下に「星井美希 担当」か、ブランドが 2 つ以上なら
//                  まとまりごとにブランドの略称。並べる人・まとめ方・文言はコアの `producerCardFace`)・
//                  ハンドル 1 つ。
//                  - 入場証 (pass): 左に担当色の縦の帯。
//                  - かしこまった名刺 (formal): 細い罫と明朝、担当色は罫と判子だけ。
//                  - ポップ (pop): 墨の太い枠と担当色の太い帯、名前の下に担当色の太い線。
// ImasMeishiBack   裏。QR (交換用か自分の QR)・参加公演数・回収曲数・「YYYY.MM.DD 時点」。
// ImasMeishiStamp  表に並べる担当 1 人 (写真があれば写真、無ければ判子)。
// =============================================================================

enum ImasMeishi {
    /// 名刺の紙の大きさ (pt)。日本の名刺の比 (91:55) で、画面の幅 (iPhone で 360pt 前後) とほぼ同じ。
    static let canvas = CGSize(width: 364, height: 220)
    /// 紙の縦横比。
    static var aspect: CGFloat { canvas.width / canvas.height }
}

/// 名刺の紙と墨の色。
struct ImasMeishiInk {
    var paper: Color
    var ink: Color
    var sub: Color
    /// 細い罫・写真の縁。
    var line: Color
    /// 担当の色 (帯・罫・下線)。担当がいなければ墨。
    var accent: Color
    /// 担当の色の帯の上の文字。
    var onAccent: Color

    /// 画面の名刺。ダークでも紙は明るいチケットの紙 (QR を読めるように・紙の名刺に見えるように)。
    /// 担当の色は明るい紙の上の色で引く。
    static func screen(seed: String?, brand: String?) -> ImasMeishiInk {
        let theme = ImasTheme.derive(seed: seed, brand: brand, scheme: .light)
        return ImasMeishiInk(
            paper: DS.ticket, ink: DS.ticketInk, sub: DS.ticketSub, line: DS.ticketDash,
            accent: theme.isNeutral ? DS.ticketInk : theme.accent,
            onAccent: theme.isNeutral ? DS.ticket : theme.onAccent
        )
    }
}

/// 名刺に載せる画像。画面は URL (読み込みながら出す)、紙に刷る画像は読み込み済みの UIImage。
enum ImasMeishiPicture {
    case url(URL)
    case image(UIImage)
}

/// 名刺の表で 1 つのブランドにまとめて並べる担当 (コアの `CardFaceOshiGroup`)。
struct ImasMeishiOshiGroup: Identifiable {
    /// ブランドの略称 (「765AS」)。名前の行が無いときだけ判子の下に刷る。空なら刷らない。
    let label: String
    let oshi: [ImasMeishiOshi]
    var id: String { oshi.first?.id ?? label }
}

/// 名刺の表に並べる担当 1 人。
struct ImasMeishiOshi: Identifiable {
    let id: String
    let name: String
    /// 判子の略称。
    let shortName: String
    /// 判子の色 (担当の色)。
    let color: Color
    var picture: ImasMeishiPicture? = nil
}

// MARK: - 表

struct ImasMeishiFront: View {
    enum Look { case pass, formal, pop }

    var look: Look = .pass
    let name: String
    /// 「SINCE 2014」(コアの `CardFace.sinceImprint`)。
    var sinceImprint: String? = nil
    /// 表に並べる担当のブランドごとのまとまり (コアの `CardFace.oshiGroups` の順)。
    var oshiGroups: [ImasMeishiOshiGroup] = []
    /// 判子の下の 1 行 (コアの `CardFace.oshiCaption`)。nil ならまとまりごとにブランドの略称を刷る。
    var oshiCaption: String? = nil
    /// 数で畳んだ担当の人数 (「+2」)。
    var moreOshi: Int = 0
    /// 右下に刷るハンドル (「@fuga_p」)。
    var handle: String? = nil
    /// 名前の書体の PostScript 名 (デザインの書体)。
    var nameFont: String? = nil
    /// 名刺の写真 (右に正方形の枠で)。
    var portrait: ImasMeishiPicture? = nil
    /// 名刺の写真を丸く切る (X のアイコン。切り方はコアの `cardPhotoShape`)。
    var portraitRound = false
    let ink: ImasMeishiInk
    /// 紙の上の寸法を何倍で描くか (画面は幅に合わせる)。
    var scale: CGFloat = 1

    private func p(_ v: CGFloat) -> CGFloat { v * scale }

    var body: some View {
        Group {
            switch look {
            case .pass: passBody
            case .formal: formalBody
            case .pop: popBody
            }
        }
        .frame(width: p(ImasMeishi.canvas.width), height: p(ImasMeishi.canvas.height))
        .background(ink.paper)
    }

    // MARK: 入場証 (担当色の縦の帯)

    private var passBody: some View {
        HStack(spacing: 0) {
            Rectangle().fill(ink.accent).frame(width: p(18))
            HStack(alignment: .center, spacing: p(14)) {
                VStack(alignment: .leading, spacing: 0) {
                    imprint("PRODUCER PASS", design: .monospaced)
                    Spacer(minLength: p(4))
                    nameText(size: 26)
                    oshiBlock(stamp: 22, font: .system(size: p(8.5), weight: .regular, design: .serif),
                              labelFont: .system(size: p(6), weight: .semibold, design: .monospaced))
                        .padding(.top, p(6))
                    Spacer(minLength: p(4))
                    footer(design: .monospaced, weight: .medium)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                portraitView(border: ink.line, width: p(0.5))
            }
            .padding(.horizontal, p(18))
            .padding(.vertical, p(16))
        }
    }

    // MARK: かしこまった名刺 (担当色は名前の上の細い罫と判子だけ)

    private var formalBody: some View {
        HStack(alignment: .center, spacing: p(16)) {
            VStack(alignment: .leading, spacing: 0) {
                imprint("PRODUCER", design: .serif, tracking: 1.6)
                Rectangle().fill(ink.accent).frame(height: max(p(0.5), 0.5)).padding(.top, p(5))
                Spacer(minLength: p(4))
                oshiBlock(stamp: 18, font: .system(size: p(8), weight: .regular, design: .serif),
                          labelFont: .system(size: p(6), weight: .medium, design: .serif))
                    .padding(.bottom, p(5))
                nameText(size: 25, tracking: 1.3)
                Spacer(minLength: p(4))
                footer(design: .serif, weight: .regular)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            portraitView(border: ink.line, width: p(0.5))
        }
        .padding(.horizontal, p(26))
        .padding(.vertical, p(20))
    }

    // MARK: ポップ (墨の太い枠・担当色の太い帯と名前の下の太い線)

    private var popBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text(imprintText("PRODUCER!"))
                    .font(.system(size: p(7.5), weight: .heavy, design: .rounded))
                    .tracking(p(0.8))
                    .foregroundStyle(ink.onAccent)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, p(16))
            .frame(height: p(28))
            .background(ink.accent)
            Rectangle().fill(ink.ink).frame(height: p(3))
            HStack(alignment: .center, spacing: p(14)) {
                VStack(alignment: .leading, spacing: p(5)) {
                    nameText(size: 27)
                    Rectangle().fill(ink.accent).frame(width: p(56), height: p(6))
                    oshiBlock(stamp: 20, font: .system(size: p(8.5), weight: .heavy, design: .rounded),
                              labelFont: .system(size: p(6), weight: .heavy, design: .rounded))
                    Spacer(minLength: 0)
                    footer(design: .rounded, weight: .heavy)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                portraitView(border: ink.ink, width: p(2))
            }
            .padding(.horizontal, p(16))
            .padding(.vertical, p(12))
        }
        .overlay(Rectangle().strokeBorder(ink.ink, lineWidth: p(5)))
    }

    // MARK: 共通

    private func imprintText(_ head: String) -> String {
        [head, sinceImprint].compactMap { $0 }.joined(separator: " · ")
    }

    private func imprint(_ head: String, design: Font.Design, tracking: CGFloat = 1.1) -> some View {
        Text(imprintText(head))
            .font(.system(size: p(6.5), weight: .medium, design: design))
            .tracking(p(tracking))
            .foregroundStyle(ink.sub)
            .lineLimit(1)
    }

    private func nameText(size: CGFloat, tracking: CGFloat = 0) -> some View {
        Text(name)
            .font(.imasCardNameFixed(nameFont, size: p(size)))
            .tracking(p(tracking))
            .foregroundStyle(ink.ink)
            .lineLimit(2)
            .minimumScaleFactor(0.45)
    }

    /// 担当の判子 (写真) をブランドごとにまとめた並びと、その下の 1 行 (「星井美希 担当」) か
    /// まとまりごとのブランドの略称。名刺に載る担当 (5 人) が全員、名前・写真と重ならずに並ぶ大きさ。
    @ViewBuilder
    private func oshiBlock(stamp: CGFloat, font: Font, labelFont: Font) -> some View {
        if !oshiGroups.isEmpty {
            VStack(alignment: .leading, spacing: p(3)) {
                HStack(alignment: .top, spacing: p(7)) {
                    ForEach(oshiGroups) { group in
                        VStack(alignment: .leading, spacing: p(2)) {
                            HStack(spacing: p(3)) {
                                ForEach(group.oshi) { ImasMeishiStamp(oshi: $0, size: p(stamp), paper: ink.paper) }
                            }
                            if oshiCaption == nil, !group.label.isEmpty {
                                Text(group.label)
                                    .font(labelFont)
                                    .foregroundStyle(ink.sub)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                    }
                    if moreOshi > 0 {
                        Text("+\(moreOshi)")
                            .font(.system(size: p(stamp * 0.36), weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(ink.ink)
                            .frame(width: p(stamp), height: p(stamp))
                            .overlay(Circle().strokeBorder(ink.line, lineWidth: max(p(0.75), 0.5)))
                    }
                }
                if let oshiCaption {
                    Text(oshiCaption)
                        .font(font)
                        .foregroundStyle(ink.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
    }

    private func footer(design: Font.Design, weight: Font.Weight) -> some View {
        HStack(alignment: .lastTextBaseline) {
            if let handle {
                Text(handle)
                    .font(.system(size: p(8), weight: weight, design: design))
                    .foregroundStyle(ink.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: p(6))
            Text("IDOL LIVE DB")
                .font(.system(size: p(5.5), weight: weight, design: design))
                .tracking(p(1.1))
                .foregroundStyle(ink.sub)
                .lineLimit(1)
        }
    }

    /// 名刺の写真の正方形の枠 (X のアイコンは枠に内接する丸)。枠の大きさを先に決め、写真はその上に
    /// 重ねて切る (写真の比率で枠が膨らまないように。実機の縦長の写真ではみ出したことがある)。
    @ViewBuilder
    private func portraitView(border: Color, width: CGFloat) -> some View {
        if let portrait {
            let shape = RoundedRectangle(cornerRadius: portraitRound ? p(42) : p(2), style: .circular)
            Color.clear
                .frame(width: p(84), height: p(84))
                .overlay { ImasMeishiPictureView(picture: portrait) }
                .clipShape(shape)
                .overlay(shape.strokeBorder(border, lineWidth: max(width, 0.5)))
        }
    }
}

// MARK: - 裏

struct ImasMeishiBack: View {
    /// QR の模様 (`ImasQRCode.render`)。まだ無ければ紙のまま。
    var qr: UIImage?
    /// QR の横に刷る案内。
    var note: String
    var showCount: UInt32? = nil
    var songCount: UInt32? = nil
    /// 「2026.10.06 時点」(コアの `CardFace.issuedLabel`)。
    let issuedLabel: String
    let ink: ImasMeishiInk
    var scale: CGFloat = 1

    private func p(_ v: CGFloat) -> CGFloat { v * scale }

    var body: some View {
        HStack(spacing: p(18)) {
            Group {
                if let qr {
                    Image(uiImage: qr)
                        .renderingMode(.template)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(ink.ink)
                } else {
                    ink.paper
                }
            }
            .frame(width: p(164), height: p(164))
            VStack(alignment: .leading, spacing: p(8)) {
                if let showCount { metric(showCount, label: "参加公演") }
                if let songCount { metric(songCount, label: "回収曲") }
                Spacer(minLength: 0)
                Text(note)
                    .font(.system(size: p(6.5), weight: .regular))
                    .foregroundStyle(ink.sub)
                    .fixedSize(horizontal: false, vertical: true)
                Text(issuedLabel)
                    .font(.system(size: p(6.5), weight: .medium, design: .monospaced))
                    .foregroundStyle(ink.sub)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(.horizontal, p(20))
        .padding(.vertical, p(24))
        .frame(width: p(ImasMeishi.canvas.width), height: p(ImasMeishi.canvas.height))
        .background(ink.paper)
    }

    private func metric(_ value: UInt32, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value.formatted())
                .font(.system(size: p(23), weight: .heavy).width(.compressed).monospacedDigit())
                .foregroundStyle(ink.ink)
            Text(label)
                .font(.system(size: p(7), weight: .semibold))
                .foregroundStyle(ink.sub)
        }
    }
}

// MARK: - 担当の判子

/// 表に並べる担当 1 人。写真があれば写真、無ければ紙に担当色の略称 (判子)。縁は担当色。
struct ImasMeishiStamp: View {
    let oshi: ImasMeishiOshi
    let size: CGFloat
    let paper: Color

    var body: some View {
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                if let picture = oshi.picture {
                    ImasMeishiPictureView(picture: picture, fallback: stamp)
                } else {
                    stamp
                }
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(oshi.color, lineWidth: max(size * 0.07, 0.75)))
    }

    private var stamp: some View {
        ZStack {
            paper
            Text(oshi.shortName)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(oshi.color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, size * 0.1)
        }
    }
}

/// 名刺の画像 1 枚。置いた枠いっぱいに広げる (枠で切るのは置いた側)。
/// URL は読み込みながら出し、読めないあいだは `fallback` (判子など) か紙の地。
struct ImasMeishiPictureView<Fallback: View>: View {
    let picture: ImasMeishiPicture
    var contentMode: ContentMode = .fill
    var fallback: Fallback

    init(picture: ImasMeishiPicture, contentMode: ContentMode = .fill, fallback: Fallback) {
        self.picture = picture
        self.contentMode = contentMode
        self.fallback = fallback
    }

    var body: some View {
        switch picture {
        case let .image(image):
            Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
        case let .url(url):
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: contentMode)
                } else {
                    fallback
                }
            }
        }
    }
}

extension ImasMeishiPictureView where Fallback == Color {
    init(picture: ImasMeishiPicture, contentMode: ContentMode = .fill) {
        self.init(picture: picture, contentMode: contentMode, fallback: DS.surface2)
    }
}
