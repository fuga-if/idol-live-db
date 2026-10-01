import SwiftUI

// =============================================================================
// チップ (docs/DESIGN_SYSTEM.md §8.2)
//
// 用途      ImasChip         情報の小さな札 (押せない)。ブランド・種類・タグ
//           ImasFilterChip   押すと選択が切り替わる。絞り込み・カテゴリ・歌唱メンバーの予想
//           ImasRemovableChip 押すと外れる。効いている絞り込み・選んだもの
// 使わない  状態を示す小さい札 (参加済・ユニット・NEW) → ImasBadge /
//           操作のボタン → ImasButton
// 構成      [先頭 (記号・色の点・アバター、任意)] [文言] [× (Removable のみ)]
// 寸法      高さ 32 のカプセル、文字 14pt 中太、左右 12。画面で大きさを変えない。
// 状態      未選択 (灰の地) / 選択 (実体色の塗り) / 押下 / 無効 (薄く)
// 色        seed / brand / color を渡せばその色、何も渡さなければ環境の実体色 (`.imasTheme`)。
// =============================================================================

/// チップの先頭に置けるもの。
enum ImasChipLeading {
    /// SF Symbols の記号。
    case symbol(String)
    /// 色の点 (アイドル・ブランドの色)。
    case dot
    /// 小さいアバター (歌唱メンバーの予想など)。
    case avatar(label: String, imageURL: URL? = nil)
}

enum ImasChipStyle {
    /// 実体色の淡い地。情報の札に色を付けたいとき。
    case themed
    /// 実体色の塗り。選んだもの。
    case selected
    /// 灰の地。
    case neutral
}

/// 情報の小さな札 (押せない)。押せるようにするなら `ImasFilterChip`。
struct ImasChip: View {
    let text: String
    var systemImage: String? = nil
    var style: ImasChipStyle = .neutral
    var seed: String? = nil
    var brand: String? = nil
    /// 実体色そのもの (ユーザーが選んだタグ色等)。指定すると seed/brand より優先し、
    /// 素の色を塗らずに WCAG の計算を通す (どんな明るさでも文字が読める側に倒れる)。
    var color: Color? = nil
    /// グリッド内で幅を揃えたいとき true。
    var fillsWidth: Bool = false
    var leading: ImasChipLeading? = nil

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: color, env: envTheme, scheme: scheme)
        let (bg, fg) = ImasChipColors.colors(style: style, theme: t)
        HStack(spacing: 6) {
            ImasChipLeadingView(leading: leading ?? systemImage.map(ImasChipLeading.symbol), theme: t, onFill: style == .selected)
            Text(text)
                .font(ImasTextRole.chip.font)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: DS.Size.chip)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .foregroundStyle(fg)
        .background(bg, in: Capsule())
    }
}

/// 押して選択を切り替えるチップ。フィルタ・カテゴリ・種別・タグ・歌唱メンバーの予想の「唯一の正」。
///
/// 以前は画面ごとに 19 種の自前実装があり、角丸・フォント・余白がバラバラだった。
/// 見た目は `ImasChip` と同一で、押下と選択状態だけを足す。
struct ImasFilterChip: View {
    let text: String
    var systemImage: String? = nil
    let isSelected: Bool
    var seed: String? = nil
    var brand: String? = nil
    var color: Color? = nil
    var fillsWidth: Bool = false
    var isDisabled: Bool = false
    var leading: ImasChipLeading? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ImasChip(
                text: text,
                systemImage: systemImage,
                style: isSelected ? .selected : .neutral,
                seed: seed,
                brand: brand,
                color: color,
                fillsWidth: fillsWidth,
                leading: leading
            )
        }
        .buttonStyle(.imasPress)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 押すと外れるチップ。効いている絞り込み・選んだものを見せて、その場で外させる。
struct ImasRemovableChip: View {
    let text: String
    var seed: String? = nil
    var brand: String? = nil
    var leading: ImasChipLeading? = nil
    let onRemove: () -> Void

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: nil, env: envTheme, scheme: scheme)
        let accent: Color = t.isNeutral ? DS.sys : t.accent
        Button(action: onRemove) {
            HStack(spacing: 6) {
                ImasChipLeadingView(leading: leading, theme: t, onFill: false)
                Text(text).font(ImasTextRole.chip.font).lineLimit(1)
                Image(systemName: "xmark")
                    .font(.imasScaled(10, weight: .bold))
                    .opacity(0.8)
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(minHeight: DS.Size.chip)
            .foregroundStyle(accent)
            .background(accent.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.imasPress)
        .accessibilityLabel("\(text) を外す")
    }
}

