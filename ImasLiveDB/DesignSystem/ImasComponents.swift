import SwiftUI

// =============================================================================
// 移行中の部品 (docs/DESIGN_SYSTEM.md)
//
// 新しい部品は DesignSystem/Components/ に置く。ここには旧い呼び名のまま使われている部品を、
// 新しい部品の上に組み直して残している。画面を移したら消す。
//
//   ImasLeadRow     → ImasRow(leading: .bar) / ImasEventRow
//   ImasMetricBadge → ImasMetric
//   ImasTagChip     → ImasBadge
//   ImasLabeledRow  → ImasValueRow
// =============================================================================

// MARK: - リードバー付きの一覧行 (→ ImasRow)

/// `ImasLeadBar` + 題 + 副題 + 末尾。中身は `ImasRow(leading: .bar)` と同じ。
struct ImasLeadRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var seed: String? = nil
    var brand: String? = nil
    var rainbow: Bool = false
    var titleLineLimit: Int = 2
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ImasRow(
            title: title,
            subtitle: subtitle,
            leading: .bar(seed: seed, brand: brand, rainbow: rainbow),
            trailing: .custom(AnyView(trailing())),
            titleLineLimit: titleLineLimit
        )
    }
}

extension ImasLeadRow where Trailing == ImasRowChevron {
    init(title: String, subtitle: String? = nil, seed: String? = nil, brand: String? = nil,
         rainbow: Bool = false, titleLineLimit: Int = 2) {
        self.init(title: title, subtitle: subtitle, seed: seed, brand: brand, rainbow: rainbow,
                  titleLineLimit: titleLineLimit, trailing: { ImasRowChevron() })
    }
}

// MARK: - 数字 (→ ImasMetric)

struct ImasMetricBadge: View {
    let value: String
    var unit: String = ""
    var emphasized: Bool = true
    var seed: String? = nil

    var body: some View {
        ImasMetric(value: value, unit: unit, size: .medium, emphasized: emphasized)
            .imasTheme(seed: seed)
    }
}

// MARK: - 順位の行

/// 順位 + ジャケ/画像 + 題 + 数。1〜3 位は墨、4 位から灰。
struct ImasRankingRow: View {
    enum Lead { case artwork(title: String, imageURL: URL?), avatar(label: String, imageURL: URL?) }
    let rank: Int
    let lead: Lead
    let title: String
    var sub: String? = nil
    let metric: String
    var unit: String = "回"
    var seed: String? = nil
    var brand: String? = nil

    var body: some View {
        HStack(spacing: DS.Space.rowGap) {
            ImasRankNumber(rank: rank)
            switch lead {
            case let .artwork(title, url): ImasArtwork(title: title, seed: seed, brand: brand, size: 44, imageURL: url)
            case let .avatar(label, url):
                ImasAvatar(label: label, seed: seed, brand: brand, size: 40, imageURL: url, reservesPickRing: false)
            }
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                Text(title).imasText(.rowTitle).lineLimit(1)
                if let sub { Text(sub).imasText(.rowSubtitle).lineLimit(1) }
            }
            Spacer(minLength: DS.Space.gap)
            ImasMetric(value: metric, unit: unit, size: .medium, emphasized: rank <= 3)
        }
        .padding(.horizontal, DS.Space.rowH)
        .padding(.vertical, DS.Space.rowVCompact)
        .frame(minHeight: DS.Size.touch)
        .background(DS.surface)
        .imasTheme(seed: seed, brand: brand)
    }
}

// MARK: - セトリの役割の札 (→ ImasBadge)

struct ImasTagChip: View {
    enum Kind { case unit, all, cover, partial, lead, guest }
    let text: String
    let kind: Kind
    var seed: String? = nil
    var brand: String? = nil

    var body: some View {
        ImasBadge(text: text, kind: badgeKind, seed: seed, brand: brand)
    }

    private var badgeKind: ImasBadge.Kind {
        switch kind {
        case .unit: return .unit
        case .all: return .all
        case .cover: return .cover
        case .partial: return .partial
        case .lead: return .lead
        case .guest: return .guest
        }
    }
}

// MARK: - 項目と値の行 (→ ImasValueRow)

