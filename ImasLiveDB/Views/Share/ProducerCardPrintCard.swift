import SwiftUI

// =============================================================================
// 紙に刷る P名刺 (91×55mm、日本の名刺の大きさ)。
//
// 表 = 名刺のデザインごとの組み (入場証は担当色の縦の帯、かしこまった名刺は明朝と細い罫、
//      ポップは墨の太い枠と担当色の太い帯)。名前・担当・ハンドル・名刺の写真 (あれば右に証明写真)。
//      自作の画像の名刺は、その画像をそのまま刷る (`ProducerCardPrintImage`)。
//      印刷所の名刺テンプレにそのまま載る余白を残す。
// 裏 = QR (既定はアプリの交換と同じ中身。自分の QR も選べる)・参加公演数と回収曲数・「YYYY.MM.DD 時点」。
//
// ImageRenderer で焼く固定のキャンバスなので、色は固定色 (ShareInk / ShareCardPalette)、文字は固定 pt。
// =============================================================================

enum ProducerCardPrint {
    /// 91:55 の論理サイズ (pt)。3 倍で焼いて 1638×990px (350dpi 相当)。
    static let size = ShareCard.Size(width: 546, height: 330)
    static let renderScale: CGFloat = 3

    static let ink = ShareInk.nearBlack
    static let paper = ShareInk.offWhite
    static let sub = Color(.sRGB, red: 0x5A / 255, green: 0x57 / 255, blue: 0x55 / 255)

    @MainActor
    static func render(_ card: some View) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = renderScale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// 表。デザイン (入場証・かしこまった名刺・ポップ) ごとに組みを変える。載せるものは同じ。
struct ProducerCardPrintFront: View {
    enum Look { case pass, formal, pop }

    var look: Look = .pass
    let name: String
    var sinceYear: UInt16? = nil
    /// 担当の名前 (「天海春香・如月千早」)。
    var oshiNames: [String] = []
    /// 担当の色 (帯・罫)。
    var seed: String? = nil
    /// 右下に刷るハンドル (「@fuga_p」)。
    var handle: String? = nil
    /// 名前の書体の PostScript 名 (コアのデザインの書体)。
    var nameFont: String? = nil
    /// 名刺の写真 (右に証明写真の大きさで刷る)。
    var portrait: UIImage? = nil

    private var accent: Color { seed == nil ? ProducerCardPrint.ink : ShareCardPalette(seed: seed).accent }

    var body: some View {
        Group {
            switch look {
            case .pass: passBody
            case .formal: formalBody
            case .pop: popBody
            }
        }
        .frame(width: ProducerCardPrint.size.width, height: ProducerCardPrint.size.height)
        .background(ProducerCardPrint.paper)
    }

    // MARK: 入場証 (担当色の縦の帯)

