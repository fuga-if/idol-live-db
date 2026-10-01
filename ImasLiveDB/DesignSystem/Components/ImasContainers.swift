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
    var seeAll: (() -> Void)? = nil
    /// seeAll の文言。行き先が「一覧の全件」でないとき (例: ほかのお題) に替える。
    var seeAllTitle: String = "すべて見る"
    var style: Style = .large

    /// 旧い呼び方 (`tight: true` = 小) を残す。
    init(title: String, count: String? = nil, seeAll: (() -> Void)? = nil, tight: Bool = false,
         seeAllTitle: String = "すべて見る") {
        self.title = title
        self.count = count
        self.seeAll = seeAll
        self.seeAllTitle = seeAllTitle
        self.style = tight ? .small : .large
    }

    init(_ title: String, count: String? = nil, imprint: String? = nil, style: Style = .large,
         seeAllTitle: String = "すべて見る", seeAll: (() -> Void)? = nil) {
        self.title = title
        self.count = count
        self.imprint = imprint
        self.seeAll = seeAll
        self.seeAllTitle = seeAllTitle
        self.style = style
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.gap) {
            Text(title)
                .imasText(style == .large ? .sectionTitle : .sectionLabel)
                .lineLimit(2)
            if let count {
                Text(count)
                    .font(style == .large ? ImasNumeralSize.small.font : .imasCaption)
                    .foregroundStyle(DS.ink3)
            }
            if let imprint, style == .large {
                Text(imprint).imasText(.imprint).foregroundStyle(DS.ink3).lineLimit(1)
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
    @ViewBuilder var content: Content

    init(_ title: String? = nil, count: String? = nil, imprint: String? = nil,
         style: ImasSectionHeader.Style = .large, footer: String? = nil, seeAll: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.imprint = imprint
        self.style = style
        self.footer = footer
        self.seeAll = seeAll
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                ImasSectionHeader(title, count: count, imprint: imprint, style: style, seeAll: seeAll)
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
        /// 面に入れる (紙面なら灰の面、灰の地なら白い面)。入口・設定・カードの中の短い一覧。
        case panel
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
        case .panel:
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
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

/// 旧名。`ImasCardList` に置き換えていく。
typealias ImasListContainer = ImasCardList

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
struct ImasRowDivider: View {
    var inset: CGFloat = 0
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        Rectangle()
            .fill(DS.sep)
            .frame(height: 1 / displayScale)
            .padding(.leading, inset)
            .accessibilityHidden(true)
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