/// 旧い呼び方の「項目: 値」の行。見た目は `ImasValueRow` と同じ寸法。
struct ImasLabeledRow: View {
    let key: String
    let value: String
    var showChevron: Bool = false
    var showSwatch: Bool = false
    var mono: Bool = false
    var tappable: Bool = false
    /// タップで省略を解除して全文を改行表示する (特技など長文向け)。値が 1 行に収まって
    /// いる行ではトグルもタップ操作も出さない (押しても何も起きない行を作らない)。
    var expandable: Bool = false
    var copyable: Bool = true
    var seed: String? = nil
    var brand: String? = nil
    @Environment(\.colorScheme) private var scheme
    @State private var expanded = false
    @State private var isTruncated = false

    private var showsToggle: Bool { expandable && (isTruncated || expanded) }

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        let valueFont = mono ? ImasTextRole.value.font.monospacedDigit() : ImasTextRole.value.font
        let row = HStack(spacing: DS.Space.rowGap) {
            Text(key).imasText(.value).foregroundStyle(DS.ink2)
            Spacer(minLength: DS.Space.rowGap)
            if showSwatch {
                Circle().fill(t.accent).frame(width: 16, height: 16)
            }
            Text(value)
                .font(valueFont)
                .foregroundStyle(tappable ? t.accent : DS.ink)
                .lineLimit(expandable ? (expanded ? nil : 1) : 1)
                .truncationMode(.tail)
                .multilineTextAlignment(.trailing)
                .truncationDetector(isTruncated: $isTruncated, text: value, font: valueFont, enabled: expandable)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.imasScaled(13, weight: .semibold))
                    .foregroundStyle(tappable ? t.accent : DS.ink3)
            } else if showsToggle {
                Image(systemName: "chevron.down")
                    .font(.imasScaled(11, weight: .semibold)).foregroundStyle(DS.ink3)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
        }
        .padding(.horizontal, DS.Space.rowH)
        .padding(.vertical, DS.Space.rowV)
        .frame(minHeight: DS.Size.touch)
        .background(DS.surface)
        .contentShape(Rectangle())

        // 省略されている値も原文 (`value`) を渡すので、全文がコピーできる。
        let copyableRow = row.imasCopyable(
            copyable ? [CopyItem("\(key)をコピー", value, key: "labeled_row")] : [])

        if showsToggle {
            copyableRow.onTapGesture { withAnimation(.imasStandard) { expanded.toggle() } }
        } else {
            copyableRow
        }
    }
}

// MARK: - 省略検出

private extension View {
    /// 1 行表示のテキストが実際に省略されているかを実測して `isTruncated` に反映する。
    /// iOS 17 が下限のため `onGeometryChange` (iOS 18+) は使わず GeometryReader で測る。
    func truncationDetector(isTruncated: Binding<Bool>, text: String, font: Font, enabled: Bool) -> some View {
        background {
            if enabled {
                GeometryReader { available in
                    Text(text)
                        .font(font)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .hidden()
                        .accessibilityHidden(true)
                        .background {
                            GeometryReader { natural in
                                Color.clear
                                    .task(id: natural.size.width) {
                                        // 端数で誤検知しないよう 0.5pt の余裕を見る。
                                        isTruncated.wrappedValue = natural.size.width > available.size.width + 0.5
                                    }
                            }
                        }
                }
            }
        }
    }
}

// MARK: - List の行装飾

extension View {
    /// List の中で「カードではない帯」を出す行装飾 (見出し・要約・空状態用)。
    ///
    /// `swipeActions` は List の行にしか効かないため、見出しや要約も List の行として
    /// 差さざるを得ない画面 (習熟度の 2 画面など) で使う。
    func plainRow(background: Color) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: DS.sp5, bottom: DS.sp5, trailing: DS.sp5))
            .listRowBackground(background)
            .listRowSeparator(.hidden)
    }
}

// MARK: - 広い画面での本文幅

extension DS {
    /// 広い画面 (iPad / Mac) で一覧の本文が伸びきらない幅。Web の本文段と揃える。
    static let readableContentWidth: CGFloat = 880
}

extension View {
    /// 一覧 (List / ScrollView) の本文を `DS.readableContentWidth` に収め、左右の余りを
    /// 余白にする。ナビバーや背景は全幅のまま、スクロールも画面全体で効く
    /// (`frame(maxWidth:)` で縮めると余白部分でスクロールできなくなる)。
    /// 狭い画面では余りが出ないので何も変わらない。
    ///
    /// ⚠️ 余白は配下のスクロールビューにも伝わる。横スクロールのチップ列などを
    /// 含む階層ではなく、縦の一覧そのものに付けること。
    func readableContentMargins() -> some View {
        modifier(ReadableContentMargins())
    }
}

private struct ReadableContentMargins: ViewModifier {
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, max(0, (width - DS.readableContentWidth) / 2), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
