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
    /// ライブ・公演のリードバー (実体の色の細い帯)。
    case bar(seed: String? = nil, brand: String? = nil, rainbow: Bool = false)
    /// アイドルのアイコン (40)。写真があれば写真、無ければ判子 (`ImasAvatar` の既定の見た目)。
    case avatar(label: String, seed: String? = nil, brand: String? = nil, imageURL: URL? = nil, isPick: Bool = false)
    /// 曲のジャケ (48、compact は 40)。
    case artwork(title: String, seed: String? = nil, brand: String? = nil, imageURL: URL? = nil)
    /// 記号 (幅 28、地なし)。`seed` / `brand` を渡すとその実体の色で点く (予定の種類・ブランド)。
    case icon(String, tone: ImasIconTile.Tone = .themed, seed: String? = nil, brand: String? = nil)
    /// 曲順・番号 (等幅)。
    case number(String)
    /// 曲順 + ジャケ (セトリ)。
    case numberedArtwork(number: String, title: String, seed: String? = nil, brand: String? = nil,
                         imageURL: URL? = nil)
    /// 順位。1〜3 位は実体色。
    case rank(Int)
    /// 選択の印 (ピッカー)。
    case selection(Bool, single: Bool = false)
    /// 部品の外で作った先頭 (ゲーム・特殊な一覧のみ。増やす前に種類を足せないか考える)。
    /// `alignment` は行内の縦揃え (既定は中央。セトリの曲順+ジャケのように上揃えにしたいときに渡す)。
    case custom(AnyView, width: CGFloat, alignment: VerticalAlignment = .center)
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
    /// 印 (担当・お気に入り) をその場で付け外しする記号のボタン。
    case mark(ImasMarkKind, isOn: Bool, action: () -> Void)
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

/// 行頭の色の帯 (ブランド・実体の色)。先頭 (ジャケなど) の前に立てる。楽曲一覧のブランドの色など。
struct ImasRowLeadBar: Equatable {
    var seed: String? = nil
    var brand: String? = nil
    var rainbow: Bool = false
}

/// 行の頭に置く選択の印 (`ImasSelectableRow` が使う)。
struct ImasRowSelection: Equatable {
    var isOn: Bool
    var single: Bool = false
    var seed: String? = nil
    var brand: String? = nil
}

struct ImasRow<Detail: View>: View {
    let title: String
    var subtitle: String? = nil
    var leading: ImasRowLeading = .none
    /// 先頭の前に置く選択の印。先頭 (ジャケ・アイコン) と並べて出せる。
    var selection: ImasRowSelection? = nil
    /// 先頭の前に立てる色の帯。
    var leadBar: ImasRowLeadBar? = nil
    var trailing: ImasRowTrailing = .none
    var density: ImasRowDensity = .regular
    var emphasis: ImasRowEmphasis = .normal
    var titleLineLimit: Int = 2
    /// 副題の行数。既定は 1 行 (値を添えるだけの行)。説明文が長い行は 2 にする。
    var subtitleLineLimit: Int = 1
    /// 題の代わりに強調付きの文字 (絞り込みで当たった所に色を敷くなど)。
    var attributedTitle: AttributedString? = nil
    /// 題の書体。もの (曲・アイドル・ライブ) は `.rowTitle`、操作・設定は `.rowLabel`。
    var titleRole: ImasTextRole = .rowTitle
    /// 題だけを押せるようにする (行の他の場所にも別の押せる物があるとき)。nil なら押せない文字のまま。
    var onSelectTitle: (() -> Void)? = nil
    /// 題の読み上げを見た目の文字と変えたいとき (「タグ: 〇〇」など前置きを足す)。nil なら題の文字をそのまま読む。
    /// 行全体に付けると副題・末尾の札まで隠れて読めなくなるため、ここで題だけに絞って付ける。
    var titleAccessibilityLabel: String? = nil
    @ViewBuilder var detail: Detail

