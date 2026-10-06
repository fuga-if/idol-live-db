import SwiftUI
import UIKit

// =============================================================================
// プロフィール帳 (SNS に貼る自己紹介の 1 枚絵)。P を職業に見立てた事務書類の様式を、ポップに崩す。
//
// - 履歴書 (既定) / 職務経歴書。欄・行・丸・詰め方はコア (`profileSheetLayout`) が決め、ここは描くだけ。
// - 紙は生成り、線は墨の太い罫。担当色は上の帯・表の頭の罫・押印欄の判子・職務経歴の印にだけ出す
//   (面を塗らない)。ブランドの丸はブランドの色の手描きの線。
// - 題はポップな書体 (Mochiy Pop One)、設問は印字 (ゴシック)、答えと名前は P名刺で選んだ書体。
// - アプリ名の帯 (`ShareCardFooter`) を下に置く。
//
// ImageRenderer で焼く固定のキャンバスなので、色は固定色、文字は固定 pt (docs/DESIGN_SYSTEM.md §13)。
// 画像は読み込み済みの UIImage だけを使う (ImageRenderer は読み込みを待たない)。
// =============================================================================

enum ProfileSheetInk {
    /// 生成りの紙。
    static let paper = Color(.sRGB, red: 0xFB / 255, green: 0xF7 / 255, blue: 0xEE / 255)
    static let ink = ShareInk.nearBlack
    static let sub = Color(.sRGB, red: 0x5A / 255, green: 0x57 / 255, blue: 0x55 / 255)
    /// 外枠の罫 (太い)。
    static let frame: CGFloat = 2.5
    /// 欄の中の罫。
    static let rule: CGFloat = 1

    /// QR の辺。詰め方で縮めない (焼いた画像を SNS が縮めても読めるように)。周りに紙の余白を足す。
    static let qrSide: CGFloat = 52

    /// 題の書体 (同梱のポップ体)。
    static var titleFont: String { cardNameFontInfo(font: .pop).postscriptName }

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
        let base: CGFloat = layout.size == .story ? 1.12 : 1
        return steps[start...].map { $0 * base }
    }

    static func accent(_ seed: String?) -> Color {
        seed == nil ? ink : ShareCardPalette(seed: seed).accent
    }
}

/// プロフィール帳 1 枚 (様式で出し分け)。
struct ProfileSheetCard: View {
    let layout: ProfileSheetLayout
    let materials: ProfileSheetMaterials

    var body: some View {
        let size = ProfileSheetInk.size(layout.size)
        let accent = ProfileSheetInk.accent(materials.seed)
        let scales = ProfileSheetInk.scales(layout)
        VStack(spacing: 0) {
            Rectangle().fill(accent).frame(height: 10)
            Rectangle().fill(ProfileSheetInk.ink).frame(height: 2)
            VStack(alignment: .leading, spacing: 0) {
                ProfileSheetHeading(layout: layout, s: scales[0])
                // コアの詰め方から始めて、収まらなければ小さい方へ (最後の段は下を切る)。
                ViewThatFits(in: .vertical) {
                    ForEach(scales, id: \.self) { s in
                        content(accent: accent, s: s)
                    }
                }
                .padding(.top, 10)
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()
                ShareCardFooter(ink: ProfileSheetInk.ink.opacity(0.7), rule: ProfileSheetInk.ink.opacity(0.3))
                    .padding(.top, 8)
            }
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .frame(width: size.width, height: size.height)
        .background(ProfileSheetInk.paper)
    }

    @ViewBuilder
    private func content(accent: Color, s: CGFloat) -> some View {
        switch layout.style {
        case .resume: ProfileResumeBody(layout: layout, materials: materials, accent: accent, s: s)
        case .career: ProfileCareerBody(layout: layout, materials: materials, accent: accent, s: s)
        }
    }
}

// MARK: - 頭 (題・日付)

private struct ProfileSheetHeading: View {
    let layout: ProfileSheetLayout
    let s: CGFloat

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(layout.title)
                .font(.imasCardNameFixed(ProfileSheetInk.titleFont, size: 32 * s))
                .tracking(6)
                .foregroundStyle(ProfileSheetInk.ink)
            Text(layout.imprint)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(ProfileSheetInk.sub)
            Spacer(minLength: 8)
            Text(layout.asOf)
                .font(.system(size: 10.5 * s, weight: .semibold))
                .foregroundStyle(ProfileSheetInk.ink)
        }
    }
}

