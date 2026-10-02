import SwiftUI

// =============================================================================
// 詳細の頭 (docs/DESIGN_SYSTEM.md §2.2・§8.4)
//
// ImasHero      そのものの顔。アイコン (ジャケ) と、大きく組んだ名前。地は白い紙面。
//               曲は大きいジャケを中央に (`.centered`)、アイドル・ユニット・ライブ・公演は
//               アイコンを左・名前を右に (`.leading`)。同じ種類のものはいつも同じ形。
//               `.color` は地を実体の色で塗る (担当の顔など、色そのものを主役にする所)。
// ImasMarkBar   担当・お気に入り・参加・メモ・座席の印を横に並べる。
// ImasMarkTile  印 1 つ。丸いパンチ。ON は実体の色で塗られて点く (押すと判子の手応え)。
// ImasTabs      詳細・一覧の中の表示の切り替え。太い文字 + 実体の色の下線。
// ImasSegmented フォーム・設定の中で値を 1 つ選ぶ。墨で塗った札が動く。
// =============================================================================

/// 詳細の頭の地。
enum ImasHeroSurface {
    /// 白い紙面 (既定)。色はペンライトとアイコンの輪だけ。
    case paper
    /// 実体の色で塗る。文字は色の上で読める白か黒。
    case color
}

struct ImasHero<Media: View, Facts: View>: View {
    enum Layout {
        /// 画像を中央に大きく (曲)。
        case centered
        /// アイコンを左、名前を右 (アイドル・ユニット・ライブ・公演)。
        case leading
    }

    typealias Surface = ImasHeroSurface

    struct Action {
        let title: String
        var systemImage: String? = nil
        var isEnabled: Bool = true
        let action: () -> Void
    }

    var layout: Layout = .leading
    var surface: Surface = .paper
    /// 名前の上の小さい見出し (ブランド・種類)。前にペンライトが付く。
    var eyebrow: String? = nil
    /// 見出しを押したとき (ブランドで絞った一覧など)。nil なら押せない。
    var onEyebrowTap: (() -> Void)? = nil
    let title: String
    /// 名前の下 (CV・歌唱者・日付と会場)。
    var subtitle: String? = nil
    /// 主操作 1 つ (再生・出演ライブ・セトリを見る)。印は `UserMarkBar` に置く。
    var primary: Action? = nil
    @ViewBuilder var media: Media
    /// 名前の下の札の並び (全体曲・合同・受賞)。
    @ViewBuilder var facts: Facts

    @Environment(\.imasTheme) private var theme

    private var onColor: Bool { surface == .color && !theme.isNeutral }
    private var ink: Color { onColor ? theme.onAccent : DS.ink }
    private var ink2: Color { onColor ? theme.onAccent.opacity(0.78) : DS.ink2 }

    var body: some View {
        VStack(alignment: layout == .centered ? .center : .leading, spacing: DS.Space.card + 4) {
            switch layout {
            case .centered:
                VStack(spacing: DS.Space.card) {
                    media
                    texts(alignment: .center)
                }
                .frame(maxWidth: .infinity)
            case .leading:
                HStack(alignment: .center, spacing: DS.Space.card) {
                    media
                    texts(alignment: .leading)
                    Spacer(minLength: 0)
                }
            }
            if let primary {
                Button(action: primary.action) {
                    if let s = primary.systemImage { Label(primary.title, systemImage: s) } else { Text(primary.title) }
                }
                .buttonStyle(HeroButtonStyle(fill: onColor ? theme.onAccent : DS.sys,
                                             text: onColor ? theme.accent : DS.onSys))
                .disabled(!primary.isEnabled)
            }
        }
        .padding(.horizontal, DS.Space.screen)
        .padding(.top, onColor ? DS.Space.card + 4 : DS.Space.gapLoose)
        .padding(.bottom, DS.Space.card + 4)
        .frame(maxWidth: .infinity)
        .background(onColor ? theme.accent : DS.paper)
    }

    private func texts(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            if let eyebrow {
                let row = HStack(spacing: 7) {
                    Text(eyebrow)
                        .font(.imasFootnote.weight(.bold))
                        .foregroundStyle(ink2)
                        .lineLimit(1)
                }
                if let onEyebrowTap {
                    Button(action: onEyebrowTap) { row }.buttonStyle(.plain)
                } else {
                    row
                }
            }
            Text(title)
                .font(ImasTextRole.heroTitle.font)
                .foregroundStyle(ink)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.imasSubhead)
                    .foregroundStyle(ink2)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .lineLimit(2)
            }
            facts
                .padding(.top, DS.Space.gapTight)
        }
    }
}

extension ImasHero where Facts == EmptyView {
    init(layout: Layout = .leading, surface: Surface = .paper, eyebrow: String? = nil,
         onEyebrowTap: (() -> Void)? = nil, title: String,
         subtitle: String? = nil, primary: Action? = nil, @ViewBuilder media: () -> Media) {
        self.init(layout: layout, surface: surface, eyebrow: eyebrow, onEyebrowTap: onEyebrowTap, title: title,
                  subtitle: subtitle, primary: primary, media: media, facts: { EmptyView() })
    }
}

