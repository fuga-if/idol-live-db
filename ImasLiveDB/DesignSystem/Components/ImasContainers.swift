import SwiftUI

// =============================================================================
// 区画と面 (docs/DESIGN_SYSTEM.md §3・§4・§6.1・§6.2)
//
// ImasSection        見出し + 中身 + 補足文。ScrollView の画面で縦に並べる単位。
// ImasSectionHeader  見出し。大 (詳細・ハブ) と小 (一覧・設定・フォーム・カードの中)。
// ImasCard           行でない中身を 1 枚の面にまとめる。
// ImasCardList       行を並べる。紙面にそのまま並べる (plain) か、面に入れる (panel)。
//                    区切り線は行が持つ。
// ImasNote           補足文。囲まない。
// ImasRowDivider     行の間の線。行の部品が使う (画面では書かない)。
// =============================================================================

// MARK: - 見出し

struct ImasSectionHeader: View {
    enum Style {
        /// 20pt 太字・墨。詳細とハブの区画。
        case large
        /// 13pt 中太・灰。一覧・設定・フォームの区画と、カードの中の小分け。
        case small
    }

    let title: String
    var count: String? = nil
    /// 見出しの横の英字の印字 (「PLAY」「42 SONGS」)。大きい見出しにだけ付ける。
    var imprint: String? = nil
    /// 見出しの前のペンライトの色の手がかり (ブランドごと・アイドルごとの区切り)。
    var seed: String? = nil
    var brand: String? = nil
    var seeAll: (() -> Void)? = nil
    /// seeAll の文言。行き先が「一覧の全件」でないとき (例: ほかのお題) に替える。
    var seeAllTitle: String = "すべて見る"
    /// 見出し右の文脈アクション (「＋ タグ」「▶ 動画」)。`seeAll` (矢印付き「すべて見る」) とは
    /// 見え方が違う (記号 + 可変の文言、矢印なし)。別の画面へ移るのではなくその場で何かを
    /// 始める操作のときに使う。`seeAll` と同時には出さない。
    var actionTitle: String? = nil
    var actionSystemImage: String? = nil
    var onAction: (() -> Void)? = nil
    var style: Style = .large
    /// 見出しの行数。ユーザーが書いた題 (お題のタイトルなど) を区画見出しに流用するときは
    /// 切りたくないので増やす (既定は他の区画見出しと同じ 2 行)。
    var titleLineLimit: Int = 2

    /// 旧い呼び方 (`tight: true` = 小) を残す。
    init(title: String, count: String? = nil, seeAll: (() -> Void)? = nil, tight: Bool = false,
         seeAllTitle: String = "すべて見る") {
        self.title = title
        self.count = count
        self.seeAll = seeAll
        self.seeAllTitle = seeAllTitle
        self.style = tight ? .small : .large
    }