    @Environment(\.imasRowPosition) private var position
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.gap))
            : AnyLayout(HStackLayout(alignment: rowAlignment, spacing: DS.Space.rowGap))

        layout {
            HStack(alignment: rowAlignment, spacing: DS.Space.rowGap) {
                if let selection {
                    ImasSelectionMark(isSelected: selection.isOn, seed: selection.seed, brand: selection.brand,
                                      isSingle: selection.single)
                }
                if let leadBar {
                    ImasLeadBar(seed: leadBar.seed, brand: leadBar.brand, rainbow: leadBar.rainbow)
                        .frame(height: leadBarHeight)
                }
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
                let markWidth: CGFloat = selection == nil ? 0 : 24 + DS.Space.rowGap
                let barWidth: CGFloat = leadBar == nil ? 0 : DS.Size.leadBar + DS.Space.rowGap
                ImasRowDivider(inset: DS.Space.rowH + markWidth + barWidth + leadingWidth
                               + (leadingWidth > 0 ? DS.Space.rowGap : 0))
            }
        }
        // 余白は行が持つので、List・Form の中では List の余白を消す (二重に入らないように)。
        .listRowInsets(EdgeInsets())
    }

    /// 曲順・順位は題の 1 行目に揃える (セトリの紙と同じ)。ほかは行の中央。
    private var rowAlignment: VerticalAlignment {
        switch leading {
        case .number, .rank: return .firstTextBaseline
        case .numberedArtwork: return .top
        case let .custom(_, _, alignment): return alignment
        default: return .center
        }
    }

    // MARK: 本文

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            titleView

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(ImasTextRole.rowSubtitle.font)
                    .foregroundStyle(emphasis == .dimmed ? DS.ink3 : DS.ink2)
                    .lineLimit(subtitleLineLimit)
            }
            detail
        }
    }

    /// 題の文字。`onSelectTitle` があるときだけボタンにする (行の他の場所の押せる物を邪魔しない)。
    @ViewBuilder private var titleView: some View {
        let text = Group {
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
        .accessibilityLabel(titleAccessibilityLabel ?? title)

        if let onSelectTitle {
            Button(action: onSelectTitle) {
                text.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        } else {
            text
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
            // 写真があれば写真、無ければ ImasAvatar 既定の判子 (アイコンは常に出す)。
            ImasAvatar(label: label, seed: seed, brand: brand, size: density.avatarSize, isPick: isPick, imageURL: url)
        case let .artwork(title, seed, brand, url):
            ImasArtwork(title: title, seed: seed, brand: brand, size: density.artworkSize, imageURL: url)
        case let .icon(name, tone, seed, brand):
            ImasIconTile(systemImage: name, size: .s28, tone: tone, seed: seed, brand: brand)
        case let .number(text):
            Text(text)
                .font(ImasNumeralSize.small.font)
                .foregroundStyle(DS.ink3)
                .frame(width: 30, alignment: .trailing)
        case let .numberedArtwork(number, title, seed, brand, url):
            HStack(alignment: .top, spacing: 10) {
                Text(number)
                    .font(.imasMono(11.5, weight: .bold))
                    .foregroundStyle(DS.ink2)
                    .frame(width: 24, alignment: .trailing)
                    .padding(.top, 2)
                ImasArtwork(title: title, seed: seed, brand: brand, size: 44, imageURL: url)
            }
        case let .rank(rank):
            ImasRankNumber(rank: rank)
        case let .selection(isOn, single):
            ImasSelectionMark(isSelected: isOn, isSingle: single)
        case let .custom(view, width, _):
            view.frame(width: width)
        }
    }

    /// 色の帯の高さ。ジャケと並ぶときはジャケの高さに揃える。
    private var leadBarHeight: CGFloat {
        switch leading {
        case .artwork: return density.artworkSize
        case .numberedArtwork: return 44
        // `.custom` は呼び出し側がジャケ等を直書きした先頭 (例: 試聴対応の ImasSongRow)。
        // 渡された `width` がその面の一辺 (正方形) なので、帯もそれに揃える。
        // 揃えないと試聴対応の行だけ帯が既定の 36pt のまま浮いてばらつく。
        case let .custom(_, width, _): return width
        default: return 36
        }
    }

    /// 先頭の幅 (区切り線を本文の頭に揃えるため)。
    private var leadingWidth: CGFloat {
        switch leading {
        case .none: return 0
        case .bar: return DS.Size.leadBar
        case .avatar: return density.avatarSize + ImasAvatar.ringPadding * 2
        case .artwork: return density.artworkSize
        case .icon: return ImasIconTile.Size.s28.rawValue
        case .number: return 30
        case .numberedArtwork: return 24 + 10 + 44
        case .rank: return ImasRankNumber.width
        case .selection: return 24
        case let .custom(_, width, _): return width
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
                .imasText(.value, color: DS.ink2)
                .lineLimit(1)
        case let .metric(value, unit, emphasized):
            ImasMetric(value: value, unit: unit, size: .medium, emphasized: emphasized)
        case let .badge(badge):
            badge
        case let .toggle(binding):
            Toggle("", isOn: binding).labelsHidden().tint(DS.switchOn)
        case let .mark(kind, isOn, action):
            ImasMarkButton(kind: kind, isOn: isOn, action: action)
        case let .custom(view):
            view
        }
    }
}

extension ImasRow where Detail == EmptyView {
    init(title: String, subtitle: String? = nil, leading: ImasRowLeading = .none,
         selection: ImasRowSelection? = nil,
         trailing: ImasRowTrailing = .none, density: ImasRowDensity = .regular,
         emphasis: ImasRowEmphasis = .normal, titleLineLimit: Int = 2, subtitleLineLimit: Int = 1,
         titleRole: ImasTextRole = .rowTitle,
         onSelectTitle: (() -> Void)? = nil, titleAccessibilityLabel: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.selection = selection
        self.trailing = trailing
        self.density = density
        self.emphasis = emphasis
        self.titleLineLimit = titleLineLimit
        self.subtitleLineLimit = subtitleLineLimit
        self.titleRole = titleRole
        self.onSelectTitle = onSelectTitle
        self.titleAccessibilityLabel = titleAccessibilityLabel
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

/// 順位の数字。1〜3 位は墨、それ以外は薄灰 (色で順位を飾らない)。
struct ImasRankNumber: View {
    let rank: Int
    static let width: CGFloat = 28

    var body: some View {
        Text("\(rank)")
            .font(Font.imasScaled(20, weight: .heavy).width(.compressed).monospacedDigit())
            .foregroundStyle(rank <= 3 ? DS.ink : DS.ink3)
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
    /// 行を並べ、2 行目以降の上に区切り線を引く (線は行が本文の頭から引く)。
    init<Data: RandomAccessCollection, ID: Hashable, Row: View>(
        _ data: Data, id: KeyPath<Data.Element, ID>, style: Style = .panel,
        @ViewBuilder row: @escaping (Data.Element) -> Row
    ) where Content == ImasCardListRows<Data, ID, Row> {
        self.init(style: style) { ImasCardListRows(data: data, id: id, row: row) }
    }

    init<Data: RandomAccessCollection, Row: View>(
        _ data: Data, style: Style = .panel, @ViewBuilder row: @escaping (Data.Element) -> Row
    ) where Data.Element: Identifiable, Content == ImasCardListRows<Data, Data.Element.ID, Row> {
        self.init(style: style) { ImasCardListRows(data: data, id: \.id, row: row) }
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
    /// 値が押せる (別画面へ行く・外へ飛ぶ) とき。矢印を出す (値の色は変えない)。
    var isLink: Bool = false
    /// 長い値を開閉できるようにする (省略されているときだけ開閉が出る)。
    var expandable: Bool = false
    /// 数字を等幅にする。
    var monospaced: Bool = false
    var copyable: Bool = true

    @Environment(\.imasRowPosition) private var position
    @State private var expanded = false
    @State private var isTruncated = false

    private var showsToggle: Bool { expandable && (isTruncated || expanded) }

    var body: some View {
        let row = HStack(alignment: .firstTextBaseline, spacing: DS.Space.rowGap) {
            Text(key)
                .imasText(.value, color: DS.ink2)
                .layoutPriority(1)
            Spacer(minLength: DS.Space.rowGap)
            Text(value)
                .font(monospaced ? ImasTextRole.value.font.monospacedDigit() : ImasTextRole.value.font)
                .foregroundStyle(DS.ink)
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
        .listRowInsets(EdgeInsets())
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
    var iconTone: ImasIconTile.Tone = .solid
    /// 記号を実体の色で点けたいとき (混在ブランドの一覧など)。既定は `iconTone` 任せ。
    var seed: String? = nil
    var brand: String? = nil
    var value: String? = nil
    /// 押してから外へ飛ぶまでの待ち。矢印をくるくるに替える。
    var isLoading: Bool = false
    /// 矢印を描くか。`NavigationLink` の中など、OS 側が既に矢印を出す場所では `false` にする
    /// (二重に並ぶのを防ぐ)。既定は今まで通り出す。
    var showsChevron: Bool = true
    /// 副題の行数。既定は 1 行、説明文が長い行は 2 にする。
    var subtitleLineLimit: Int = 1
    /// 題の行数。既定は 1 行。見分ける語が丸ごと要る行は 2 にする。
    var titleLineLimit: Int = 1

    var body: some View {
        ImasRow(
            title: title,
            subtitle: subtitle,
            leading: systemImage.map { .icon($0, tone: iconTone, seed: seed, brand: brand) } ?? .none,
            trailing: .custom(AnyView(
                HStack(spacing: DS.Space.gap) {
                    if let value {
                        Text(value).imasText(.value, color: DS.ink2).lineLimit(1)
                    }
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else if showsChevron {
                        ImasRowChevron()
                    }
                }
            )),
            density: .compact,
            titleLineLimit: titleLineLimit,
            subtitleLineLimit: subtitleLineLimit,
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

/// 選べる行 (ピッカー・複数選択)。行のどこを押しても切り替わる。
/// 複数選択は ○ と ✓、1 つ選択は選んだ行にだけ ✓。先頭 (ジャケ・アイコン) と並べられる。
struct ImasSelectableRow: View {
    let title: String
    var subtitle: String? = nil
    var leading: ImasRowLeading = .none
    var trailing: ImasRowTrailing = .none
    let isSelected: Bool
    var isSingle: Bool = false
    var seed: String? = nil
    var brand: String? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ImasRow(
                title: title,
                subtitle: subtitle,
                leading: leading,
                selection: ImasRowSelection(isOn: isSelected, single: isSingle, seed: seed, brand: brand),
                trailing: trailing,
                density: .compact,
                emphasis: isDisabled ? .dimmed : .normal
            )
        }
        .buttonStyle(.imasRow)
        .disabled(isDisabled)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 値を 1 つ選ぶ設定の行。押すとその場に選択肢のメニューが出る (画面を移らない)。
struct ImasMenuRow<Selection: Hashable>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    let options: [Selection]
    @Binding var selection: Selection
    let label: (Selection) -> String

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
        } label: {
            ImasRow(
                title: title,
                subtitle: subtitle,
                leading: systemImage.map { .icon($0, tone: .neutral) } ?? .none,
                trailing: .custom(AnyView(
                    HStack(spacing: DS.Space.gapTight) {
                        Text(label(selection)).imasText(.value, color: DS.ink2).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.imasScaled(11, weight: .semibold))
                            .foregroundStyle(DS.ink3)
                    }
                )),
                density: .compact,
                titleLineLimit: 1,
                titleRole: .rowLabel
            )
        }
        .buttonStyle(.imasRow)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// 数を 1 つずつ増減する設定の行 (問題数・人数)。
struct ImasStepperRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    var unit: String? = nil

    var body: some View {
        ImasRow(
            title: title,
            subtitle: subtitle,
            leading: systemImage.map { .icon($0, tone: .neutral) } ?? .none,
            trailing: .custom(AnyView(
                HStack(spacing: DS.Space.gap) {
                    ImasMetric(value: "\(value)", unit: unit, size: .medium, emphasized: true)
                    Stepper(title, value: $value, in: range, step: step).labelsHidden()
                }
            )),
            density: .compact,
            titleLineLimit: 1,
            titleRole: .rowLabel
        )
        .sensoryFeedback(.selection, trigger: value)
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
    /// 処理中。記号をくるくるに替え、押せなくする (発行・送信など時間のかかる操作)。
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.imasRowPosition) private var position

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.gap) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                Spacer(minLength: 0)
            }
            .font(ImasTextRole.rowLabel.font)
            .foregroundStyle(kind == .destructive ? DS.danger : DS.ink)
            .padding(.horizontal, DS.Space.rowH)
            .frame(maxWidth: .infinity, minHeight: DS.Size.touch, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if position == .following { ImasRowDivider(inset: DS.Space.rowH) }
            }
        }
        .buttonStyle(.imasRow)
        .disabled(isLoading)
        .listRowInsets(EdgeInsets())
    }
}

// MARK: - 印のボタン

/// 行や頭で付け外しする印の種類。記号と読み上げを決める。
enum ImasMarkKind {
    /// 担当 (♥)。
    case pick
    /// お気に入り (★)。
    case favorite
    /// 所有 (カードゲームの収録カードなど)。
    case owned

    func systemImage(isOn: Bool) -> String {
        switch self {
        case .pick: return isOn ? "heart.fill" : "heart"
        case .favorite: return isOn ? "star.fill" : "star"
        case .owned: return isOn ? "shippingbox.fill" : "shippingbox"
        }
    }

    func accessibilityLabel(isOn: Bool) -> String {
        switch self {
        case .pick: return isOn ? "担当から外す" : "担当にする"
        case .favorite: return isOn ? "お気に入りから外す" : "お気に入りにする"
        case .owned: return isOn ? "所有から外す" : "所有を記録"
        }
    }
}

/// 印 (担当・お気に入り) をその場で付け外しする記号のボタン。押せる所は 44pt。
/// ON は実体の色で点き (無ければ墨)、OFF は薄い墨の線の記号。押すと手応えを返す。
struct ImasMarkButton: View {
    let kind: ImasMarkKind
    let isOn: Bool
    var seed: String? = nil
    var brand: String? = nil
    let action: () -> Void

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: nil, env: envTheme, scheme: scheme)
        Button(action: action) {
            Image(systemName: kind.systemImage(isOn: isOn))
                .font(.imasScaled(18, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? onColor(t) : DS.ink3)
                .symbolEffect(.bounce, value: isOn)
                .frame(minWidth: DS.Size.touch, minHeight: DS.Size.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.impact(weight: .light), trigger: isOn)
        .accessibilityLabel(kind.accessibilityLabel(isOn: isOn))
    }

    private func onColor(_ t: ImasTheme) -> Color {
        switch kind {
        case .pick: return t.isNeutral ? DS.pick : t.penlight
        case .favorite: return DS.favorite
        case .owned: return t.isNeutral ? DS.ink : t.accent
        }
    }
}
