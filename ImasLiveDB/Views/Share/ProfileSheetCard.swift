import SwiftUI
import UIKit

// =============================================================================
// P名刺の画像 (SNS に貼る自己紹介の 1 枚絵)。P を職業に見立てた **P履歴書** の様式。
//
// - 欄・行・丸・詰め方はコア (`profileSheetLayout`) が決め、ここは描くだけ。
// - 紙は生成り、線は墨。罫の太さは 2 段 (外枠と欄の中)。色は担当のアイコンの縁と、ブランドの丸の手描きの線
//   (中身そのものの色) だけ (面を塗らない・帯を引かない)。英字の印字と押印欄の判子は置かない
//   (2026-10 ユーザー「RESUME みたいなサブタイトルいらない。あと謎のハンコも」)。
// - 字面は事務書類の端正さに寄せる (2026-10 ユーザー「文字の感じが若干垢抜けてない」)。題・名前・欄の題は明朝、
//   本文はゴシック (`ProfileSheetType`)。太さは 2 段 (本文 = regular・見出し = semibold)、
//   和文はかなを詰めて (palt) 字間を少し詰める。数字は等幅。題は大きく本文は控えめにして、大きさの比をはっきり取る。
// - 中身はすべてアプリの記録と P名刺から (自分で書く欄は無い)。アプリ名の帯 (`ShareCardFooter`) を下に置く。
//
// 組み: 頭 (題・日付) / 氏名・P歴・連絡先と証明写真・担当 (ブランドごとの行) / 担当ブランド / P歴の表 /
//       好きな曲 / 思い出の公演 / 次の現場と記録 (左右に) / ひとこと。
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

/// P名刺の画像の書体。題・名前・欄の題だけ明朝 (ヒラギノ明朝 W6)、ほかはゴシック (ヒラギノ角ゴ)、
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

/// P名刺の画像 1 枚。
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
                    .tracking(6)
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