    private var passBody: some View {
        HStack(spacing: 0) {
            Rectangle().fill(accent).frame(width: 30)
            HStack(alignment: .center, spacing: 22) {
                info(imprint: "PRODUCER PASS", nameSize: 40, oshiFont: .system(size: 13, weight: .regular, design: .serif))
                portraitView(border: ProducerCardPrint.sub.opacity(0.35), width: 0.5)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
        }
    }

    // MARK: かしこまった名刺 (担当色は名前の上の細い罫だけ)

    private var formalBody: some View {
        HStack(alignment: .center, spacing: 26) {
            VStack(alignment: .leading, spacing: 0) {
                Text(["PRODUCER", sinceYear.map { "SINCE \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .tracking(2.4)
                    .foregroundStyle(ProducerCardPrint.sub)
                Rectangle().fill(accent).frame(height: 0.75).padding(.top, 8)
                Spacer(minLength: 0)
                if !oshiNames.isEmpty {
                    Text("\(oshiNames.joined(separator: "・")) 担当")
                        .font(.system(size: 12, weight: .regular, design: .serif))
                        .foregroundStyle(ProducerCardPrint.sub)
                        .lineLimit(2)
                        .padding(.bottom, 6)
                }
                Text(name)
                    .font(.imasCardNameFixed(nameFont, size: 38))
                    .tracking(2)
                    .foregroundStyle(ProducerCardPrint.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline) {
                    if let handle {
                        Text(handle)
                            .font(.system(size: 11, weight: .regular, design: .serif))
                            .foregroundStyle(ProducerCardPrint.ink)
                    }
                    Spacer(minLength: 8)
                    Text("IDOL LIVE DB")
                        .font(.system(size: 8, weight: .regular, design: .serif))
                        .tracking(1.6)
                        .foregroundStyle(ProducerCardPrint.sub)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            portraitView(border: ProducerCardPrint.sub.opacity(0.35), width: 0.5)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
    }

    // MARK: ポップ (墨の太い枠・担当色の太い帯と名前の下の太い線)

    private var popBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text(["PRODUCER!", sinceYear.map { "SINCE \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(seed == nil ? ProducerCardPrint.paper : ProducerCardPrint.ink)
                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(height: 44)
            .background(accent)
            Rectangle().fill(ProducerCardPrint.ink).frame(height: 4)
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .font(.imasCardNameFixed(nameFont, size: 42))
                        .foregroundStyle(ProducerCardPrint.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Rectangle().fill(accent).frame(width: 84, height: 9)
                    if !oshiNames.isEmpty {
                        Text("\(oshiNames.joined(separator: "・")) 担当")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(ProducerCardPrint.ink)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    HStack(alignment: .lastTextBaseline) {
                        if let handle {
                            Text(handle)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(ProducerCardPrint.ink)
                        }
                        Spacer(minLength: 8)
                        Text("IDOL LIVE DB")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(1.6)
                            .foregroundStyle(ProducerCardPrint.sub)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                portraitView(border: ProducerCardPrint.ink, width: 3)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .overlay(Rectangle().strokeBorder(ProducerCardPrint.ink, lineWidth: 8))
    }

    // MARK: 共通

    @ViewBuilder
    private func portraitView(border: Color, width: CGFloat) -> some View {
        if let portrait {
            Image(uiImage: portrait)
                .resizable()
                .scaledToFill()
                .frame(width: 114, height: 152)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(border, lineWidth: width))
        }
    }

    private func info(imprint: String, nameSize: CGFloat, oshiFont: Font) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text([imprint, sinceYear.map { "SINCE \($0)" }].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(ProducerCardPrint.sub)
            Spacer(minLength: 0)
            Text(name)
                .font(.imasCardNameFixed(nameFont, size: nameSize))
                .foregroundStyle(ProducerCardPrint.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !oshiNames.isEmpty {
                Text("\(oshiNames.joined(separator: "・")) 担当")
                    .font(oshiFont)
                    .foregroundStyle(ProducerCardPrint.ink)
                    .lineLimit(2)
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline) {
                if let handle {
                    Text(handle)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(ProducerCardPrint.ink)
                }
                Spacer(minLength: 8)
                Text("IDOL LIVE DB")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(ProducerCardPrint.sub)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
    /// 「2026.10.06 時点」(コアの `cardIssuedLabel`)。
    let issuedLabel: String
    var qrImage: UIImage?

    var body: some View {
        HStack(spacing: 26) {
            Group {
                if let qrImage {
                    Image(uiImage: qrImage)
                        .renderingMode(.template)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(ProducerCardPrint.ink)
                } else {
                    ProducerCardPrint.paper
                }
            }
            .frame(width: 250, height: 250)
            VStack(alignment: .leading, spacing: 12) {
                if let showCount { metric("\(showCount)", label: "参加公演") }
                if let songCount { metric("\(songCount)", label: "回収曲") }
                Spacer(minLength: 0)
                Text(note)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(ProducerCardPrint.sub)
                    .fixedSize(horizontal: false, vertical: true)
                Text(issuedLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(ProducerCardPrint.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 40)
        .frame(width: ProducerCardPrint.size.width, height: ProducerCardPrint.size.height)
        .background(ProducerCardPrint.paper)
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 34, weight: .heavy).width(.compressed).monospacedDigit())
                .foregroundStyle(ProducerCardPrint.ink)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ProducerCardPrint.sub)
        }
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
