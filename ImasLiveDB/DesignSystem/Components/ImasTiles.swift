import SwiftUI

// =============================================================================
// カード・数・メーター・入口 (docs/DESIGN_SYSTEM.md §6.3〜§6.5・§10.4)
//
// ImasFeatureCard   ハブの最上段で「いま一番大事なもの」を 1 枚で。題は大きく、操作は下に行で並べる。
// ImasEntryCard     奥の画面への入口を大きく見せる。
// ImasStatTile      数 1 つ (記号 + 細長い太字の数 + 名前)。`ImasStatGrid` が 1 枚の面に並べる。
// ImasStatBar       項目ごとの割合の横棒。
// ImasProgressRing  1 つの割合を大きく。
// ImasShortcutGroup 種類ごとの入口の行のまとまり (あそぶ・みんな・しらべる)。
// ImasCarousel      カードを横に流す。
//
// どれも色の地を敷かない。面は地から決まる灰 (紙面) か白 (灰の地) で、実体の色は
// ペンライトと記号にだけ出す。記号は淡い色の四角に入れない (v1 の「よくある見た目」の元)。
// =============================================================================

// MARK: - 主役のカード

/// 主役のカードの面。
enum ImasFeatureSurface {
    /// 地の上の面 (紙面なら灰)。
    case panel
    /// 実体の色を面いっぱいに塗る (担当)。文字は色の上で読める白か黒。
    case color
}

/// ハブの最上段で「いま一番大事なもの」を 1 枚で見せる (担当・次のライブ・開催中のお題)。
///
/// 構成は [ペンライト + 目印 ……… 右上の数] / [画像] [題 (19pt 太字) / 副題] / [操作の行 …]。
/// 操作は塗りのボタンを 2 つ並べず、行 (文言 + 矢印) で下に重ねる。押せる所の大きさが揃い、
/// 「主・副のボタンが並ぶカード」というどこにでもある形にならない。
struct ImasFeatureCard<Media: View>: View {
    struct Action {
        let title: String
        var systemImage: String? = nil
        let action: () -> Void
    }

    /// 右上の数 (「あと 37 日」)。
    struct Metric {
        var prefix: String? = nil
        let value: String
        var unit: String? = nil
    }

    typealias Surface = ImasFeatureSurface

    /// 上の目印 (「担当」「参加予定」)。前に実体の色のペンライトが付く。
    var eyebrow: String? = nil
    /// 目印の前にペンライトを付けるか。実体に紐づかない一般の見出し (「BATTLE MODE」等) は false にする。
    var eyebrowPenlight: Bool = true
    let title: String
    var subtitle: String? = nil
    var seed: String? = nil
    var brand: String? = nil
    var metric: Metric? = nil
    var surface: Surface = .panel
    /// カードの頭 (目印〜副題) を押したときの行き先。
    var onOpen: (() -> Void)? = nil
    var primary: Action? = nil
    var secondary: Action? = nil
    @ViewBuilder var media: Media

    var body: some View {
        FeatureCardBody(eyebrow: eyebrow, eyebrowPenlight: eyebrowPenlight, title: title, subtitle: subtitle,
                        metric: metric, surface: surface, onOpen: onOpen,
                        actions: [primary, secondary].compactMap { $0 }, media: media)
            .imasTheme(seed: seed, brand: brand)
    }
}

extension ImasFeatureCard where Media == EmptyView {
    init(eyebrow: String? = nil, eyebrowPenlight: Bool = true, title: String, subtitle: String? = nil,
         seed: String? = nil, brand: String? = nil, metric: Metric? = nil, surface: Surface = .panel,
         onOpen: (() -> Void)? = nil, primary: Action? = nil, secondary: Action? = nil) {
        self.init(eyebrow: eyebrow, eyebrowPenlight: eyebrowPenlight, title: title, subtitle: subtitle,
                  seed: seed, brand: brand, metric: metric, surface: surface, onOpen: onOpen,
                  primary: primary, secondary: secondary) { EmptyView() }
    }
}