// MARK: - 履歴書

private struct ProfileResumeBody: View {
    let layout: ProfileSheetLayout
    let materials: ProfileSheetMaterials
    let accent: Color
    let s: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            identity
            if !layout.brands.isEmpty {
                ProfileBrandRange(title: layout.brandsTitle, brands: layout.brands, s: s)
            }
            if !layout.history.isEmpty || !layout.licenses.isEmpty {
                ProfileBox {
                    VStack(spacing: 0) {
                        if !layout.history.isEmpty {
                            ProfileTableHead(title: "P歴（学歴・職歴）", accent: accent, s: s)
                            ForEach(Array(layout.history.enumerated()), id: \.offset) { i, row in
                                if i > 0 { ProfileRule() }
                                ProfileHistoryLine(row: row, s: s)
                            }
                        }
                        if !layout.licenses.isEmpty {
                            if !layout.history.isEmpty { ProfileRule(width: ProfileSheetInk.frame) }
                            ProfileTableHead(title: "免許・資格", accent: accent, s: s)
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
                ProfileBox { ProfileSectionView(section: section, font: materials.nameFont, s: s) }
            }
            let pair = layout.sections.filter { $0.slot != .motivation }
            if !pair.isEmpty {
                HStack(alignment: .top, spacing: 8 * s) {
                    ForEach(pair, id: \.title) { section in
                        ProfileBox {
                            ProfileSectionView(section: section, font: materials.nameFont, s: s)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 氏名・ふりがな・押印・P歴・担当・連絡先と証明写真。
    private var identity: some View {
        ProfileBox {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ProfileField(label: "ふりがな", s: s) {
                        Text(layout.furigana.isEmpty ? " " : layout.furigana)
                            .font(.system(size: 10.5 * s, weight: .medium))
                            .foregroundStyle(ProfileSheetInk.ink)
                            .lineLimit(1)
                    }
                    ProfileRule()
                    ProfileField(label: "氏名", s: s) {
                        HStack(spacing: 8) {
                            Text(layout.name)
                                .font(.imasCardNameFixed(materials.nameFont, size: 30 * s))
                                .foregroundStyle(ProfileSheetInk.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Spacer(minLength: 0)
                            if layout.showOshi, let oshi = materials.oshi.first {
                                ProfileSeal(oshi: oshi, diameter: 46 * s)
                            }
                        }
                        .padding(.vertical, 2 * s)
                    }
                    if let since = layout.sinceLabel {
                        ProfileRule()
                        ProfileField(label: "P歴", s: s) {
                            Text(since)
                                .font(.system(size: 10.5 * s, weight: .bold))
                                .foregroundStyle(ProfileSheetInk.ink)
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
                                Text(layout.contacts.joined(separator: "　"))
                                    .font(.system(size: 10.5 * s, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(ProfileSheetInk.ink)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                                Spacer(minLength: 0)
                                if layout.showQr, let qr = materials.qr {
                                    ProfileQR(image: qr, side: ProfileSheetInk.qrSide)
                                }
                            }
                        }
                    }
                }
                Rectangle().fill(ProfileSheetInk.ink).frame(width: ProfileSheetInk.frame)
                ProfilePhotoBox(image: layout.showPhoto ? materials.portrait : nil, width: 92 * s)
                    .padding(8 * s)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 職務経歴書

private struct ProfileCareerBody: View {
    let layout: ProfileSheetLayout
    let materials: ProfileSheetMaterials
    let accent: Color
    let s: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            identity
            ForEach(layout.sections.filter { $0.slot == .summary }, id: \.title) { section in
                ProfileHeadline(title: section.title, imprint: section.imprint, accent: accent, s: s)
                ProfileEntries(entries: section.entries, font: materials.nameFont, s: s)
            }
            if !layout.career.isEmpty {
                ProfileHeadline(title: "職務経歴", imprint: "CAREER", accent: accent, s: s)
                careerTable
            }
            if (layout.showOshi && !materials.oshi.isEmpty) || !layout.brands.isEmpty {
                ProfileHeadline(title: "担当・対応範囲", imprint: "IN CHARGE", accent: accent, s: s)
                if layout.showOshi && !materials.oshi.isEmpty {
                    ProfileOshiList(oshi: materials.oshi, s: s)
                }
                if !layout.brands.isEmpty {
                    ProfileBrandRange(title: layout.brandsTitle, brands: layout.brands, s: s)
                }
            }
            ForEach(layout.sections.filter { $0.slot != .summary }, id: \.title) { section in
                ProfileHeadline(title: section.title, imprint: section.imprint, accent: accent, s: s)
                ProfileEntries(entries: section.entries, font: materials.nameFont, s: s)
            }
            HStack {
                Spacer()
                Text("以上").font(.system(size: 11 * s, weight: .bold)).foregroundStyle(ProfileSheetInk.ink)
            }
        }
    }

    /// 右上に氏名と押印・証明写真 (職務経歴書の頭)。
    private var identity: some View {
        HStack(alignment: .bottom, spacing: 12 * s) {
            VStack(alignment: .leading, spacing: 4 * s) {
                if let since = layout.sinceLabel {
                    Text(since)
                        .font(.system(size: 10.5 * s, weight: .bold))
                        .foregroundStyle(ProfileSheetInk.ink)
                }
                if !layout.contacts.isEmpty {
                    Text(layout.contacts.joined(separator: "　"))
                        .font(.system(size: 10 * s, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ProfileSheetInk.sub)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                if !layout.furigana.isEmpty {
                    Text(layout.furigana)
                        .font(.system(size: 9.5 * s, weight: .medium))
                        .foregroundStyle(ProfileSheetInk.sub)
                }
                HStack(alignment: .center, spacing: 6) {
                    Text("氏名").font(.system(size: 9 * s, weight: .bold)).foregroundStyle(ProfileSheetInk.sub)
                    Text(layout.name)
                        .font(.imasCardNameFixed(materials.nameFont, size: 26 * s))
                        .foregroundStyle(ProfileSheetInk.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if layout.showOshi, let oshi = materials.oshi.first {
                        ProfileSeal(oshi: oshi, diameter: 40 * s)
                    }
                }
                Rectangle().fill(ProfileSheetInk.ink).frame(height: ProfileSheetInk.frame)
            }
            .fixedSize()
            if layout.showQr, let qr = materials.qr {
                ProfileQR(image: qr, side: ProfileSheetInk.qrSide)
            }
            if layout.showPhoto, let portrait = materials.portrait {
                ProfilePhotoBox(image: portrait, width: 60 * s)
            }
        }
    }

    private var careerTable: some View {
        ProfileBox {
            VStack(spacing: 0) {
                ForEach(Array(layout.career.enumerated()), id: \.offset) { i, year in
                    if i > 0 { ProfileRule(width: ProfileSheetInk.frame) }
                    HStack {
                        Text(year.year).font(.system(size: 12 * s, weight: .heavy))
                        Spacer()
                        Text(year.countLabel).font(.system(size: 10 * s, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(ProfileSheetInk.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3 * s)
                    .overlay(alignment: .bottom) { Rectangle().fill(accent).frame(height: 2.5) }
                    ForEach(Array(year.rows.enumerated()), id: \.offset) { j, row in
                        if j > 0 { ProfileRule() }
                        ProfileCareerLine(row: row, accent: accent, s: s)
                    }
                }
                if layout.careerMore > 0 {
                    ProfileRule()
                    HStack {
                        Spacer()
                        Text("ほか \(layout.careerMore) 公演")
                            .font(.system(size: 9.5 * s, weight: .semibold))
                            .foregroundStyle(ProfileSheetInk.sub)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3 * s)
                }
            }
        }
    }
}

private struct ProfileCareerLine: View {
    let row: ProfileCareerRow
    let accent: Color
    let s: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.date)
                .font(.system(size: 10 * s, weight: .bold, design: .monospaced))
                .frame(width: 40 * s, alignment: .leading)
            (Text(row.title).font(.system(size: 10 * s, weight: .bold))
                + Text(row.venue.map { "　\($0)" } ?? "")
                .font(.system(size: 8.5 * s, weight: .medium))
                .foregroundColor(ProfileSheetInk.sub))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if row.planned {
                Text("予定")
                    .font(.system(size: 9 * s, weight: .heavy))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(Rectangle().strokeBorder(accent, lineWidth: 1.5))
                    .rotationEffect(.degrees(-6))
            } else if let brand = row.brand {
                Text(brand)
                    .font(.system(size: 9 * s, weight: .bold))
                    .foregroundStyle(ProfileSheetInk.sub)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(ProfileSheetInk.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 3 * s)
    }
}

// MARK: - 部品 (プロフィール帳の中だけ)

/// 太い墨の罫で囲む欄。
private struct ProfileBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Rectangle().strokeBorder(ProfileSheetInk.ink, lineWidth: ProfileSheetInk.frame))
    }
}

private struct ProfileRule: View {
    var width: CGFloat = ProfileSheetInk.rule

    var body: some View {
        Rectangle().fill(ProfileSheetInk.ink).frame(height: width)
    }
}

/// 項目名 (印字) と中身の 1 段。
private struct ProfileField<Content: View>: View {
    let label: String
    let s: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.system(size: 8.5 * s, weight: .bold))
                .foregroundStyle(ProfileSheetInk.sub)
                .frame(width: 40 * s, alignment: .leading)
            content
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 表の頭 (年・月・内容)。下の罫だけ担当色で太く。
private struct ProfileTableHead: View {
    let title: String
    let accent: Color
    let s: CGFloat

    var body: some View {
        ProfileHistoryColumns(year: "年", month: "月", s: s) {
            Text(title).frame(maxWidth: .infinity)
        }
        .font(.system(size: 9 * s, weight: .heavy))
        .foregroundStyle(ProfileSheetInk.ink)
        .overlay(alignment: .bottom) { Rectangle().fill(accent).frame(height: 2.5) }
    }
}

private struct ProfileHistoryLine: View {
    let row: ProfileHistoryRow
    let s: CGFloat

    var body: some View {
        ProfileHistoryColumns(year: row.year, month: row.month, s: s) {
            Text(row.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: row.kind == .closing ? .trailing : .leading)
        }
        .font(.system(size: 10 * s, weight: row.kind == .closing ? .bold : .medium))
        .foregroundStyle(ProfileSheetInk.ink)
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
            Text(year).monospacedDigit().frame(width: 40 * s)
            Rectangle().fill(ProfileSheetInk.ink).frame(width: ProfileSheetInk.rule)
            Text(month).monospacedDigit().frame(width: 26 * s)
            Rectangle().fill(ProfileSheetInk.ink).frame(width: ProfileSheetInk.rule)
            content.padding(.horizontal, 8)
        }
        .padding(.vertical, 2.5 * s)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 欄 (題と、質問・答えの並び)。
private struct ProfileSectionView: View {
    let section: ProfileSection
    let font: String
    let s: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(section.title).font(.system(size: 10.5 * s, weight: .heavy))
                Text(section.imprint)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(ProfileSheetInk.sub)
            }
            .foregroundStyle(ProfileSheetInk.ink)
            ProfileEntries(entries: section.entries, font: font, s: s)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6 * s)
    }
}

/// 質問 (印字の小さな字) と答え (P名刺の書体)。自動の項目は印字で。
private struct ProfileEntries: View {
    let entries: [ProfileEntry]
    let font: String
    let s: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 1) {
                    if !entry.label.isEmpty {
                        Text(entry.label)
                            .font(.system(size: 8.5 * s, weight: .bold))
                            .foregroundStyle(ProfileSheetInk.sub)
                    }
                    Text(entry.text)
                        .font(entry.isAuto
                              ? .system(size: 11 * s, weight: .semibold)
                              : .imasCardNameFixed(font, size: 12.5 * s))
                        .foregroundStyle(ProfileSheetInk.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// 職務経歴書の見出し (担当色の四角 + 題 + 英字の印字)。
private struct ProfileHeadline: View {
    let title: String
    let imprint: String
    let accent: Color
    let s: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Rectangle().fill(accent).frame(width: 9 * s, height: 9 * s)
            Text(title).font(.system(size: 12 * s, weight: .heavy)).foregroundStyle(ProfileSheetInk.ink)
            Text(imprint)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(ProfileSheetInk.sub)
            Rectangle().fill(ProfileSheetInk.ink).frame(height: ProfileSheetInk.rule)
        }
        .padding(.top, 2 * s)
    }
}

/// 対応範囲: 刷ってあるブランドの名前に、対応しているものだけ手描きの丸。
private struct ProfileBrandRange: View {
    let title: String
    let brands: [ProfileBrandCheck]
    let s: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.system(size: 9 * s, weight: .heavy))
                .foregroundStyle(ProfileSheetInk.ink)
            FlowLayout(spacing: 16 * s, lineSpacing: 8 * s) {
                ForEach(brands, id: \.id) { brand in
                    Text(brand.label)
                        .font(.system(size: 10.5 * s, weight: .bold))
                        .foregroundStyle(brand.checked ? ProfileSheetInk.ink : ProfileSheetInk.sub)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .overlay {
                            if brand.checked {
                                ProfileHandCircle(tilt: brand.tiltDegrees, stretch: brand.stretch,
                                                  start: brand.startDegrees)
                                    .stroke(ProfileSheetInk.accent(brand.color),
                                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                    .padding(.horizontal, -3)
                                    .padding(.vertical, -4)
                            }
                        }
                }
            }
        }
        .padding(.vertical, 2 * s)
    }
}

/// 手描きの丸。少し傾け、横に伸び縮みさせ、書き終わりを行き過ぎて重ねる。揺らぎはコアが id から決める。
struct ProfileHandCircle: Shape {
    var tilt: Double
    var stretch: Double
    var start: Double

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width / 2 * stretch
        let ry = rect.height / 2
        let a0 = start * .pi / 180
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

/// 押印欄の判子 (担当の名前を担当色の二重の丸に。少し傾けて押す)。
private struct ProfileSeal: View {
    let oshi: ProfileSheetOshi
    let diameter: CGFloat

    var body: some View {
        let color = ProfileSheetInk.accent(oshi.color ?? oshi.brandColor)
        ZStack {
            Circle().strokeBorder(color, lineWidth: 2.5)
            Circle().strokeBorder(color, lineWidth: 1).padding(4)
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
        HStack(spacing: 10 * s) {
            ForEach(oshi) { idol in
                HStack(spacing: 5) {
                    ProfileOshiIcon(oshi: idol, size: 24 * s)
                    Text(idol.name)
                        .font(.system(size: 10.5 * s, weight: .bold))
                        .foregroundStyle(ProfileSheetInk.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
    }
}

/// 担当のアイコン (写真が無ければ判子)。
private struct ProfileOshiIcon: View {
    let oshi: ProfileSheetOshi
    let size: CGFloat

    var body: some View {
        let color = ProfileSheetInk.accent(oshi.color ?? oshi.brandColor)
        ZStack {
            if let image = oshi.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ProfileSheetInk.paper
                Text(oshi.shortName)
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, size * 0.1)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(color, lineWidth: 1.5))
    }
}

/// 証明写真の欄。写真が無ければ履歴書の「写真をはる位置」を刷っておく。
private struct ProfilePhotoBox: View {
    let image: UIImage?
    let width: CGFloat

    var body: some View {
        let height = width * 4 / 3
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                VStack(spacing: 4) {
                    Text("写真をはる位置").font(.system(size: 8, weight: .bold))
                    Text("縦 36〜40mm\n横 24〜30mm").font(.system(size: 7, weight: .medium))
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(ProfileSheetInk.sub)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay(
            Rectangle().strokeBorder(ProfileSheetInk.ink,
                                     style: StrokeStyle(lineWidth: 1, dash: image == nil ? [3, 2] : []))
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
            .foregroundStyle(ProfileSheetInk.ink)
            .frame(width: side, height: side)
            .padding(4)
            .background(ProfileSheetInk.paper)
    }
}