    init(_ title: String, count: String? = nil, imprint: String? = nil, seed: String? = nil, brand: String? = nil,
         style: Style = .large, titleLineLimit: Int = 2, seeAllTitle: String = "すべて見る", seeAll: (() -> Void)? = nil,
         actionTitle: String? = nil, actionSystemImage: String? = nil, onAction: (() -> Void)? = nil) {
        self.title = title
        self.count = count
        self.imprint = imprint
        self.seed = seed
        self.brand = brand
        self.seeAll = seeAll
        self.seeAllTitle = seeAllTitle
        self.actionTitle = actionTitle
        self.actionSystemImage = actionSystemImage
        self.onAction = onAction
        self.style = style
        self.titleLineLimit = titleLineLimit
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.imasTheme) private var envTheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.gap) {
            if seed != nil || brand != nil {
                ImasPenlight(color: ImasTheme.derive(seed: seed, brand: brand, scheme: scheme).penlight,
                             size: style == .large ? .regular : .small)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
            }
            Text(title)
                .imasText(style == .large ? .sectionTitle : .sectionLabel)
                .lineLimit(titleLineLimit)
            if let count {
                Text(count)
                    .font(style == .large ? ImasNumeralSize.small.font : .imasCaption)
                    .foregroundStyle(DS.ink3)
            }
            if let imprint, style == .large {
                Text(imprint).imasText(.imprint, color: DS.ink3).lineLimit(1)
            }
            Spacer(minLength: DS.Space.gapLoose)
            if let seeAll {
                Button(action: seeAll) {
                    HStack(spacing: 2) {
                        Text(seeAllTitle)
                        Image(systemName: "chevron.right").font(.imasScaled(11, weight: .semibold))
                    }
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink2)
                }
                .buttonStyle(.plain)
            } else if let actionTitle, let onAction {
                let t = ImasChipColors.theme(seed: seed, brand: brand, color: nil, env: envTheme, scheme: scheme)
                Button(action: onAction) {
                    HStack(spacing: DS.Space.gapTight) {
                        if let actionSystemImage {
                            Image(systemName: actionSystemImage).font(.imasScaled(13, weight: .semibold))
                        }
                        Text(actionTitle).font(.imasScaled(14, weight: .semibold))
                    }
                    .foregroundStyle(t.isNeutral ? DS.ink : t.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 区画

/// 見出し + 中身 + 補足文。区画どうしの間隔は並べる側 (`ImasPage`) が持つ。
struct ImasSection<Content: View>: View {
    var title: String? = nil
    var count: String? = nil
    var imprint: String? = nil
    var style: ImasSectionHeader.Style = .large
    var footer: String? = nil
    var seeAll: (() -> Void)? = nil
    /// 見出し右の文脈アクション (`seeAll` とは同時に出さない)。
    var actionTitle: String? = nil
    var actionSystemImage: String? = nil
    var onAction: (() -> Void)? = nil
    @ViewBuilder var content: Content

    init(_ title: String? = nil, count: String? = nil, imprint: String? = nil,
         style: ImasSectionHeader.Style = .large, footer: String? = nil, seeAll: (() -> Void)? = nil,
         actionTitle: String? = nil, actionSystemImage: String? = nil, onAction: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.imprint = imprint
        self.style = style
        self.footer = footer
        self.seeAll = seeAll
        self.actionTitle = actionTitle
        self.actionSystemImage = actionSystemImage
        self.onAction = onAction
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                ImasSectionHeader(title, count: count, imprint: imprint, style: style, seeAll: seeAll,
                                  actionTitle: actionTitle, actionSystemImage: actionSystemImage, onAction: onAction)
                    .padding(.horizontal, style == .small ? DS.Space.rowH : 0)
                    .padding(.bottom, DS.Space.header)
            }
            content
            if let footer {
                ImasNote(footer)
                    .padding(.horizontal, DS.Space.rowH)
                    .padding(.top, DS.Space.note)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 区画を縦に並べる画面の本体 (詳細・ハブ・ダッシュボード)。地・左右の余白・区画どうしの
/// 間隔・広い画面での本文幅を持つ。中の部品には「紙面の上」(`.paper`) を伝える。
struct ImasPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.section) {
                content
            }
            .padding(.horizontal, DS.Space.screen)
            .padding(.top, DS.Space.gapLoose)
            .padding(.bottom, DS.Space.section)
        }
        .background(DS.paper)
        .environment(\.imasBackdrop, .paper)
        .readableContentMargins()
    }
}

// MARK: - 面

/// 行でない中身を 1 枚の面にまとめる。
struct ImasCard<Content: View>: View {
    enum Style {
        /// 地の上の面 (紙面なら灰、灰の地なら白)。
        case standard
        /// 旧名。色の地は敷かなくなったので `standard` と同じ。
        case tinted
        /// カードの中の囲み (面の中の、地と同じ色の窓)。
        case inset
    }

    var style: Style = .standard
    var padding: CGFloat = DS.Space.card
    @ViewBuilder var content: Content

    @Environment(\.imasBackdrop) private var backdrop

    var body: some View {
        if style == .inset {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(padding)
                .background(DS.surface2, in: RoundedRectangle(cornerRadius: DS.rInner, style: .continuous))
        } else {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(padding)
                .background(DS.surface(on: backdrop), in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
                .imasSurfaceEdge(cornerRadius: DS.rCard)
        }
    }
}

/// 行を並べる。中の行は左揃え・幅いっぱい。区切り線は行の部品が持つ。
struct ImasCardList<Content: View>: View {
    enum Style {
        /// 面に入れる。入口・設定・カードの中の短い一覧。
        case panel
        /// 紙に入れ、行の間を切り取り線で区切る (セトリ・申込書のような「刷られた紙」)。
        case sheet
        /// 紙面にそのまま並べる。行は画面の端から端まで、線は本文の頭から右の端まで。
        /// 曲・ライブ・アイドルなど「もの」の一覧 (`ImasPage` の中でだけ使う)。
        case plain
    }

    var style: Style = .panel
    @ViewBuilder var content: Content

    @Environment(\.imasBackdrop) private var backdrop

    init(style: Style = .panel, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        switch style {
        case .panel, .sheet:
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.imasDividerStyle, style == .sheet ? .perforated : .hairline)
                .background(DS.surface(on: backdrop), in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
                .imasSurfaceEdge(cornerRadius: DS.rCard)
        case .plain:
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, -DS.Space.screen)
        }
    }
}


// MARK: - 補足文

/// 区画の下の補足文。灰色の小さい文で、囲まない。
/// 読まないと困ること (始められない・失敗した) は `ImasNotice` にする。
struct ImasNote: View {
    let text: String
    var systemImage: String? = nil

    init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).font(.imasScaled(12, weight: .semibold))
            }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .imasText(.note)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 区切り線