private struct FeatureCardBody<Media: View>: View {
    let eyebrow: String?
    let eyebrowPenlight: Bool
    let title: String
    let subtitle: String?
    let metric: ImasFeatureCard<Media>.Metric?
    let surface: ImasFeatureCard<Media>.Surface
    let onOpen: (() -> Void)?
    let actions: [ImasFeatureCard<Media>.Action]
    let media: Media

    @Environment(\.imasTheme) private var theme
    @Environment(\.imasBackdrop) private var backdrop

    private var onColor: Bool { surface == .color && !theme.isNeutral }
    private var fill: Color { onColor ? theme.accent : DS.surface(on: backdrop) }
    private var ink: Color { onColor ? theme.onAccent : DS.ink }
    private var ink2: Color { onColor ? theme.onAccent.opacity(0.78) : DS.ink2 }
    private var rule: Color { onColor ? theme.onAccent.opacity(0.22) : DS.sep }
    private var pressed: Color { onColor ? theme.onAccent.opacity(0.1) : DS.fill }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.rCard, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if let onOpen {
                Button(action: onOpen) { head }
                    .buttonStyle(FeatureCardPressStyle(pressedFill: pressed))
            } else {
                head
            }
            ForEach(Array(actions.enumerated()), id: \.offset) { _, a in
                Rectangle().fill(rule).frame(height: 0.5).padding(.leading, DS.Space.card)
                Button(action: a.action) {
                    HStack(spacing: DS.Space.gap) {
                        if let s = a.systemImage {
                            Image(systemName: s).font(.imasScaled(15, weight: .semibold))
                        }
                        Text(a.title).font(.imasHeading(16, weight: .semibold))
                        Spacer(minLength: DS.Space.gap)
                        Image(systemName: "chevron.right")
                            .font(.imasScaled(13, weight: .semibold))
                            .foregroundStyle(ink2)
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, DS.Space.card)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FeatureCardPressStyle(pressedFill: pressed))
            }
        }
        .background(fill, in: shape)
        .clipShape(shape)
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
            if eyebrow != nil || metric != nil {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.gap) {
                    if let eyebrow {
                        HStack(spacing: 7) {
                            if eyebrowPenlight {
                                ImasPenlight(color: onColor ? theme.onAccent : theme.penlight, size: .regular)
                            }
                            Text(eyebrow)
                                .font(ImasTextRole.eyebrow.font)
                                .foregroundStyle(ink2)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: DS.Space.gap)
                    if let metric {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            if let prefix = metric.prefix {
                                Text(prefix).font(.imasFootnote.weight(.semibold)).foregroundStyle(ink2)
                            }
                            if !metric.value.isEmpty {
                                Text(metric.value)
                                    .font(ImasNumeralSize.large.font)
                                    .foregroundStyle(ink)
                            }
                            if let unit = metric.unit {
                                Text(unit).font(.imasFootnote.weight(.semibold)).foregroundStyle(ink2)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            HStack(alignment: .center, spacing: DS.Space.card) {
                media
                VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                    Text(title)
                        .font(ImasTextRole.cardTitle.font)
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.imasSubhead)
                            .foregroundStyle(ink2)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if onOpen != nil {
                    Image(systemName: "chevron.right")
                        .font(.imasScaled(13, weight: .semibold))
                        .foregroundStyle(ink2)
                }
            }
        }
        .padding(DS.Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 主役のカードの中の押せる所。押すと面が少し沈む (縮めない: カードの中の一部なので)。
private struct FeatureCardPressStyle: ButtonStyle {
    let pressedFill: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? pressedFill : Color.clear)
            .animation(.imasStandard, value: configuration.isPressed)
    }
}

// MARK: - 入口のカード

/// 奥の画面への入口を大きく見せる。一覧で十分なら `ImasNavRow`。
struct ImasEntryCard: View {
    let systemImage: String
    let title: String
    var preview: String? = nil
    var seed: String? = nil
    var brand: String? = nil
    /// 押してから外へ飛ぶまでの待ち。矢印をくるくるに替える。
    var isLoading: Bool = false

    @Environment(\.imasBackdrop) private var backdrop

    var body: some View {
        HStack(spacing: DS.Space.gapLoose) {
            ImasIconTile(systemImage: systemImage, size: .s32, tone: .solid, seed: seed, brand: brand)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).imasText(.cardTitle)
                if let preview {
                    Text(preview).imasText(.note).lineLimit(2)
                }
            }
            Spacer(minLength: DS.Space.gap)
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                ImasRowChevron()
            }
        }
        .padding(DS.Space.card)
        .background(DS.surface(on: backdrop), in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
    }
}