/// ヒーローの主操作 (幅いっぱい・高さ 50)。色の地の上では白黒を反転する。
private struct HeroButtonStyle: ButtonStyle {
    let fill: Color
    let text: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let size = ImasButtonSize.large
        let shape = RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
        configuration.label
            .font(size.font)
            .lineLimit(1)
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: size.height)
            .background(fill, in: shape)
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.imasStandard, value: configuration.isPressed)
    }
}

// MARK: - 印

/// 印 (`ImasMarkTile`) を横に並べる。主操作 (出演ライブ・試聴) を右端に置くときは `trailing`。
struct ImasMarkBar<Content: View>: View {
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if alignment == .center { Spacer(minLength: 0) }
            content
            Spacer(minLength: 0)
        }
    }
}

/// 担当・お気に入り・参加・メモ・座席の印 1 つ。丸いパンチと名前。
/// OFF = 線の丸に墨の記号、ON = 丸が実体の色で塗られて点く (ペンライトが点くように)。
/// `isAction` は印でなく操作 (出演ライブ・試聴) で、墨で塗った丸にする。
struct ImasMarkTile: View {
    let systemImage: String
    let label: String
    let isOn: Bool
    var isAction: Bool = false
    var accessibilityText: String? = nil
    let action: () -> Void

    @Environment(\.imasTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 50

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.imasScaled(19, weight: isOn || isAction ? .semibold : .regular))
                    .foregroundStyle(iconColor)
                    .symbolEffect(.bounce, value: isOn)
                    .frame(width: diameter, height: diameter)
                    .background {
                        if isOn || isAction {
                            Circle().fill(fill)
                        } else {
                            Circle().strokeBorder(DS.line, lineWidth: 1.5)
                        }
                    }
                Text(label)
                    .font(.imasCaption2.weight(.semibold))
                    .foregroundStyle(isOn ? DS.ink : DS.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(minWidth: diameter)
            .contentShape(Rectangle())
        }
        .buttonStyle(.imasPress)
        .sensoryFeedback(.impact(weight: .medium), trigger: isOn)
        .accessibilityLabel(accessibilityText ?? label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(.imasStandard, value: isOn)
    }

    private var fill: Color { isAction ? DS.sys : theme.penlight }
    private var iconColor: Color {
        if isAction { return DS.onSys }
        if isOn { return theme.isNeutral ? DS.onSys : theme.onAccent }
        return DS.ink
    }
}

// MARK: - 表示の切り替え (タブ)

/// 1 つの画面の中で表示を切り替える (詳細のタブ・今後/開催済み・セットリスト/予想)。
/// 文字を左から並べ、選んだものに下線。下線は実体の色 (無ければ墨)。
/// フォームで値を選ぶなら `ImasSegmented`、一覧を絞るなら `ImasFilterChip`。
struct ImasTabs<Selection: Hashable>: View {
    let options: [Selection]
    @Binding var selection: Selection
    let label: (Selection) -> String

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @Namespace private var namespace

    private let seed: String?
    private let brand: String?

    init(options: [Selection], selection: Binding<Selection>, seed: String? = nil, brand: String? = nil,
         label: @escaping (Selection) -> String) {
        self.options = options
        self._selection = selection
        self.label = label
        self.seed = seed
        self.brand = brand
    }

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: nil, env: envTheme, scheme: scheme)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(options, id: \.self) { option in
                    let on = option == selection
                    Button {
                        withAnimation(.imasStandard) { selection = option }
                    } label: {
                        Text(label(option))
                            .font(.imasHeading(16, weight: .heavy))
                            .foregroundStyle(on ? DS.ink : DS.ink3)
                            .lineLimit(1)
                            .padding(.vertical, 12)
                            .overlay(alignment: .bottom) {
                                if on {
                                    Capsule()
                                        .fill(t.penlight)
                                        .frame(height: 3)
                                        .matchedGeometryEffect(id: "underline", in: namespace)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
        .background(alignment: .bottom) {
            Rectangle().fill(DS.sep).frame(height: 1 / displayScale)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

extension ImasTabs where Selection == Int {
    init(labels: [String], selection: Binding<Int>, seed: String? = nil, brand: String? = nil) {
        self.init(options: Array(labels.indices), selection: selection, seed: seed, brand: brand) { labels[$0] }
    }
}

// MARK: - 値を 1 つ選ぶ (フォーム)

/// フォーム・設定の中で値を 1 つ選ぶ (期間・表示の単位・文字の大きさ)。
/// 薄い溝の上を、墨で塗った札が選んだ値へ動く。画面の中身を切り替えるなら `ImasTabs`。
struct ImasSegmented<Selection: Hashable>: View {
    let options: [Selection]
    @Binding var selection: Selection
    let label: (Selection) -> String

    @Namespace private var namespace
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 34

    init(options: [Selection], selection: Binding<Selection>, seed: String? = nil, brand: String? = nil,
         label: @escaping (Selection) -> String) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    withAnimation(.imasStandard) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.imasSubhead.weight(on ? .bold : .semibold))
                        .foregroundStyle(on ? DS.onSys : DS.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: height)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: DS.rControl(height) - 2, style: .continuous)
                                    .fill(DS.sys)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rControl(height + 6), style: .continuous))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

extension ImasSegmented where Selection == Int {
    init(labels: [String], selection: Binding<Int>, seed: String? = nil, brand: String? = nil) {
        self.init(options: Array(labels.indices), selection: selection) { labels[$0] }
    }
}