/// 行の間の線。色は `DS.sep`、左は行の本文の頭に揃える (`inset`)。
/// `ImasCardList(style: .sheet)` の中では切り取り線 (点線) になる。
struct ImasRowDivider: View {
    var inset: CGFloat = 0
    @Environment(\.displayScale) private var displayScale
    @Environment(\.imasDividerStyle) private var style

    var body: some View {
        Group {
            switch style {
            case .hairline:
                Rectangle()
                    .fill(DS.sep)
                    .frame(height: 1 / displayScale)
            case .perforated:
                ImasPerforation(color: DS.perforation)
            }
        }
        .padding(.leading, inset)
        .accessibilityHidden(true)
    }
}

/// 行の区切りの線の種類。
enum ImasDividerStyle {
    /// 細い線 (一覧)。
    case hairline
    /// 切り取り線 (セトリの紙・申込書)。
    case perforated
}

private struct ImasDividerStyleKey: EnvironmentKey {
    static let defaultValue: ImasDividerStyle = .hairline
}

extension EnvironmentValues {
    var imasDividerStyle: ImasDividerStyle {
        get { self[ImasDividerStyleKey.self] }
        set { self[ImasDividerStyleKey.self] = newValue }
    }
}

// MARK: - 年・月の見出し

/// 年・月で区切る見出し (ライブ一覧・収支・予定)。細長い大きな数字と、横に英字の印字。
/// 終わった区切りは薄くする。
struct ImasDateHeader: View {
    /// 大きい数字 (「2026」「11」)。
    let big: String
    /// 横の印字 (「NOV 2026 · 4 公演」)。
    var imprint: String? = nil
    var isPast: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.gapLoose) {
            Text(big)
                .font(ImasNumeralSize.date.font)
                .foregroundStyle(isPast ? DS.ink3 : DS.ink)
            if let imprint {
                Text(imprint).imasText(.imprint, color: DS.ink3).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, DS.Space.gapLoose)
        .padding(.bottom, DS.Space.gapTight)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 面の縁

extension View {
    /// 面の縁。ライトはロビーの紙が浮くような薄い影、ダークは客席の暗がりで面が溶けないよう細い線。
    func imasSurfaceEdge(cornerRadius: CGFloat) -> some View {
        modifier(ImasSurfaceEdge(cornerRadius: cornerRadius))
    }
}

private struct ImasSurfaceEdge: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if scheme == .dark {
            content.overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DS.sep, lineWidth: 1)
            )
        } else {
            content
                .shadow(color: DS.ink.opacity(0.04), radius: 0, y: 1)
                .shadow(color: DS.ink.opacity(0.06), radius: 9, y: 6)
        }
    }
}