// MARK: - 数

/// 数 1 つ。上に記号 (実体の色)、その下に細長い太字の数と名前。奥へ行けるときは右上に矢印。
/// `ImasStatGrid` の中では面を持たず、外に単独で置くと自分で面を持つ。
struct ImasStatTile: View {
    var systemImage: String? = nil
    let value: String
    var unit: String? = nil
    let label: String
    var seed: String? = nil
    var brand: String? = nil
    var tappable: Bool = false

    @Environment(\.imasInStatGrid) private var inGrid
    @Environment(\.imasBackdrop) private var backdrop
    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: nil, env: envTheme, scheme: scheme)
        VStack(alignment: .leading, spacing: 4) {
            if systemImage != nil || tappable {
                HStack(alignment: .center) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.imasScaled(16, weight: .semibold))
                            .foregroundStyle(t.penlight)
                            .frame(height: 20)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                    if tappable {
                        Image(systemName: "chevron.right")
                            .font(.imasScaled(10, weight: .bold))
                            .foregroundStyle(DS.ink3)
                    }
                }
                .padding(.bottom, 2)
            }
            // 金額のように桁が伸びる値でも折り返さない (タイルの高さが揃わなくなる)。
            ImasMetric(value: value, unit: unit, size: .large)
            Text(label)
                .font(.imasCaption.weight(.semibold))
                .foregroundStyle(DS.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, inGrid ? DS.Space.gapLoose : DS.Space.card)
        .padding(.vertical, DS.Space.gapLoose)
        .background {
            if !inGrid {
                RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(DS.surface(on: backdrop))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 数を 1 枚の面に格子で並べる (記録・統計)。列は 2〜4。
struct ImasStatGrid<Content: View>: View {
    var columns: Int = 2
    @ViewBuilder var content: Content

    @Environment(\.imasBackdrop) private var backdrop

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: columns), spacing: 0) {
            content
        }
        .padding(DS.Space.gapTight)
        .environment(\.imasInStatGrid, true)
        .background(DS.surface(on: backdrop), in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
    }
}

private struct ImasInStatGridKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `ImasStatGrid` の中にいる (数が自分の面を持たない)。
    var imasInStatGrid: Bool {
        get { self[ImasInStatGridKey.self] }
        set { self[ImasInStatGridKey.self] = newValue }
    }
}

// MARK: - 割合の横棒

/// 項目ごとの割合 (ブランド別の回収率など)。
struct ImasStatBar: View {
    let label: String
    let value: String
    /// 0〜100。
    let percent: Double
    var seed: String? = nil
    var brand: String? = nil
    /// 右端の値の幅。金額のように桁が伸びる値は広げる。
    var valueWidth: CGFloat = 52

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        HStack(spacing: DS.Space.gapLoose) {
            HStack(spacing: 7) {
                ImasPenlight(color: t.penlight, size: .small)
                Text(label).font(.imasFootnote).foregroundStyle(DS.ink).lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(DS.fill)
                    Rectangle().fill(t.bar).frame(width: geo.size.width * min(1, max(0, percent / 100)))
                }
            }
            .frame(height: 6)
            Text(value)
                .font(ImasNumeralSize.small.font)
                .foregroundStyle(DS.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: valueWidth, alignment: .trailing)
        }
        .padding(.vertical, DS.Space.gap)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 割合の輪

