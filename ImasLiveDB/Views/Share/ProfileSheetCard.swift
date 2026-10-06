import SwiftUI
import UIKit

// =============================================================================
// プロフィール帳 (SNS に貼る自己紹介の 1 枚絵)。P を職業に見立てた **履歴書** の様式。
//
// - 欄・行・丸・詰め方はコア (`profileSheetLayout`) が決め、ここは描くだけ。
// - 紙は生成り、線は墨。罫の太さは 2 段 (外枠と欄の中)。担当色は押印欄の判子の 1 か所だけ
//   (面を塗らない・帯を引かない)。ブランドの丸はブランドの色の手描きの線 (中身そのものの色)。
// - 字面は事務書類の端正さに寄せる (2026-10 ユーザー「文字の感じが若干垢抜けてない」)。題・名前・欄の題は明朝、
//   本文はゴシック (`ProfileSheetType`)、英字は等幅の大文字の印字だけ。太さは 2 段 (本文 = regular・見出し = semibold)、
//   和文はかなを詰めて (palt) 字間を少し詰め、英字の大文字にだけ字間を足す。数字は等幅。
//   題は大きく本文は控えめにして、大きさの比をはっきり取る。
// - 中身はすべてアプリの記録から (自分で書く欄は無い)。アプリ名の帯 (`ShareCardFooter`) を下に置く。
//
// ImageRenderer で焼く固定のキャンバスなので、色は固定色、文字は固定 pt (docs/DESIGN_SYSTEM.md §13)。
// 画像は読み込み済みの UIImage だけを使う (ImageRenderer は読み込みを待たない)。画像は大きさの決まった枠を
// 先に作ってから重ねて切る (縦長の大きな画像で枠が膨らまないように)。
// =============================================================================

enum ProfileSheetInk {
    /// 生成りの紙。
    static let paper = Color(.sRGB, red: 0xFB / 255, green: 0xF7 / 255, blue: 0xEE / 255)
    static let ink = ShareInk.nearBlack
    /// 設問・項目名の灰。
    static let sub = Color(.sRGB, red: 0x6A / 255, green: 0x66 / 255, blue: 0x63 / 255)
    /// 外枠の罫。
    static let frame: CGFloat = 1.5
    /// 欄の中の罫。
    static let rule: CGFloat = 0.5

    /// QR の辺。詰め方で縮めない (焼いた画像を SNS が縮めても読めるように)。周りに紙の余白を足す。
    static let qrSide: CGFloat = 52

    static func size(_ size: ProfileSheetSize) -> ShareCard.Size {
        size == .story ? ShareCard.Ratio.story.size : ShareCard.Ratio.portrait.size
    }

    /// 詰め方 (コアの `density`) の倍率。縦長のストーリーズは少し大きく組む。
    /// 見積もりより実物が長いときは、ここから 1 段ずつ小さくして収まるものを使う (`ProfileSheetCard`)。
    static func scales(_ layout: ProfileSheetLayout) -> [CGFloat] {
        let steps: [CGFloat] = [1, 0.96, 0.92, 0.88, 0.84, 0.8, 0.76, 0.72, 0.68, 0.64]
        let start = switch layout.density {
        case .regular: 0
        case .compact: 2
        case .tight: 4
        }
        // 9:16 は縦に余るので大きく組む (入らなければ下の段へ)。
        let base: CGFloat = layout.size == .story ? 1.3 : 1
        return steps[start...].map { $0 * base }
    }

    static func accent(_ seed: String?) -> Color {
        seed == nil ? ink : ShareCardPalette(seed: seed).accent
    }
}

