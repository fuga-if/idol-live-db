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
//                  - 担当を大きく (oshi): 左半分に担当の画像を大きく (1 人なら 1 枚、複数なら分けて。先頭ほど
//                    大きな枠。並びはコアの `CardFace.heroIdolIds`)。画像の無い担当は大きな判子と名前。
//                    右に名前・P歴・名刺の写真・ハンドル。境目に担当色の細い縦の線。
//                  - チケット (ticket): 右に切り取り線と担当色の半券 (名刺の写真と P歴の年)。
//                  - 縦書き (vertical): 明朝の名前を右に縦に大きく、左に名刺の写真・担当・ハンドル。
//                  - 墨一色 (sumi): 罫も帯も無い紙に名前を大きく。担当色は名前の下の点 1 つだけ。
//                  - 夜公演 (night): 黒い紙に白い文字。担当色は上の細い線と写真の縁と判子だけ。
//                  帯・罫・判子を刷る色 (`ink.accent`) は名刺の刷る色 (コアの `CardFace.accentIdolId`)。
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
    /// 夜公演 (黒い紙) で刷る担当の色。暗い紙の上でも沈まない色。
    var nightAccent: Color? = nil

    /// 画面の名刺。ダークでも紙は明るいチケットの紙 (QR を読めるように・紙の名刺に見えるように)。
    /// 担当の色は明るい紙の上の色で引く。
    static func screen(seed: String?, brand: String?) -> ImasMeishiInk {
        let theme = ImasTheme.derive(seed: seed, brand: brand, scheme: .light)
        let night = ImasTheme.derive(seed: seed, brand: brand, scheme: .dark)
        return ImasMeishiInk(
            paper: DS.ticket, ink: DS.ticketInk, sub: DS.ticketSub, line: DS.ticketDash,
            accent: theme.isNeutral ? DS.ticketInk : theme.accent,
            onAccent: theme.isNeutral ? DS.ticket : theme.onAccent,
            nightAccent: night.isNeutral ? nil : night.accent
        )
    }

    /// 夜公演の黒い紙と白い墨 (紙に刷る画像も画面も同じ固定色。担当の色だけ受け継ぐ)。
    var night: ImasMeishiInk {
        let paper = Color(.sRGB, red: 0x17 / 255, green: 0x16 / 255, blue: 0x1A / 255)
        let white = Color(.sRGB, red: 0xF4 / 255, green: 0xF1 / 255, blue: 0xEA / 255)
        let accent = nightAccent ?? white
        return ImasMeishiInk(paper: paper, ink: white,
                             sub: Color(.sRGB, red: 0xA3 / 255, green: 0x9F / 255, blue: 0x98 / 255),
                             line: white.opacity(0.22), accent: accent, onAccent: paper, nightAccent: accent)
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

/// 名刺の表に重ねる素材 1 枚 (置き方はコアの `CardSticker`: 紙に対する中心・幅・傾き)。
struct ImasMeishiSticker: Identifiable {
    let id: String
    let picture: ImasMeishiPicture
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let rotationDegrees: Double
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
    enum Look { case pass, ticket, formal, vertical, pop, sumi, night, oshi, cheki, trading, stripes }

    /// トレカのデザインの下に並べるステータス 1 つ (「公演」「87」)。
    struct Stat: Hashable {
        let label: String
        let value: String
    }

    var look: Look = .pass
    let name: String
    /// 「SINCE 2014」(コアの `CardFace.sinceImprint`)。
    var sinceImprint: String? = nil
    /// 表に並べる担当のブランドごとのまとまり (コアの `CardFace.oshiGroups` の順)。
    var oshiGroups: [ImasMeishiOshiGroup] = []
    /// 担当を大きく並べる順 (担当を大きく のデザインだけ。コアの `CardFace.heroIdolIds` の順)。
    var hero: [ImasMeishiOshi] = []
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
    /// 表の上に重ねる素材 (重なりの順)。
    var stickers: [ImasMeishiSticker] = []
    /// トレカのデザインのステータス (P歴・参加公演・回収曲。名刺に載っているものだけ)。
    var stats: [Stat] = []
    /// 渡された紙と墨 (夜公演はここから黒い紙を組む。描くときは `ink`)。
    private let baseInk: ImasMeishiInk
    /// 紙の上の寸法を何倍で描くか (画面は幅に合わせる)。
    var scale: CGFloat = 1

    init(look: Look = .pass, name: String, sinceImprint: String? = nil, oshiGroups: [ImasMeishiOshiGroup] = [],
         hero: [ImasMeishiOshi] = [], oshiCaption: String? = nil, moreOshi: Int = 0, handle: String? = nil,
         nameFont: String? = nil, portrait: ImasMeishiPicture? = nil, portraitRound: Bool = false,
         stickers: [ImasMeishiSticker] = [], stats: [Stat] = [], ink: ImasMeishiInk, scale: CGFloat = 1) {
        self.look = look
        self.name = name
        self.sinceImprint = sinceImprint
        self.oshiGroups = oshiGroups
        self.hero = hero
        self.oshiCaption = oshiCaption
        self.moreOshi = moreOshi
        self.handle = handle
        self.nameFont = nameFont
        self.portrait = portrait
        self.portraitRound = portraitRound
        self.stickers = stickers
        self.stats = stats
        self.baseInk = ink
        self.scale = scale
    }

    private var ink: ImasMeishiInk { look == .night ? baseInk.night : baseInk }

    private func p(_ v: CGFloat) -> CGFloat { v * scale }

    var body: some View {
        Group {
            switch look {
            case .pass: passBody
            case .ticket: ticketBody
            case .formal: formalBody
            case .vertical: verticalBody
            case .pop: popBody
            case .sumi: sumiBody
            case .night: nightBody
            case .cheki: chekiBody
            case .trading: tradingBody
            case .stripes: stripesBody
            case .oshi: oshiBody
            }
        }
        .frame(width: p(ImasMeishi.canvas.width), height: p(ImasMeishi.canvas.height))
        .background(ink.paper)
        .overlay { ImasMeishiStickerLayer(stickers: stickers, scale: scale) }
        .clipped()
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

    // MARK: チケット (右に切り取り線と担当色の半券)

    /// 半券の幅。
    private static let stubWidth: CGFloat = 92

    private var ticketBody: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                imprint("ADMIT ONE PRODUCER", design: .monospaced)
                Spacer(minLength: p(4))
                nameText(size: 25)
                oshiBlock(stamp: 20, font: .system(size: p(8.5), weight: .regular, design: .serif),
                          labelFont: .system(size: p(6), weight: .semibold, design: .monospaced))
                    .padding(.top, p(6))
                Spacer(minLength: p(4))
                footer(design: .monospaced, weight: .medium)
            }
            .padding(.leading, p(20))
            .padding(.trailing, p(14))
            .padding(.vertical, p(16))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            // 切り取り線 (上下に半円の切り欠き)。
            ZStack {
                Rectangle()
                    .stroke(ink.line, style: StrokeStyle(lineWidth: max(p(1), 0.5), dash: [p(3), p(2.5)]))
                    .frame(width: max(p(1), 0.5))
                    .padding(.vertical, p(10))
                VStack {
                    Circle().strokeBorder(ink.line, lineWidth: max(p(0.75), 0.5))
                        .frame(width: p(12), height: p(12)).offset(y: -p(6))
                    Spacer()
                    Circle().strokeBorder(ink.line, lineWidth: max(p(0.75), 0.5))
                        .frame(width: p(12), height: p(12)).offset(y: p(6))
                }
            }
            .frame(width: p(12))
            VStack(spacing: p(8)) {
                portraitView(border: ink.onAccent, width: p(1.5), side: 58)
                Spacer(minLength: 0)
                Text("SINCE")
                    .font(.system(size: p(6), weight: .semibold, design: .monospaced))
                    .tracking(p(1.4))
                    .foregroundStyle(ink.onAccent.opacity(0.8))
                Text(sinceYear ?? "—")
                    .font(.system(size: p(20), weight: .heavy, design: .monospaced).monospacedDigit())
                    .foregroundStyle(ink.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.vertical, p(16))
            .padding(.horizontal, p(10))
            .frame(width: p(Self.stubWidth))
            .frame(maxHeight: .infinity)
            .background(ink.accent)
        }
    }

    /// P歴の年だけ (「SINCE 2014」の「2014」)。
    private var sinceYear: String? {
        sinceImprint?.split(separator: " ").last.map(String.init)
    }

    // MARK: 縦書き (明朝の名前を右に縦に)

    private var verticalBody: some View {
        HStack(alignment: .top, spacing: p(14)) {
            VStack(alignment: .leading, spacing: p(8)) {
                portraitView(border: ink.line, width: p(0.5), side: 64)
                Spacer(minLength: 0)
                oshiBlock(stamp: 18, font: .system(size: p(8), weight: .regular, design: .serif),
                          labelFont: .system(size: p(6), weight: .medium, design: .serif))
                footer(design: .serif, weight: .regular)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(alignment: .top, spacing: p(8)) {
                if let sinceYear {
                    ImasMeishiVerticalText(text: "\(Self.kanjiDigits(sinceYear))年就任", font: .system(size: p(7.5), weight: .regular,
                                                                                     design: .serif),
                                           color: ink.sub, step: p(9.5))
                        .padding(.top, p(4))
                }
                Rectangle().fill(ink.accent).frame(width: max(p(1), 0.5))
                verticalName
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, p(22))
        .padding(.vertical, p(18))
    }

    /// 縦書きの年は漢数字で (「2014」→「二〇一四」。算用数字は縦に積むと読みにくい)。
    private static func kanjiDigits(_ s: String) -> String {
        let map: [Character: Character] = ["0": "〇", "1": "一", "2": "二", "3": "三", "4": "四",
                                           "5": "五", "6": "六", "7": "七", "8": "八", "9": "九"]
        return String(s.map { map[$0] ?? $0 })
    }

    /// 縦に組む名前。紙の高さに収まる大きさに縮める (長い名前は 2 列に折る)。
    private var verticalName: some View {
        let chars = Array(name)
        let room = ImasMeishi.canvas.height - 36
        let perColumn = max(1, Int((room / 30).rounded(.down)))
        let columns = chars.count > perColumn * 2 ? 2 : (chars.count > perColumn ? 2 : 1)
        let rows = Int((Double(chars.count) / Double(columns)).rounded(.up))
        let size = min(30, room / CGFloat(max(rows, 1)) * 0.92)
        let parts: [String] = (0..<columns).map { c in
            String(chars[min(c * rows, chars.count)..<min((c + 1) * rows, chars.count)])
        }
        return HStack(alignment: .top, spacing: p(size * 0.25)) {
            // 縦書きは右の列から読む。
            ForEach(Array(parts.enumerated().reversed()), id: \.offset) { _, part in
                ImasMeishiVerticalText(text: part, font: .imasCardNameFixed(nameFont, size: p(size)),
                                       color: ink.ink, step: p(size * 1.04))
            }
        }
    }

    // MARK: 墨一色 (名前を大きく、担当色は点 1 つ)

    private var sumiBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                imprint("PRODUCER", design: .serif, tracking: 2)
                Spacer(minLength: p(8))
                portraitView(border: ink.line, width: p(0.5), side: 42)
            }
            Spacer(minLength: 0)
            nameText(size: 32, tracking: 2)
            Circle().fill(ink.accent).frame(width: p(5), height: p(5)).padding(.top, p(8))
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                oshiBlock(stamp: 15, font: .system(size: p(7.5), weight: .regular, design: .serif),
                          labelFont: .system(size: p(5.5), weight: .medium, design: .serif))
                Spacer(minLength: p(6))
                if let handle {
                    Text(handle)
                        .font(.system(size: p(8), weight: .regular, design: .serif))
                        .foregroundStyle(ink.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .padding(.horizontal, p(28))
        .padding(.vertical, p(20))
    }

    // MARK: 夜公演 (黒い紙・白い文字)

    private var nightBody: some View {
        VStack(spacing: 0) {
            Rectangle().fill(ink.accent).frame(height: p(3))
            HStack(alignment: .center, spacing: p(14)) {
                VStack(alignment: .leading, spacing: 0) {
                    imprint("TONIGHT'S PRODUCER", design: .monospaced, tracking: 1.6)
                    Spacer(minLength: p(4))
                    nameText(size: 26)
                    oshiBlock(stamp: 22, font: .system(size: p(8.5), weight: .regular),
                              labelFont: .system(size: p(6), weight: .semibold, design: .monospaced))
                        .padding(.top, p(6))
                    Spacer(minLength: p(4))
                    footer(design: .monospaced, weight: .medium)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                portraitView(border: ink.accent, width: p(1.5))
            }
            .padding(.horizontal, p(20))
            .padding(.vertical, p(16))
        }
    }

    // MARK: チェキ (左に少し傾けたチェキ、下の余白に名前)

    /// チェキの写真: 名刺の写真、無ければ先頭の担当の画像、どちらも無ければ先頭の担当の判子。
    @ViewBuilder
    private func chekiPhoto(side: CGFloat) -> some View {
        Color.clear
            .frame(width: p(side), height: p(side))
            .overlay {
                if let portrait {
                    ImasMeishiPictureView(picture: portrait)
                } else if let lead = hero.first, let picture = lead.picture {
                    ImasMeishiPictureView(picture: picture)
                } else if let lead = hero.first {
                    ImasMeishiStamp(oshi: lead, size: p(side * 0.7), paper: ink.paper)
                } else {
                    ink.line.opacity(0.35)
                }
            }
            .clipped()
    }

    private var chekiBody: some View {
        HStack(alignment: .center, spacing: p(16)) {
            VStack(spacing: p(6)) {
                chekiPhoto(side: 120)
                Text(name)
                    .font(.imasCardNameFixed(nameFont, size: p(15)))
                    .foregroundStyle(ink.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: p(120))
                    .padding(.bottom, p(10))
            }
            .padding(.horizontal, p(8))
            .padding(.top, p(8))
            .background(ink.paper)
            .overlay(Rectangle().strokeBorder(ink.line, lineWidth: max(p(0.75), 0.5)))
            .rotationEffect(.degrees(-3))
            VStack(alignment: .leading, spacing: 0) {
                imprint("CHEKI", design: .rounded)
                Spacer(minLength: p(4))
                oshiBlock(stamp: 18, font: .system(size: p(8.5), weight: .heavy, design: .rounded),
                          labelFont: .system(size: p(6), weight: .heavy, design: .rounded))
                Spacer(minLength: p(4))
                footer(design: .rounded, weight: .heavy)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(.horizontal, p(20))
        .padding(.vertical, p(16))
    }

    // MARK: トレカ (担当色の太い枠・大きな画像・ステータス)

    private var tradingBody: some View {
        VStack(spacing: p(6)) {
            HStack(alignment: .firstTextBaseline) {
                nameText(size: 18)
                Spacer(minLength: p(6))
                if let handle {
                    Text(handle)
                        .font(.system(size: p(7.5), weight: .semibold, design: .monospaced))
                        .foregroundStyle(ink.sub)
                        .lineLimit(1)
                }
            }
            HStack(spacing: p(10)) {
                Color.clear
                    .overlay {
                        if let portrait {
                            ImasMeishiPictureView(picture: portrait)
                        } else if !hero.isEmpty {
                            ImasMeishiHero(oshi: hero, paper: ink.paper, ink: ink.ink, gap: p(1.5), scale: scale)
                        } else {
                            ink.line.opacity(0.35)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: p(6), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: p(6), style: .continuous)
                        .strokeBorder(ink.accent, lineWidth: p(1.5)))
                VStack(alignment: .leading, spacing: p(4)) {
                    oshiBlock(stamp: 16, font: .system(size: p(7.5), weight: .semibold),
                              labelFont: .system(size: p(5.5), weight: .semibold, design: .monospaced))
                    Spacer(minLength: 0)
                    if let sinceImprint {
                        Text(sinceImprint)
                            .font(.system(size: p(6.5), weight: .semibold, design: .monospaced))
                            .tracking(p(1))
                            .foregroundStyle(ink.sub)
                    }
                }
                .frame(width: p(118), alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            if !stats.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { i, stat in
                        if i > 0 { Rectangle().fill(ink.line).frame(width: max(p(0.75), 0.5)) }
                        VStack(spacing: 0) {
                            Text(stat.value)
                                .font(.system(size: p(14), weight: .heavy, design: .rounded).monospacedDigit())
                                .foregroundStyle(ink.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(stat.label)
                                .font(.system(size: p(6), weight: .semibold))
                                .foregroundStyle(ink.sub)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, p(4))
                .overlay(alignment: .top) { Rectangle().fill(ink.accent).frame(height: p(1.5)) }
            }
        }
        .padding(p(12))
        .overlay(Rectangle().strokeBorder(ink.accent, lineWidth: p(7)))
    }

    // MARK: 推しの色の縞 (左の帯を載せた担当の色の縞に)

    private var stripesBody: some View {
        let colors = oshiGroups.flatMap(\.oshi).map(\.color)
        return HStack(spacing: 0) {
            HStack(spacing: 0) {
                if colors.isEmpty {
                    ink.accent
                } else {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in color }
                }
            }
            .frame(width: p(30))
            HStack(alignment: .center, spacing: p(14)) {
                VStack(alignment: .leading, spacing: 0) {
                    imprint("PRODUCER", design: .monospaced)
                    Spacer(minLength: p(4))
                    nameText(size: 26)
                    oshiBlock(stamp: 22, font: .system(size: p(8.5), weight: .regular),
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

    // MARK: 担当を大きく (左半分に担当の画像)

    /// 左の担当の画像の枠の幅 (紙の半分より少し狭く、右の名前の欄を確保する)。
    private static let heroWidth: CGFloat = 170

    private var oshiBody: some View {
        HStack(spacing: 0) {
            ImasMeishiHero(oshi: hero, paper: ink.paper, ink: ink.ink, gap: p(1.5), scale: scale)
                .frame(width: p(Self.heroWidth), height: p(ImasMeishi.canvas.height))
                .clipped()
            Rectangle().fill(ink.accent).frame(width: p(3))
            VStack(alignment: .leading, spacing: p(6)) {
                HStack(alignment: .top, spacing: p(8)) {
                    imprint("PRODUCER", design: .monospaced)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    portraitView(border: ink.line, width: p(0.5), side: 44)
                }
                nameText(size: 24)
                heroCaption
                Spacer(minLength: 0)
                footer(design: .monospaced, weight: .medium)
            }
            .padding(.horizontal, p(14))
            .padding(.vertical, p(14))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// 担当を大きく のデザインの名前の下の 1 行 (「星井美希 担当」、無ければブランドの略称、畳んだ数)。
    @ViewBuilder
    private var heroCaption: some View {
        let labels = oshiGroups.map(\.label).filter { !$0.isEmpty }
        let line = oshiCaption ?? (labels.isEmpty ? nil : labels.joined(separator: "・"))
        let more = moreOshi > 0 ? "+\(moreOshi)" : nil
        let text = [line, more].compactMap { $0 }.joined(separator: "  ")
        if !text.isEmpty {
            Text(text)
                .font(.system(size: p(8), weight: .medium))
                .foregroundStyle(ink.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
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
    private func portraitView(border: Color, width: CGFloat, side: CGFloat = 84) -> some View {
        if let portrait {
            let shape = RoundedRectangle(cornerRadius: portraitRound ? p(side / 2) : p(2), style: .circular)
            Color.clear
                .frame(width: p(side), height: p(side))
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

// MARK: - 担当を大きく

/// 担当を大きく のデザインの左の枠。担当の画像を枠いっぱいに分けて並べる (先頭ほど大きな枠)。
/// 1 人: 1 枚 / 2 人: 左右 / 3 人: 左に先頭、右に 2 段 / 4 人: 2×2 / 5 人: 上に 2 枚、下に 3 枚。
/// 画像は枠の上に重ねて上寄せで切る (縦長の担当の画像で顔が切れにくいように)。画像の無い担当は大きな判子と名前。
struct ImasMeishiHero: View {
    let oshi: [ImasMeishiOshi]
    let paper: Color
    let ink: Color
    /// 枠と枠の間の紙の幅。
    let gap: CGFloat
    var scale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                paper
                ForEach(Array(Self.tiles(count: oshi.count).enumerated()), id: \.offset) { index, tile in
                    let rect = CGRect(x: tile.minX * w, y: tile.minY * h, width: tile.width * w, height: tile.height * h)
                        .insetBy(dx: gap / 2, dy: gap / 2)
                    ImasMeishiHeroTile(oshi: oshi[index], paper: paper, ink: ink, scale: scale)
                        .frame(width: max(rect.width, 0), height: max(rect.height, 0))
                        .clipped()
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
    }

    /// 人数ごとの枠 (枠全体を 1 とした割合)。
    static func tiles(count: Int) -> [CGRect] {
        switch count {
        case 0: return []
        case 1: return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        case 2: return [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]
        case 3: return [CGRect(x: 0, y: 0, width: 0.5, height: 1),
                        CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]
        case 4: return [CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                        CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]
        default:
            let top = 0.55, third = 1.0 / 3
            return [CGRect(x: 0, y: 0, width: 0.5, height: top), CGRect(x: 0.5, y: 0, width: 0.5, height: top)]
                + (0..<3).map { CGRect(x: Double($0) * third, y: top, width: third, height: 1 - top) }
        }
    }
}

/// 担当を大きく の枠 1 つ。画像は上寄せで枠いっぱい、無ければ判子と名前。
private struct ImasMeishiHeroTile: View {
    let oshi: ImasMeishiOshi
    let paper: Color
    let ink: Color
    let scale: CGFloat

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if let picture = oshi.picture {
                ImasMeishiPictureView(picture: picture, fallback: stamp(size))
                    .frame(width: size.width, height: size.height, alignment: .top)
            } else {
                stamp(size)
            }
        }
    }

    private func stamp(_ size: CGSize) -> some View {
        let side = min(size.width, size.height) * 0.62
        return VStack(spacing: side * 0.08) {
            ImasMeishiStamp(oshi: oshi, size: side, paper: paper)
            if size.height > side * 1.5 {
                Text(oshi.name)
                    .font(.system(size: max(side * 0.14, 6 * scale), weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, side * 0.1)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(paper)
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

// MARK: - 縦書き

/// 1 字ずつ縦に積む縦書き。長音・ダッシュ・波線は 90° 回し、小書きの仮名は右上に寄せる。
struct ImasMeishiVerticalText: View {
    let text: String
    let font: Font
    let color: Color
    /// 1 字の送り (字の高さ)。
    let step: CGFloat

    private static let rotated: Set<Character> = ["ー", "－", "—", "‐", "-", "〜", "～", "…", "‥", "(", ")", "（", "）",
                                                   "「", "」", "[", "]"]
    private static let small: Set<Character> = ["ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "っ", "ゃ", "ゅ", "ょ", "ゎ",
                                                 "ァ", "ィ", "ゥ", "ェ", "ォ", "ッ", "ャ", "ュ", "ョ", "ヮ", "、", "。"]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, c in
                Text(String(c))
                    .font(font)
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(Self.rotated.contains(c) ? 90 : 0))
                    .offset(x: Self.small.contains(c) ? step * 0.12 : 0, y: Self.small.contains(c) ? -step * 0.12 : 0)
                    .frame(width: step, height: step)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - 素材

/// 名刺の表に重ねる素材の層。素材は紙の大きさに対する割合で置き、紙の外にはみ出した分は切る。
struct ImasMeishiStickerLayer: View {
    let stickers: [ImasMeishiSticker]
    var scale: CGFloat = 1

    var body: some View {
        let w = ImasMeishi.canvas.width * scale, h = ImasMeishi.canvas.height * scale
        ZStack(alignment: .topLeading) {
            ForEach(stickers) { sticker in
                ImasMeishiPictureView(picture: sticker.picture, contentMode: .fit, fallback: Color.clear)
                    .frame(width: w * sticker.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .rotationEffect(.degrees(sticker.rotationDegrees))
                    .position(x: w * sticker.x, y: h * sticker.y)
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
