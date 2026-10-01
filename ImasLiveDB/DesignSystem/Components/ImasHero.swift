import SwiftUI

// =============================================================================
// 詳細の頭 (docs/DESIGN_SYSTEM.md §2.2・§8.4)
//
// ImasHero      そのものの顔。画像・名前・要点・主操作 1 つ。地は実体色 (`heroSurface`)。
//               曲は大きいジャケを中央に (`.centered`)、アイドル・ユニット・ライブ・公演は
//               左に画像・右に名前 (`.leading`)。同じ種類のものはいつも同じ形。
// ImasMarkTile  担当・お気に入り・参加・メモ・座席の印のタイル。`UserMarkBar` が横に並べる。
// ImasTabs      詳細の中の表示の切り替え (2〜4 個)。
// =============================================================================

struct ImasHero<Media: View, Facts: View>: View {
    enum Layout {
        /// 画像を中央に大きく (曲)。
        case centered
        /// 画像を左、名前を右 (アイドル・ユニット・ライブ・公演)。
        case leading
    }

    struct Action {
        let title: String
        var systemImage: String? = nil
        var isEnabled: Bool = true
        let action: () -> Void
    }

    var layout: Layout = .leading
    /// 名前の上の小さい見出し (ブランド・種類)。
    var eyebrow: String? = nil
    let title: String
    /// 名前の下 (CV・歌唱者・日付と会場)。
    var subtitle: String? = nil
    /// 主操作 1 つ (再生・出演ライブ・セトリを見る)。印は `UserMarkBar` に置く。
    var primary: Action? = nil
    @ViewBuilder var media: Media
    /// 名前の下の札の並び (全体曲・合同・受賞)。
    @ViewBuilder var facts: Facts

    @Environment(\.imasTheme) private var theme

    var body: some View {
        VStack(alignment: layout == .centered ? .center : .leading, spacing: DS.Space.card) {
            switch layout {
            case .centered:
                VStack(spacing: DS.Space.gapLoose) {
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
                .buttonStyle(.imas(.primary, size: .medium, fillsWidth: true))
                .disabled(!primary.isEnabled)
            }
        }
        .padding(.horizontal, DS.Space.screen)
        .padding(.top, DS.Space.gapLoose)
        .padding(.bottom, DS.Space.card)
        .frame(maxWidth: .infinity)
        .background(theme.isNeutral ? DS.bg : theme.heroSurface)
    }

    private func texts(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: DS.Space.gapTight) {
            if let eyebrow {
                Text(eyebrow)
                    .font(ImasTextRole.eyebrow.font)
                    .foregroundStyle(theme.isNeutral ? DS.ink2 : theme.accent)
            }
            Text(title)
                .font(ImasTextRole.heroTitle.font)
                .foregroundStyle(DS.ink)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .imasText(.rowSubtitle)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .lineLimit(2)
            }
            facts
                .padding(.top, DS.Space.gapTight)
        }
    }
}

extension ImasHero where Facts == EmptyView {
    init(layout: Layout = .leading, eyebrow: String? = nil, title: String, subtitle: String? = nil,
         primary: Action? = nil, @ViewBuilder media: () -> Media) {
        self.init(layout: layout, eyebrow: eyebrow, title: title, subtitle: subtitle, primary: primary,
                  media: media, facts: { EmptyView() })
    }
}

// MARK: - 印のタイル

/// 担当・お気に入り・参加・メモ・座席の印 1 つ。等幅で横に並べる。
/// OFF = 白い面 + 実体色の記号、ON = 実体色の塗り。
struct ImasMarkTile: View {
    let systemImage: String
    let label: String
    let isOn: Bool
    var accessibilityText: String? = nil
    let action: () -> Void

    @Environment(\.imasTheme) private var theme

    private static var radius: CGFloat { min(DS.rCard, 16) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.imasScaled(18, weight: .semibold))
                    .symbolEffect(.bounce, value: isOn)
                Text(label)
                    .font(.imasCaption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? theme.onActionFill : (theme.isNeutral ? DS.ink : theme.chipText))
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(isOn ? theme.actionFill : DS.surface,
                        in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        }
        .buttonStyle(.imasPress)
        .sensoryFeedback(.impact(weight: .light), trigger: isOn)
        .accessibilityLabel(accessibilityText ?? label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(.imasStandard, value: isOn)
    }
}

// MARK: - 中身の切り替え

/// 1 つの画面の中で表示を切り替える (詳細のタブ・月/週・今後/開催済み)。2〜4 個、文言は全角 6 文字まで。
/// 一覧を絞るなら `ImasFilterChip`、別の画面へ行くなら `ImasNavRow`。
struct ImasSegmented<Selection: Hashable>: View {
    let options: [Selection]
    @Binding var selection: Selection
    let label: (Selection) -> String

    init(options: [Selection], selection: Binding<Selection>, seed: String? = nil, brand: String? = nil,
         label: @escaping (Selection) -> String) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    withAnimation(.imasStandard) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.imasSubhead.weight(.semibold))
                        .foregroundStyle(on ? DS.ink : DS.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background {
                            if on {
                                Capsule()
                                    .fill(DS.surface)
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(DS.fill, in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}

extension ImasSegmented where Selection == Int {
    init(labels: [String], selection: Binding<Int>, seed: String? = nil, brand: String? = nil) {
        self.init(options: Array(labels.indices), selection: selection) { labels[$0] }
    }
}

/// デザインシステムの呼び名。`ImasSegmented` と同じもの。
typealias ImasTabs = ImasSegmented