/// プロフィール帳の書体。題・名前・欄の題だけ明朝 (ヒラギノ明朝 W6)、ほかはゴシック (ヒラギノ角ゴ)、
/// 英字は等幅の印字。
/// 撮り比べ (2026-10): 「全部ゴシック 1 系統」と並べ、題と名前を明朝にした方が履歴書の用紙らしく
/// 締まって見え (ゴシックの太い題は見出しの圧が強い)、本文はゴシックのままで縮小にも耐えたのでこちらを採った。
enum ProfileSheetType {
    /// 和文 (かなを詰める palt)。`weight` は regular / semibold の 2 段で使う。
    static func jp(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kTextSpacingType,
                UIFontDescriptor.FeatureKey.selector: kAltProportionalTextSelector,
            ]],
        ])
        return Font(UIFont(descriptor: descriptor, size: size))
    }

    /// 数字 (等幅)。
    static func num(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    /// 英字の印字 (等幅の大文字。字間は `imprintTracking`)。
    static func imprint(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    /// 題・名前・欄の題 (ヒラギノ明朝 W6。引けなければ本文のゴシックの semibold)。
    static func display(_ size: CGFloat) -> Font {
        guard let font = UIFont(name: "HiraMinProN-W6", size: size) else { return jp(size, .semibold) }
        return Font(font)
    }

    static let imprintTracking: CGFloat = 2.4
    /// 和文の字間 (少し詰める)。
    static let jpTracking: CGFloat = -0.2
}

private typealias T = ProfileSheetType
private typealias Ink = ProfileSheetInk

/// プロフィール帳 1 枚。
struct ProfileSheetCard: View {
    let layout: ProfileSheetLayout
    let materials: ProfileSheetMaterials

    var body: some View {
        let size = Ink.size(layout.size)
        let scales = Ink.scales(layout)
        VStack(alignment: .leading, spacing: 0) {
            ProfileSheetHeading(layout: layout)
            // コアの詰め方から始めて、収まらなければ小さい方へ (最後の段は下を切る)。
            ViewThatFits(in: .vertical) {
                ForEach(scales, id: \.self) { s in
                    ProfileResumeBody(layout: layout, materials: materials, s: s)
                }
            }
            .padding(.top, 12)
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            .clipped()
            ShareCardFooter(ink: Ink.ink.opacity(0.7), rule: Ink.ink.opacity(0.25))
                .padding(.top, 8)
        }
        .padding(.horizontal, 26)
        .padding(.top, 26)
        .padding(.bottom, 18)
        .frame(width: size.width, height: size.height)
        .background(Ink.paper)
    }
}

// MARK: - 頭 (題・日付)

private struct ProfileSheetHeading: View {
    let layout: ProfileSheetLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(layout.title)
                    .font(T.display(30))
                    .tracking(7)
                Text(layout.imprint)
                    .font(T.imprint(8))
                    .tracking(T.imprintTracking)
                    .foregroundStyle(Ink.sub)
                Spacer(minLength: 8)
                Text(layout.asOf)
                    .font(T.jp(9.5))
                    .monospacedDigit()
            }
            .foregroundStyle(Ink.ink)
            Rectangle().fill(Ink.ink).frame(height: Ink.frame)
        }
    }
}

// MARK: - 履歴書