/// 1 つの割合を大きく見せる輪 (回収率・習熟度)。中央に % を出す。
struct ImasProgressRing: View {
    /// 0〜1。
    let fraction: Double
    var size: CGFloat = 92
    var lineWidth: CGFloat = 8
    var seed: String? = nil
    var brand: String? = nil

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: nil, env: envTheme, scheme: scheme)
        let clamped = min(1, max(0, fraction))
        // % は切り捨て (100% は全部終わったときだけ)。規則はコア (`progress_percent`)。
        let percent = progressPercent(fraction: clamped)
        ZStack {
            Circle().stroke(DS.fill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(t.isNeutral ? DS.ink : t.bar, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Text("\(percent)%")
                .font(Font.imasScaled(size * 0.26, weight: .heavy).width(.compressed).monospacedDigit())
                .foregroundStyle(DS.ink)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(percent)パーセント")
    }
}

// MARK: - 入口のまとまり

/// 種類ごとの入口を見出し + 行のまとまりで見せる (あそぶ・みんな・しらべる)。
/// 中身は `ImasShortcutTile` (入口の行) を並べる。行の間の線は行が引き、1 行目の線はここで隠す。
struct ImasShortcutGroup<Accessory: View, Items: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var items: Items

    @Environment(\.imasBackdrop) private var backdrop
    @Environment(\.displayScale) private var displayScale

    init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder items: () -> Items) {
        self.title = title
        self.accessory = accessory()
        self.items = items()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.rCard, style: .continuous)
        VStack(alignment: .leading, spacing: DS.Space.header) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.gap) {
                Text(title).imasText(.sectionTitle)
                Spacer(minLength: DS.Space.gap)
                accessory
            }
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { items }
                .buttonStyle(.imasRow)
                // 各行は上に線を引く。1 行目の線 (面の上端) だけを隠す。
                .mask { Rectangle().padding(.top, 1 / displayScale) }
                .background(DS.surface(on: backdrop), in: shape)
                .clipShape(shape)
        }
    }
}

extension ImasShortcutGroup where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder items: () -> Items) {
        self.init(title, accessory: { EmptyView() }, items: items)
    }
}

/// 入口の行 1 つ (記号 + 名前 + 補足 + 矢印)。記号は実体の色 (無ければ墨)。押してから外へ飛ぶまでは くるくる。
struct ImasShortcutTile: View {
    let systemImage: String
    let label: String
    /// 名前の下の補足 (「つづきから Q.02」「開催中 3 件」)。
    var detail: String? = nil
    var seed: String? = nil
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: DS.Space.rowGap) {
            ImasIconTile(systemImage: systemImage, size: .s28, tone: .themed, seed: seed)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).imasText(.rowLabel).lineLimit(1)
                if let detail {
                    Text(detail).imasText(.rowSubtitle).lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.gap)
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                ImasRowChevron()
            }
        }
        .padding(.horizontal, DS.Space.rowH)
        .padding(.vertical, DS.Space.rowVCompact)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            ImasRowDivider(inset: DS.Space.rowH + ImasIconTile.Size.s28.rawValue + DS.Space.rowGap)
        }
    }
}

// MARK: - 横に流す

/// カードを横に流す。1 枚なら画面いっぱい、2 枚以上は次の 1 枚が少し見える幅にする。
struct ImasCarousel<Data: RandomAccessCollection, Card: View>: View where Data.Element: Identifiable {
    let data: Data
    @ViewBuilder let card: (Data.Element) -> Card

    var body: some View {
        if data.count <= 1 {
            ForEach(data) { card($0) }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DS.Space.gap) {
                    ForEach(data) { item in
                        card(item).containerRelativeFrame(.horizontal) { width, _ in width - 48 }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }
}
