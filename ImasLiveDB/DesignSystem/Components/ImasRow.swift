import SwiftUI

// =============================================================================
// 行 (docs/DESIGN_SYSTEM.md §5)
//
// 用途      一覧・カードの中で、1 つのものを 1 行で見せる。
// 構成      [先頭] [題 (16pt 太字・2 行まで) / 副題 (13pt 灰) / 下段 (札・日付)] [末尾]
// 種類      regular (一覧・上下 12) / compact (カードの中の短い一覧・ピッカー・上下 8)
// 状態      通常 / 押下 (面が fill) / 選択 (先頭の選択印) / 薄字 (欠席・未配信) / 無効
// 区切り線  行が持つ。List の中では本文の頭に揃い、`ImasCardList(items)` の中では
//           2 行目以降の上に本文の頭から線を引く。画面で Divider を書かない。
//
// 実体ごとの行 (ImasSongRow など) はこの形の中身を実体のデータから決めたもの。
// =============================================================================

/// 行の先頭に置けるもの。
enum ImasRowLeading {
    case none
    /// ライブ・公演のリードバー。
    case bar(seed: String? = nil, brand: String? = nil, rainbow: Bool = false)
    /// アイドルのアバター (40)。
    case avatar(label: String, seed: String? = nil, brand: String? = nil, imageURL: URL? = nil, isPick: Bool = false)
    /// 曲のジャケ (48、compact は 40)。
    case artwork(title: String, seed: String? = nil, brand: String? = nil, imageURL: URL? = nil)
    /// 記号の札 (32)。
    case icon(String, tone: ImasIconTile.Tone = .themed)
    /// 曲順・番号 (等幅)。
    case number(String)
    /// 順位。1〜3 位は実体色。
    case rank(Int)
    /// 選択の印 (ピッカー)。
    case selection(Bool, single: Bool = false)
    /// 部品の外で作った先頭 (ゲーム・特殊な一覧のみ。増やす前に種類を足せないか考える)。
    case custom(AnyView, width: CGFloat)
}

/// 行の末尾に置けるもの。
enum ImasRowTrailing {
    case none
    /// 別画面へ進む矢印 (カードの中の行のみ。List の行には出さない)。
    case chevron
    /// 値 (灰)。
    case value(String)
    /// 数字 + 単位。並べ替えの根拠・票・回数。
    case metric(String, unit: String? = nil, emphasized: Bool = false)
    /// 状態の札。
    case badge(ImasBadge)
    /// スイッチ。
    case toggle(Binding<Bool>)
    /// 部品の外で作った末尾 (「予想する」ボタン・印のボタンなど)。
    case custom(AnyView)
}

enum ImasRowDensity {
    case regular
    case compact

    var verticalPadding: CGFloat { self == .regular ? DS.Space.rowV : DS.Space.rowVCompact }
    var artworkSize: CGFloat { self == .regular ? 48 : 40 }
    var avatarSize: CGFloat { self == .regular ? 40 : 32 }
}

enum ImasRowEmphasis {
    case normal
    /// 欠席・未配信・終わったもの。題と副題を薄くする。
    case dimmed
}

/// `ImasCardList(items)` の中で、行が 1 行目かどうか (区切り線を引くか) を伝える。
enum ImasRowPosition {
    /// 区切り線を行が引かない (List の中・単独の行)。
    case standalone
    /// カードの 1 行目。
    case first
    /// カードの 2 行目以降。上に区切り線を引く。
    case following
}

private struct ImasRowPositionKey: EnvironmentKey {
    static let defaultValue: ImasRowPosition = .standalone
}

extension EnvironmentValues {
    var imasRowPosition: ImasRowPosition {
        get { self[ImasRowPositionKey.self] }
        set { self[ImasRowPositionKey.self] = newValue }
    }
}