// MARK: - 並べ方

/// チップを 1 段で横に並べ、はみ出したら横にスクロールする。2 段以上にはしない。
struct ImasChipRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.gap) { content }
                .padding(.horizontal, DS.Space.screen)
        }
        .scrollClipDisabled()
    }
}

/// チップを幅で折り返して並べる。
struct ImasChipFlow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        FlowLayout(spacing: DS.Space.gap) { content }
    }
}

// MARK: - 選択の印

/// ピッカー・複数選択の印。複数選択 = ○ と塗りの ✓、1 つ選択 = ✓ だけ。
/// 色は実体の accent (無ければ白黒)。
struct ImasSelectionMark: View {
    let isSelected: Bool
    var seed: String? = nil
    var brand: String? = nil
    var color: Color? = nil
    var size: CGFloat = 20
    /// 1 つだけ選ぶ一覧では ○ を出さず、選んだ行にだけ ✓ を出す。
    var isSingle: Bool = false

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: color, env: envTheme, scheme: scheme)
        let accent: Color = t.isNeutral ? DS.sys : t.accent
        Group {
            if isSingle {
                Image(systemName: "checkmark")
                    .font(.imasScaled(size * 0.8, weight: .bold))
                    .foregroundStyle(accent)
                    .opacity(isSelected ? 1 : 0)
            } else {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.imasScaled(size, weight: .regular))
                    .foregroundStyle(isSelected ? accent : DS.ink3)
            }
        }
        .frame(width: size + 4, height: size + 4)
        .accessibilityHidden(true)
    }
}

// MARK: - 受賞の札

/// 「みんなの投票」終了お題での順位。優勝 = 金の塗り、入賞 (2〜3 位) = 金の淡い地。
/// チップと同じ寸法で、曲詳細・アイドル詳細のヒーローに並べる。
struct ImasAwardChip: View {
    let title: String
    let rank: Int

    private var isWinner: Bool { rank == 1 }
    private var rankLabel: String { isWinner ? "優勝" : "第\(rank)位" }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isWinner ? "crown.fill" : "rosette")
                .font(.imasScaled(12, weight: .semibold))
            Text("\(title) \(rankLabel)")
                .font(ImasTextRole.chip.font)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: DS.Size.chip)
        .foregroundStyle(isWinner ? ColorMath.onColor(DS.favorite) : DS.warning)
        .background(isWinner ? AnyShapeStyle(DS.favorite) : AnyShapeStyle(DS.favorite.opacity(0.16)), in: Capsule())
        .accessibilityLabel("\(title) で\(rankLabel)")
    }
}

// MARK: - 内部

/// チップの先頭。
private struct ImasChipLeadingView: View {
    let leading: ImasChipLeading?
    let theme: ImasTheme
    /// 塗りの上に置くか (色の点は塗りと同じ色で消えるので白黒の輪にする)。
    let onFill: Bool

    var body: some View {
        switch leading {
        case .none:
            EmptyView()
        case .symbol(let name):
            Image(systemName: name).font(.imasScaled(13, weight: .semibold))
        case .dot:
            Circle()
                .fill(onFill ? theme.onAccent : theme.dot)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        case .avatar(let label, let url):
            ImasAvatar(label: label, seed: nil, size: 20, imageURL: url, reservesPickRing: false)
                .environment(\.imasTheme, theme)
                .padding(.leading, -6)
        }
    }
}

/// チップ家族の色の決め方 (明示の色 → seed/brand → 環境の実体色)。
enum ImasChipColors {
    static func theme(seed: String?, brand: String?, color: Color?, env: ImasTheme, scheme: ColorScheme) -> ImasTheme {
        if let color { return ImasTheme.derive(colorSeed: color, scheme: scheme) }
        if seed != nil || brand != nil { return ImasTheme.derive(seed: seed, brand: brand, scheme: scheme) }
        return env
    }

    static func colors(style: ImasChipStyle, theme t: ImasTheme) -> (bg: Color, fg: Color) {
        switch style {
        case .themed: return t.isNeutral ? (DS.fill, DS.ink2) : (t.chipBg, t.chipText)
        case .selected: return (t.actionFill, t.onActionFill)
        case .neutral: return (DS.fill, DS.ink2)
        }
    }
}
