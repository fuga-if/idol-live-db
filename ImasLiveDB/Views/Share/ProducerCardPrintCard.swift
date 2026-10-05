import SwiftUI

// =============================================================================
// 紙に刷る P名刺 (91×55mm、日本の名刺の大きさ)。
//
// 表 = 担当色の縦の帯・明朝の名前・担当・ハンドル。印刷所の名刺テンプレにそのまま載る余白を残す。
// 裏 = QR (アプリの交換と同じ中身)・参加公演数と回収曲数・「YYYY.MM.DD 時点」。
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

/// 表。
struct ProducerCardPrintFront: View {
    let name: String
    var sinceYear: UInt16? = nil
    /// 担当の名前 (「天海春香・如月千早」)。
    var oshiNames: [String] = []
    /// 担当の色 (帯)。
    var seed: String? = nil
    /// 右下に刷るハンドル (「@fuga_p」)。
    var handle: String? = nil

    var body: some View {
        let palette = ShareCardPalette(seed: seed)
        HStack(spacing: 0) {
            Rectangle().fill(seed == nil ? ProducerCardPrint.ink : palette.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(["PRODUCER PASS", sinceYear.map { "SINCE \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(ProducerCardPrint.sub)
                Spacer(minLength: 0)
                Text(name)
                    .font(.system(size: 40, weight: .semibold, design: .serif))
                    .foregroundStyle(ProducerCardPrint.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !oshiNames.isEmpty {
                    Text("\(oshiNames.joined(separator: "・")) 担当")
                        .font(.system(size: 13, weight: .regular, design: .serif))
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
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
        }
        .frame(width: ProducerCardPrint.size.width, height: ProducerCardPrint.size.height)
        .background(ProducerCardPrint.paper)
    }
}

/// 裏。
struct ProducerCardPrintBack: View {
    let url: String
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
                Text("読み取るとアプリの名刺入れに入ります。アプリが無ければ Web で開きます。")
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