struct ImasRow<Detail: View>: View {
    let title: String
    var subtitle: String? = nil
    var leading: ImasRowLeading = .none
    var trailing: ImasRowTrailing = .none
    var density: ImasRowDensity = .regular
    var emphasis: ImasRowEmphasis = .normal
    var titleLineLimit: Int = 2
    /// 題の代わりに強調付きの文字 (絞り込みで当たった所に色を敷くなど)。
    var attributedTitle: AttributedString? = nil
    /// 題の書体。もの (曲・アイドル・ライブ) は `.rowTitle`、操作・設定は `.rowLabel`。
    var titleRole: ImasTextRole = .rowTitle
    @ViewBuilder var detail: Detail

    @Environment(\.imasRowPosition) private var position
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.gap))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DS.Space.rowGap))

        layout {
            HStack(alignment: .center, spacing: DS.Space.rowGap) {
                leadingView
                textColumn
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength: 0)
            }
            trailingView
        }
        .padding(.horizontal, DS.Space.rowH)
        .padding(.vertical, density.verticalPadding)
        .frame(minHeight: DS.Size.touch)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if position == .following {
                ImasRowDivider(inset: DS.Space.rowH + leadingWidth + (leadingWidth > 0 ? DS.Space.rowGap : 0))
            }
        }
        .opacity(1)
    }

    // MARK: 本文

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            Group {
                if let attributedTitle {
                    Text(attributedTitle)
                } else {
                    Text(title)
                }
            }
            .font(titleRole.font)
            .foregroundStyle(emphasis == .dimmed ? DS.ink3 : DS.ink)
            .lineLimit(titleLineLimit)
            .fixedSize(horizontal: false, vertical: true)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(ImasTextRole.rowSubtitle.font)
                    .foregroundStyle(emphasis == .dimmed ? DS.ink3 : DS.ink2)
                    .lineLimit(1)
            }
            detail
        }
    }

    // MARK: 先頭

    @ViewBuilder private var leadingView: some View {
        switch leading {
        case .none:
            EmptyView()
        case let .bar(seed, brand, rainbow):
            ImasLeadBar(seed: seed, brand: brand, rainbow: rainbow)
                .frame(height: 36)
        case let .avatar(label, seed, brand, url, isPick):
            ImasAvatar(label: label, seed: seed, brand: brand, size: density.avatarSize, isPick: isPick, imageURL: url)
        case let .artwork(title, seed, brand, url):
            ImasArtwork(title: title, seed: seed, brand: brand, size: density.artworkSize, imageURL: url)
        case let .icon(name, tone):
            ImasIconTile(systemImage: name, size: .s32, tone: tone)
        case let .number(text):
            Text(text)
                .font(ImasNumeralSize.small.font)
                .foregroundStyle(DS.ink3)
                .frame(width: 30, alignment: .trailing)
        case let .rank(rank):
            ImasRankNumber(rank: rank)
        case let .selection(isOn, single):
            ImasSelectionMark(isSelected: isOn, isSingle: single)
        case let .custom(view, width):
            view.frame(width: width)
        }
    }

    /// 先頭の幅 (区切り線を本文の頭に揃えるため)。
    private var leadingWidth: CGFloat {
        switch leading {
        case .none: return 0
        case .bar: return DS.Size.leadBar
        case .avatar: return density.avatarSize + ImasAvatar.ringPadding * 2
        case .artwork: return density.artworkSize
        case .icon: return ImasIconTile.Size.s32.rawValue
        case .number: return 30
        case .rank: return ImasRankNumber.width
        case .selection: return 24
        case let .custom(_, width): return width
        }
    }

    // MARK: 末尾

    @ViewBuilder private var trailingView: some View {
        switch trailing {
        case .none:
            EmptyView()
        case .chevron:
            ImasRowChevron()
        case let .value(text):
            Text(text)
                .imasText(.value)
                .foregroundStyle(DS.ink2)
                .lineLimit(1)
        case let .metric(value, unit, emphasized):
            ImasMetric(value: value, unit: unit, size: .medium, emphasized: emphasized)
        case let .badge(badge):
            badge
        case let .toggle(binding):
            Toggle("", isOn: binding).labelsHidden()
        case let .custom(view):
            view
        }
    }
}