// MARK: - P履歴書

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
            if !layout.history.isEmpty {
                ProfileBox {
                    VStack(spacing: 0) {
                        ProfileTableHead(title: layout.historyTitle, s: s)
                        ForEach(Array(layout.history.enumerated()), id: \.offset) { i, row in
                            if i > 0 { ProfileRule() }
                            ProfileHistoryLine(row: row, s: s)
                        }
                    }
                }
            }
            // 好きな曲・思い出の公演・ひとことは横いっぱい、次の現場と記録は左右に並べる。
            ForEach(full(.songs) + full(.memories), id: \.title) { section in
                ProfileBox { ProfileSectionView(section: section, s: s) }
            }
            let pair = layout.sections.filter { $0.slot == .nextShow || $0.slot == .records }
            if !pair.isEmpty {
                HStack(alignment: .top, spacing: 10 * s) {
                    ForEach(pair, id: \.title) { section in
                        ProfileBox {
                            ProfileSectionView(section: section, s: s)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                        // 記録は数が短いので幅を取りすぎない。
                        .frame(maxWidth: section.slot == .records && pair.count == 2 ? 150 * s : .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(full(.message), id: \.title) { section in
                ProfileBox { ProfileSectionView(section: section, s: s) }
            }
        }
    }

    private func full(_ slot: ProfileSlot) -> [ProfileSection] {
        layout.sections.filter { $0.slot == slot }
    }

    /// 氏名・P歴・連絡先と証明写真、その下に担当 (ブランドごとの行)。
    private var identity: some View {
        ProfileBox {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ProfileField(label: "氏名", s: s) {
                            Text(layout.name)
                                .font(T.display(24 * s))
                                .tracking(T.jpTracking)
                                .foregroundStyle(Ink.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                        Spacer(minLength: 0)
                    }
                    Rectangle().fill(Ink.ink).frame(width: Ink.rule)
                    ProfilePhotoBox(image: layout.showPhoto ? materials.portrait : nil,
                                    round: materials.portraitRound, width: 78 * s)
                        .padding(9 * s)
                }
                .fixedSize(horizontal: false, vertical: true)
                if !layout.oshiGroups.isEmpty {
                    ProfileRule()
                    ProfileField(label: "担当", s: s) {
                        ProfileOshiRows(groups: layout.oshiGroups, oshi: materials.oshi, s: s)
                    }
                }
            }
        }
    }
}

// MARK: - 部品 (P名刺の画像の中だけ)

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

/// 欄 (題と中身)。中身の組みは欄ごと: 好きな曲は「」で流し組み、思い出の公演・次の現場は日付と公演の行、
/// 記録は項目と数の行、ひとことは本文だけ。
private struct ProfileSectionView: View {
    let section: ProfileSection
    let s: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            Text(section.title)
                .font(T.display(10.5 * s))
                .tracking(T.jpTracking)
                .foregroundStyle(Ink.ink)
            switch section.slot {
            case .songs: songs
            case .memories, .nextShow: shows
            case .records: records
            case .message: message
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9 * s)
    }

    private var songs: some View {
        FlowLayout(spacing: 2 * s, lineSpacing: 4 * s) {
            ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                Text("「\(entry.text)」")
                    .font(T.jp(10.5 * s))
                    .tracking(T.jpTracking)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
            }
        }
    }

    /// 日付 | 公演 (会場)。日付は列を揃える。
    private var shows: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .firstTextBaseline, spacing: 8 * s) {
                    Text(entry.label)
                        .font(T.jp(8.5 * s))
                        .monospacedDigit()
                        .foregroundStyle(Ink.sub)
                        .frame(width: 70 * s, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.text)
                            .font(T.jp(10 * s))
                            .tracking(T.jpTracking)
                            .foregroundStyle(Ink.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(T.jp(8 * s))
                                .foregroundStyle(Ink.sub)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var records: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .firstTextBaseline, spacing: 8 * s) {
                    Text(entry.label)
                        .font(T.jp(8.5 * s))
                        .foregroundStyle(Ink.sub)
                    Spacer(minLength: 4)
                    Text(entry.text)
                        .font(T.num(11 * s, .semibold))
                        .foregroundStyle(Ink.ink)
                }
            }
        }
    }

    private var message: some View {
        Text(section.entries.first?.text ?? "")
            .font(T.jp(10.5 * s))
            .tracking(T.jpTracking)
            .lineSpacing(2 * s)
            .foregroundStyle(Ink.ink)
            .fixedSize(horizontal: false, vertical: true)
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

/// 担当の行 (ブランドごとに 1 行、入りきらなければ折り返す)。ブランドが 2 つ以上なら行の頭にブランドの名前
/// (コアの `ProfileOshiGroup.brandLabel`。1 つなら空)。
private struct ProfileOshiRows: View {
    let groups: [ProfileOshiGroup]
    let oshi: [ProfileSheetOshi]
    let s: CGFloat

    var body: some View {
        let byId = Dictionary(oshi.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let labeled = groups.contains { !$0.brandLabel.isEmpty }
        VStack(alignment: .leading, spacing: 5 * s) {
            ForEach(groups, id: \.brandId) { group in
                HStack(alignment: .top, spacing: 8 * s) {
                    if labeled {
                        Text(group.brandLabel)
                            .font(T.jp(7.5 * s, .semibold))
                            .foregroundStyle(Ink.sub)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: 44 * s, alignment: .leading)
                            .padding(.top, 5 * s)
                    }
                    FlowLayout(spacing: 10 * s, lineSpacing: 4 * s) {
                        ForEach(group.idolIds.compactMap { byId[$0] }) { idol in
                            HStack(spacing: 4) {
                                ProfileOshiIcon(oshi: idol, size: 20 * s)
                                Text(idol.name)
                                    .font(T.jp(9.5 * s))
                                    .tracking(T.jpTracking)
                                    .foregroundStyle(Ink.ink)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 2 * s)
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