private struct ProfileResumeBody: View {
    let layout: ProfileSheetLayout
    let materials: ProfileSheetMaterials
    let s: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            identity
            if !layout.brands.isEmpty {
                ProfileBrandRange(title: layout.brandsTitle, brands: layout.brands, s: s)
            }
            if !layout.history.isEmpty || !layout.licenses.isEmpty {
                ProfileBox {
                    VStack(spacing: 0) {
                        if !layout.history.isEmpty {
                            ProfileTableHead(title: "P歴（学歴・職歴）", s: s)
                            ForEach(Array(layout.history.enumerated()), id: \.offset) { i, row in
                                if i > 0 { ProfileRule() }
                                ProfileHistoryLine(row: row, s: s)
                            }
                        }
                        if !layout.licenses.isEmpty {
                            if !layout.history.isEmpty { ProfileRule(width: Ink.frame) }
                            ProfileTableHead(title: "免許・資格", s: s)
                            ForEach(Array(layout.licenses.enumerated()), id: \.offset) { i, row in
                                if i > 0 { ProfileRule() }
                                ProfileHistoryLine(row: row, s: s)
                            }
                        }
                    }
                }
            }
            // 志望の動機は横いっぱい、趣味・特技と本人希望記入欄は左右に並べる (様式の欄の並び)。
            ForEach(layout.sections.filter { $0.slot == .motivation }, id: \.title) { section in
                ProfileBox { ProfileSectionView(section: section, s: s) }
            }
            let pair = layout.sections.filter { $0.slot != .motivation }
            if !pair.isEmpty {
                HStack(alignment: .top, spacing: 10 * s) {
                    ForEach(pair, id: \.title) { section in
                        ProfileBox {
                            ProfileSectionView(section: section, s: s)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 氏名・押印・P歴・担当・連絡先と証明写真。
    private var identity: some View {
        ProfileBox {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ProfileField(label: "氏名", s: s) {
                        HStack(spacing: 8) {
                            Text(layout.name)
                                .font(T.display(24 * s))
                                .tracking(T.jpTracking)
                                .foregroundStyle(Ink.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Spacer(minLength: 0)
                            if layout.showOshi, let oshi = materials.oshi.first {
                                ProfileSeal(oshi: oshi, diameter: 42 * s)
                            }
                        }
                        .padding(.vertical, 3 * s)
                    }
                    if let since = layout.sinceLabel {
                        ProfileRule()
                        ProfileField(label: "P歴", s: s) {
                            Text(since)
                                .font(T.jp(10 * s))
                                .monospacedDigit()
                                .foregroundStyle(Ink.ink)
                                .lineLimit(1)
                        }
                    }
                    if layout.showOshi && !materials.oshi.isEmpty {
                        ProfileRule()
                        ProfileField(label: "担当", s: s) { ProfileOshiList(oshi: materials.oshi, s: s) }
                    }
                    if !layout.contacts.isEmpty || (layout.showQr && materials.qr != nil) {
                        ProfileRule()
                        ProfileField(label: "連絡先", s: s) {
                            HStack(spacing: 8) {
                                Text(layout.contacts.joined(separator: "   "))
                                    .font(T.imprint(9.5 * s))
                                    .foregroundStyle(Ink.ink)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                                Spacer(minLength: 0)
                                if layout.showQr, let qr = materials.qr {
                                    ProfileQR(image: qr, side: Ink.qrSide)
                                }
                            }
                        }
                    }
                }
                Rectangle().fill(Ink.ink).frame(width: Ink.rule)
                ProfilePhotoBox(image: layout.showPhoto ? materials.portrait : nil, round: materials.portraitRound,
                                width: 88 * s)
                    .padding(10 * s)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 部品 (プロフィール帳の中だけ)

/// 墨の罫で囲む欄。
private struct ProfileBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Rectangle().strokeBorder(Ink.ink, lineWidth: Ink.frame))
    }
}

private struct ProfileRule: View {
    var width: CGFloat = Ink.rule

    var body: some View {
        Rectangle().fill(Ink.ink).frame(height: width)
    }
}

/// 項目名と中身の 1 段。
private struct ProfileField<Content: View>: View {
    let label: String
    let s: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(T.jp(7.5 * s, .semibold))
                .foregroundStyle(Ink.sub)
                .frame(width: 34 * s, alignment: .leading)
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 表の頭 (年・月・内容)。下は墨の罫。
private struct ProfileTableHead: View {
    let title: String
    let s: CGFloat

    var body: some View {
        ProfileHistoryColumns(year: "年", month: "月", s: s) {
            Text(title).frame(maxWidth: .infinity)
        }
        .font(T.jp(7.5 * s, .semibold))
        .foregroundStyle(Ink.sub)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.ink).frame(height: Ink.rule * 2) }
    }
}

private struct ProfileHistoryLine: View {
    let row: ProfileHistoryRow
    let s: CGFloat

    var body: some View {
        ProfileHistoryColumns(year: row.year, month: row.month, s: s) {
            Text(row.text)
                .tracking(T.jpTracking)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: row.kind == .closing ? .trailing : .leading)
        }
        .font(T.jp(9.5 * s, row.kind == .closing ? .semibold : .regular))
        .foregroundStyle(Ink.ink)
    }
}

/// 年 | 月 | 内容 の 3 列。
private struct ProfileHistoryColumns<Content: View>: View {
    let year: String
    let month: String
    let s: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            Text(year).monospacedDigit().frame(width: 38 * s)
            Rectangle().fill(Ink.ink).frame(width: Ink.rule)
            Text(month).monospacedDigit().frame(width: 24 * s)
            Rectangle().fill(Ink.ink).frame(width: Ink.rule)
            content.padding(.horizontal, 10)
        }
        .padding(.vertical, 3.5 * s)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 欄 (題と、項目の並び)。
private struct ProfileSectionView: View {
    let section: ProfileSection
    let s: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(section.title)
                    .font(T.display(10.5 * s))
                    .tracking(T.jpTracking)
                Text(section.imprint)
                    .font(T.imprint(7))
                    .tracking(T.imprintTracking)
                    .foregroundStyle(Ink.sub)
            }
            .foregroundStyle(Ink.ink)
            VStack(alignment: .leading, spacing: 6 * s) {
                ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.label)
                            .font(T.jp(7.5 * s, .semibold))
                            .foregroundStyle(Ink.sub)
                        Text(entry.text)
                            .font(T.jp(10.5 * s))
                            .tracking(T.jpTracking)
                            .monospacedDigit()
                            .lineSpacing(2 * s)
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9 * s)
    }
}