extension ImasRow where Detail == EmptyView {
    init(title: String, subtitle: String? = nil, leading: ImasRowLeading = .none,
         trailing: ImasRowTrailing = .none, density: ImasRowDensity = .regular,
         emphasis: ImasRowEmphasis = .normal, titleLineLimit: Int = 2, titleRole: ImasTextRole = .rowTitle) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.trailing = trailing
        self.density = density
        self.emphasis = emphasis
        self.titleLineLimit = titleLineLimit
        self.titleRole = titleRole
        self.detail = EmptyView()
    }
}

// MARK: - 行の中の小物

/// 一覧行の末尾の「>」。
struct ImasRowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.imasScaled(13, weight: .semibold))
            .foregroundStyle(DS.ink3)
            .accessibilityHidden(true)
    }
}

/// 順位の数字。1〜3 位は実体色、それ以外は薄灰。
struct ImasRankNumber: View {
    let rank: Int
    static let width: CGFloat = 28

    @Environment(\.imasTheme) private var theme

    var body: some View {
        Text("\(rank)")
            .font(Font.imasScaled(18, weight: .heavy).width(.condensed).monospacedDigit())
            .foregroundStyle(rank <= 3 ? (theme.isNeutral ? DS.ink : theme.accent) : DS.ink3)
            .frame(width: Self.width)
            .accessibilityLabel("\(rank)位")
    }
}

