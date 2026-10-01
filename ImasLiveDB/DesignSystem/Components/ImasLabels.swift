import SwiftUI

// =============================================================================
// 札と数字 (docs/DESIGN_SYSTEM.md §10.1・§10.2)
//
// ImasBadge   状態の札 (押せない)。セトリの役割・参加済・受付中・NEW など。
//             高さ 20 のカプセル、11pt 太字。押せるものには使わない (押せるならチップ)。
// ImasMetric  数字 + 単位。数字はステージと同じ「細長い太字・等幅」。
// =============================================================================

struct ImasBadge: View {
    enum Kind: Hashable {
        // セトリの役割
        /// ユニット曲 (実体色の淡い地)。
        case unit
        /// 全員 (灰)。
        case all
        /// カバー (担当色の系統)。
        case cover
        /// 一部のメンバー (注意色)。
        case partial
        /// 主演 (実体色の塗り)。
        case lead
        /// ゲスト (線だけ)。
        case guest
        // 状態
        /// 参加済・当選・回収。
        case positive
        /// 受付中・締切間近・下書き。
        case attention
        /// 落選・中止・差し戻し。
        case negative
        /// 終了・未定・配信・LV。
        case neutral
        /// 新着 (実体色の塗り)。
        case new
        /// 実体色の淡い札 (タグの票数など、色で所属を示したい数)。
        case themed
    }

    let text: String
    var kind: Kind = .neutral
    var systemImage: String? = nil
    var seed: String? = nil
    var brand: String? = nil

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: nil, env: envTheme, scheme: scheme)
        let s = style(t)
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.imasScaled(9, weight: .bold))
            }
            Text(text).font(ImasTextRole.badge.font).monospacedDigit()
        }
        .lineLimit(1)
        .padding(.horizontal, 7)
        .frame(minHeight: DS.Size.badge)
        .foregroundStyle(s.fg)
        .background(s.bg, in: Capsule())
        .overlay { if let stroke = s.stroke { Capsule().strokeBorder(stroke, lineWidth: 1) } }
    }

    private func style(_ t: ImasTheme) -> (bg: Color, fg: Color, stroke: Color?) {
        let accent: Color = t.isNeutral ? DS.sys : t.accent
        switch kind {
        case .unit, .themed: return (accent.opacity(0.13), accent, nil)
        case .all, .neutral: return (DS.fill, DS.ink2, nil)
        case .cover: return (DS.pick.opacity(0.14), DS.pick, nil)
        case .partial, .attention: return (DS.warning.opacity(0.16), DS.warning, nil)
        case .lead, .new: return (t.actionFill, t.onActionFill, nil)
        case .guest: return (.clear, DS.ink2, DS.ink3)
        case .positive: return (DS.success.opacity(0.16), DS.successInk, nil)
        case .negative: return (DS.danger.opacity(0.14), DS.danger, nil)
        }
    }
}

/// 数字 + 単位。並べ替えの根拠・票・確率・回数・統計の値。
struct ImasMetric: View {
    let value: String
    var unit: String? = nil
    var size: ImasNumeralSize = .medium
    /// 実体色で強調する (1〜3 位など特別な少数だけ)。
    var emphasized: Bool = false

    @Environment(\.imasTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(size.font)
                .foregroundStyle(emphasized ? (theme.isNeutral ? DS.ink : theme.accent) : DS.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let unit, !unit.isEmpty {
                Text(unit)
                    .font(size.unitFont)
                    .foregroundStyle(DS.ink3)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 割合を行の下端などに細い線で示す (票・確率の大きさ)。数字を読まなくても差が分かる。
struct ImasProportionLine: View {
    /// 0〜1。
    let fraction: Double

    @Environment(\.imasTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.fill)
                Capsule()
                    .fill(theme.isNeutral ? DS.ink3 : theme.bar)
                    .frame(width: max(3, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