/// 担当ブランド: 刷ってあるブランドの名前に、担当しているものだけ手描きの丸 (メインは二重丸、いくつでも)。
private struct ProfileBrandRange: View {
    let title: String
    let brands: [ProfileBrandCheck]
    let s: CGFloat

    var body: some View {
        // 名前が 2 段に折り返しても、欄の名前は 1 段目の高さに置く。
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(T.jp(7.5 * s, .semibold))
                .foregroundStyle(Ink.sub)
                .padding(.top, 5 * s)
                .fixedSize()
            // 丸 (二重丸の外側) が欄の名前に掛からないよう、名前の列から少し離す。
            FlowLayout(spacing: 17 * s, lineSpacing: 10 * s) {
                ForEach(brands, id: \.id) { brand in
                    Text(brand.label)
                        .font(T.jp(10 * s, brand.checked ? .semibold : .regular))
                        .tracking(T.jpTracking)
                        .foregroundStyle(brand.checked ? Ink.ink : Ink.sub)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .overlay {
                            ForEach(Array(brand.rings.enumerated()), id: \.offset) { i, ring in
                                ProfileHandCircle(ring: ring)
                                    .stroke(Ink.accent(brand.color),
                                            style: StrokeStyle(lineWidth: i == 0 ? 1.6 : 1.2, lineCap: .round,
                                                               lineJoin: .round))
                                    .padding(.horizontal, -3)
                                    .padding(.vertical, -4)
                            }
                        }
                }
            }
            .padding(.leading, 6 * s)
        }
        .padding(.vertical, 4 * s)
    }
}

/// 手描きの丸。少し傾け、横に伸び縮みさせ、書き終わりを行き過ぎて重ねる。揺らぎはコアが id から決める
/// (二重丸の 2 本目は大きさと中心もずらす)。
struct ProfileHandCircle: Shape {
    var ring: ProfileHandRing

    func path(in rect: CGRect) -> Path {
        let tilt = ring.tiltDegrees
        let cx = rect.midX + rect.width * ring.offsetX
        let cy = rect.midY + rect.height * ring.offsetY
        let rx = rect.width / 2 * ring.stretch * ring.scale
        let ry = rect.height / 2 * ring.scale
        let a0 = ring.startDegrees * .pi / 180
        let sweep = 2 * Double.pi + 0.5
        let steps = 72
        var path = Path()
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let a = a0 + sweep * t
            // 少しいびつに (3 つ山の揺らぎ) し、書き終わりは外へ逃がす。
            let r = 1 + 0.035 * sin(3 * a + a0) + 0.07 * t
            let p = CGPoint(x: cx + rx * r * cos(a), y: cy + ry * r * sin(a))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        let turn = CGAffineTransform(translationX: cx, y: cy)
            .rotated(by: tilt * .pi / 180)
            .translatedBy(x: -cx, y: -cy)
        return path.applying(turn)
    }
}

