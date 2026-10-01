import SwiftUI

// =============================================================================
// ゲームの表彰台・対戦カード (docs/DESIGN_SYSTEM.md §12)
//
// ImasPodium        1〜3 位を強調する表彰台 (1 位中央大 + 2・3 位左右)。
//                    ソートメーカー・ティアー表の結果で使う (地は紙面のまま、QS は使わない)。
// ImasVersusBadge    「VS」の丸い印 (対戦カードの間)。
// .imasAccentCard    実体色の面をまとう選べるカード (対戦カードの縁・ティアー表のチップ)。
// =============================================================================

/// 1〜3 位を強調する表彰台。1 位を大きく中央に、2・3 位を横並びに出す。
struct ImasPodium: View {
    struct Entry: Identifiable {
        let id: String
        let rank: Int
        let title: String
        var subtitle: String? = nil
        var seed: String? = nil
        var brand: String? = nil
        let visual: AnyView
        let action: () -> Void
    }

    /// 1〜3 位ぶん (先頭が 1 位)。
    let entries: [Entry]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let first = entries.first {
            VStack(spacing: 12) {
                card(first, large: true)
                let rest = Array(entries.dropFirst().prefix(2))
                if !rest.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(rest) { card($0, large: false) }
                        if rest.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                    }
                }
            }
        }
    }

    private func card(_ entry: Entry, large: Bool) -> some View {
        let theme = ImasTheme.derive(seed: entry.seed, brand: entry.brand, scheme: scheme)
        return Button(action: entry.action) {
            VStack(spacing: 12) {
                ZStack(alignment: .topLeading) {
                    entry.visual
                    Text("\(entry.rank)")
                        .font(.imasScaled(large ? 22 : 16, weight: .black)).monospacedDigit()
                        .foregroundStyle(theme.onAccent)
                        .frame(minWidth: large ? 40 : 30, minHeight: large ? 40 : 30)
                        .background(theme.accent, in: Circle())
                        .overlay(Circle().strokeBorder(DS.surface, lineWidth: 3))
                        .offset(x: -10, y: -10)
                }
                VStack(spacing: 2) {
                    Text(entry.title)
                        .font(large ? ImasTextRole.cardTitle.font : ImasTextRole.rowTitle.font)
                        .foregroundStyle(DS.ink).multilineTextAlignment(.center).lineLimit(2)
                    if let sub = entry.subtitle {
                        Text(sub).imasText(.meta).lineLimit(1)
                    }
                }
            }
            .padding(large ? 24 : DS.Space.card)
            .frame(maxWidth: .infinity)
            .background(large ? theme.tint : DS.surface, in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.rank)位 \(entry.title)")
    }
}

/// 対戦カードの間に置く「VS」の丸い印。
struct ImasVersusBadge: View {
    var body: some View {
        Text("VS")
            .font(.imasScaled(13, weight: .black))
            .foregroundStyle(DS.onSys)
            .frame(width: 36, height: 36)
            .background(DS.sys, in: Circle())
            .overlay(Circle().strokeBorder(DS.bg, lineWidth: 3))
            .accessibilityHidden(true)
    }
}

// MARK: - 選べるカードの面

/// 選べるカードの飾り方。
enum ImasAccentCardStyle {
    /// 面カード (常に紙面、上に実体色の帯、選んだときだけ太い縁)。対戦カード。
    case card
    /// チップ (選んだときだけ実体色を薄く塗って縁取る)。ティアー表のチップ。
    case chip
}

private struct ImasAccentCardBackground: ViewModifier {
    var seed: String?
    var brand: String?
    var isSelected: Bool
    var style: ImasAccentCardStyle

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        let radius = style == .card ? DS.rCard : DS.rSM
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(fill(t), in: shape)
            .overlay { shape.strokeBorder(t.accent, lineWidth: isSelected ? (style == .card ? 3 : 2.5) : 0) }
            .overlay(alignment: .top) {
                if style == .card {
                    Capsule().fill(t.accent).frame(width: 36, height: 4).padding(.top, 6)
                }
            }
    }

    private func fill(_ t: ImasTheme) -> Color {
        switch style {
        case .card: return DS.surface
        case .chip: return isSelected ? t.tint : .clear
        }
    }
}

extension View {
    /// 実体色の面をまとう選べるカード (対戦カードの上の帯・ティアー表のチップの縁)。
    func imasAccentCard(seed: String? = nil, brand: String? = nil, isSelected: Bool = false,
                        style: ImasAccentCardStyle = .card) -> some View {
        modifier(ImasAccentCardBackground(seed: seed, brand: brand, isSelected: isSelected, style: style))
    }
}