/// 行を押したときの見え方 (面が fill になる)。`Button` / `NavigationLink` に付ける。
struct ImasRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DS.fill : Color.clear)
            .animation(.imasStandard, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ImasRowButtonStyle {
    /// カードの中の行を押せるようにする。
    static var imasRow: ImasRowButtonStyle { ImasRowButtonStyle() }
}

// MARK: - カードに行を並べる

extension ImasCardList {
    /// 行をカードに入れ、2 行目以降の上に区切り線を引く (線は行が本文の頭から引く)。
    init<Data: RandomAccessCollection, ID: Hashable, Row: View>(
        _ data: Data, id: KeyPath<Data.Element, ID>,
        @ViewBuilder row: @escaping (Data.Element) -> Row
    ) where Content == ImasCardListRows<Data, ID, Row> {
        self.init { ImasCardListRows(data: data, id: id, row: row) }
    }

    init<Data: RandomAccessCollection, Row: View>(
        _ data: Data, @ViewBuilder row: @escaping (Data.Element) -> Row
    ) where Data.Element: Identifiable, Content == ImasCardListRows<Data, Data.Element.ID, Row> {
        self.init { ImasCardListRows(data: data, id: \.id, row: row) }
    }
}

/// `ImasCardList(items)` の中身。行に 1 行目かどうかを伝える。
struct ImasCardListRows<Data: RandomAccessCollection, ID: Hashable, Row: View>: View {
    let data: Data
    let id: KeyPath<Data.Element, ID>
    let row: (Data.Element) -> Row

    var body: some View {
        let firstID = data.first.map { $0[keyPath: id] }
        ForEach(data, id: id) { element in
            row(element)
                .environment(\.imasRowPosition, element[keyPath: id] == firstID ? .first : .following)
        }
    }
}

// MARK: - 項目と値の行

/// 「項目: 値」の行 (よみ・CV・会場・キャパ・価格)。長押しで値をコピーできる。
struct ImasValueRow: View {
    let key: String
    let value: String
    /// 値が押せる (別画面へ行く・外へ飛ぶ) とき。値を実体色にして矢印を出す。
    var isLink: Bool = false
    /// 長い値を開閉できるようにする (省略されているときだけ開閉が出る)。
    var expandable: Bool = false
    /// 数字を等幅にする。
    var monospaced: Bool = false
    var copyable: Bool = true

    @Environment(\.imasTheme) private var theme
    @Environment(\.imasRowPosition) private var position
    @State private var expanded = false
    @State private var isTruncated = false

    private var showsToggle: Bool { expandable && (isTruncated || expanded) }

    var body: some View {
        let row = HStack(alignment: .firstTextBaseline, spacing: DS.Space.rowGap) {
            Text(key)
                .imasText(.value)
                .foregroundStyle(DS.ink2)
                .layoutPriority(1)
            Spacer(minLength: DS.Space.rowGap)
            Text(value)
                .font(monospaced ? ImasTextRole.value.font.monospacedDigit() : ImasTextRole.value.font)
                .foregroundStyle(isLink ? (theme.isNeutral ? DS.ink : theme.accent) : DS.ink)
                .lineLimit(expandable && expanded ? nil : 1)
                .multilineTextAlignment(.trailing)
                .background(TruncationProbe(text: value, isTruncated: $isTruncated, enabled: expandable))
            if isLink {
                ImasRowChevron()
            } else if showsToggle {
                Image(systemName: "chevron.down")
                    .font(.imasScaled(11, weight: .semibold))
                    .foregroundStyle(DS.ink3)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
        }
        .padding(.horizontal, DS.Space.rowH)
        .padding(.vertical, DS.Space.rowV)
        .frame(minHeight: DS.Size.touch)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if position == .following { ImasRowDivider(inset: DS.Space.rowH) }
        }
        .imasCopyable(copyable ? [CopyItem("\(key)をコピー", value, key: "labeled_row")] : [])

        if showsToggle {
            row.onTapGesture { withAnimation(.imasStandard) { expanded.toggle() } }
        } else {
            row
        }
    }
}

/// 1 行表示の文字が実際に省略されているかを測る。
private struct TruncationProbe: View {
    let text: String
    @Binding var isTruncated: Bool
    let enabled: Bool

    var body: some View {
        if enabled {
            GeometryReader { available in
                Text(text)
                    .font(ImasTextRole.value.font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .accessibilityHidden(true)
                    .background {
                        GeometryReader { natural in
                            Color.clear.task(id: natural.size.width) {
                                isTruncated = natural.size.width > available.size.width + 0.5
                            }
                        }
                    }
            }
        }
    }
}

// MARK: - 入口・設定の行

/// 別の画面へ進む入口の行 (設定・マイページ・ハブの一覧)。押すと進むので末尾は矢印。
struct ImasNavRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var iconTone: ImasIconTile.Tone = .neutral
    var value: String? = nil

    var body: some View {
        ImasRow(
            title: title,
            subtitle: subtitle,
            leading: systemImage.map { .icon($0, tone: iconTone) } ?? .none,
            trailing: .custom(AnyView(
                HStack(spacing: DS.Space.gap) {
                    if let value {
                        Text(value).imasText(.value).foregroundStyle(DS.ink2).lineLimit(1)
                    }
                    ImasRowChevron()
                }
            )),
            density: .compact,
            titleLineLimit: 1,
            titleRole: .rowLabel
        )
    }
}

/// 設定のオンオフ。
struct ImasToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        ImasRow(
            title: title,
            subtitle: subtitle,
            leading: systemImage.map { .icon($0, tone: .neutral) } ?? .none,
            trailing: .toggle($isOn),
            density: .compact,
            titleRole: .rowLabel
        )
    }
}

/// 行の形のボタン (「＋ 曲を追加」「このライブを削除」)。
struct ImasActionRow: View {
    enum Kind {
        case standard
        case destructive
    }

    let title: String
    var systemImage: String? = nil
    var kind: Kind = .standard
    let action: () -> Void

    @Environment(\.imasTheme) private var theme
    @Environment(\.imasRowPosition) private var position

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.gap) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
                Spacer(minLength: 0)
            }
            .font(ImasTextRole.rowLabel.font)
            .foregroundStyle(kind == .destructive ? DS.danger : (theme.isNeutral ? DS.ink : theme.accent))
            .padding(.horizontal, DS.Space.rowH)
            .frame(maxWidth: .infinity, minHeight: DS.Size.touch, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if position == .following { ImasRowDivider(inset: DS.Space.rowH) }
            }
        }
        .buttonStyle(.imasRow)
    }
}