/// 押印欄の判子 (担当の名前を担当色の二重の丸に。少し傾けて押す)。プロフィール帳で担当色を使う唯一の所。
private struct ProfileSeal: View {
    let oshi: ProfileSheetOshi
    let diameter: CGFloat

    var body: some View {
        let color = Ink.accent(oshi.color ?? oshi.brandColor)
        ZStack {
            Circle().strokeBorder(color, lineWidth: 2)
            Circle().strokeBorder(color, lineWidth: 0.8).padding(3.5)
            sealText.foregroundStyle(color)
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(-12))
    }

    /// 2〜3 文字は縦書き、長い名前は横に縮めて入れる。
    @ViewBuilder private var sealText: some View {
        let chars = Array(oshi.shortName)
        if chars.count <= 3 {
            VStack(spacing: -diameter * 0.04) {
                ForEach(Array(chars.enumerated()), id: \.offset) { _, c in
                    Text(String(c))
                }
            }
            .font(.system(size: diameter * (chars.count == 3 ? 0.22 : 0.28), weight: .heavy, design: .serif))
        } else {
            Text(oshi.shortName)
                .font(.system(size: diameter * 0.24, weight: .heavy, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, diameter * 0.14)
        }
    }
}

/// 担当の並び (写真か判子 + 名前)。
private struct ProfileOshiList: View {
    let oshi: [ProfileSheetOshi]
    let s: CGFloat

    var body: some View {
        HStack(spacing: 12 * s) {
            ForEach(oshi) { idol in
                HStack(spacing: 5) {
                    ProfileOshiIcon(oshi: idol, size: 22 * s)
                    Text(idol.name)
                        .font(T.jp(10 * s))
                        .tracking(T.jpTracking)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
    }
}

/// 担当のアイコン (写真が無ければ判子)。枠を先に決めてから写真を重ねて丸く切る。
private struct ProfileOshiIcon: View {
    let oshi: ProfileSheetOshi
    let size: CGFloat

    var body: some View {
        let color = Ink.accent(oshi.color ?? oshi.brandColor)
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                if let image = oshi.image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Text(oshi.shortName)
                        .font(.system(size: size * 0.34, weight: .bold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, size * 0.1)
                }
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(color, lineWidth: 1.2))
    }
}

/// 証明写真の欄 (3:4)。枠を先に決めてから写真を重ねて切る。写真が無ければ「写真をはる位置」を刷っておく。
private struct ProfilePhotoBox: View {
    let image: UIImage?
    /// X のアイコンは欄 (3:4) の中に丸く置く (欄の幅いっぱいの丸)。
    var round = false
    let width: CGFloat

    var body: some View {
        Color.clear
            .frame(width: width, height: width * 4 / 3)
            .overlay {
                if let image, round {
                    Color.clear
                        .frame(width: width, height: width)
                        .overlay { Image(uiImage: image).resizable().scaledToFill() }
                        .clipShape(Circle())
                } else if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    VStack(spacing: 4) {
                        Text("写真をはる位置").font(T.jp(7.5, .semibold))
                        Text("縦 36〜40mm\n横 24〜30mm").font(T.jp(6.5)).monospacedDigit()
                    }
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Ink.sub)
                }
            }
            .clipped()
            .overlay(
                Rectangle().strokeBorder(Ink.ink,
                                         style: StrokeStyle(lineWidth: Ink.rule, dash: image == nil ? [3, 2] : []))
            )
    }
}

private struct ProfileQR: View {
    let image: UIImage
    let side: CGFloat

    var body: some View {
        Image(uiImage: image)
            .renderingMode(.template)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Ink.ink)
            .frame(width: side, height: side)
            .padding(4)
            .background(Ink.paper)
    }
}
