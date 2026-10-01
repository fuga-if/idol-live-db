import SwiftUI

// =============================================================================
// 札と数字 (docs/DESIGN_SYSTEM.md §10.1・§10.2)
//
// ImasBadge   状態の札 (押せない)。セトリの役割・参加済・受付中・NEW など。
//             高さ 20 の角の小さい四角 (角丸 4)、11pt 太字。押せるものには使わない。
//             色で意味を分けない: 線 (分類) / 墨 (予定・主演) / 朱の線 (済んだ記録) / 朱 (新着) だけ。
//             札ごとに色を変えると淡い色の札が並ぶ「よくある見た目」になる。意味は文字が言う。
//             チケットの印字のように、塗らずに細い線で囲むのが基本。
// ImasMetric  数字 + 単位。数字はステージと同じ「細長い太字・等幅」。
// =============================================================================

struct ImasBadge: View {
    enum Kind: Hashable {
        // セトリの役割 (分類なので灰)
        /// ユニット曲。
        case unit
        /// 全員。
        case all
        /// カバー。
        case cover
        /// 一部のメンバー。
        case partial
        /// 主演 (墨)。
        case lead
        /// ゲスト (線)。
        case guest
        // 状態
        /// 参加済・当選・回収 (朱の線。判子を押した記録)。
        case positive
        /// 参加予定・チケットあり (墨の塗り。手元にある券)。
        case planned
        /// 受付中・締切間近・下書き (墨の線)。
        case attention
        /// 落選・中止・差し戻し (灰の薄字)。
        case negative
        /// 終了・未定・配信・LV (灰)。
        case neutral
        /// 新着 (赤)。
        case new
        /// 実体の色の線 (タグの票数など、色で所属を示したい数)。
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
        let shape = RoundedRectangle(cornerRadius: DS.rTag, style: .continuous)
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.imasScaled(9, weight: .heavy))
            }
            Text(text).font(ImasTextRole.badge.font).monospacedDigit()
        }
        .lineLimit(1)
        .padding(.horizontal, 6)
        .frame(minHeight: DS.Size.badge)
        .foregroundStyle(s.fg)
        .background(s.bg, in: shape)
        .overlay { if let stroke = s.stroke { shape.strokeBorder(stroke, lineWidth: 1) } }
    }

    private func style(_ t: ImasTheme) -> (bg: Color, fg: Color, stroke: Color?) {
        switch kind {
        case .unit, .all, .cover, .partial, .neutral: return (.clear, DS.ink2, DS.line)
        case .lead, .planned: return (DS.sys, DS.onSys, nil)
        case .positive: return (.clear, DS.stamp, DS.stamp)
        case .new: return (DS.stamp, .white, nil)
        case .attention: return (.clear, DS.ink, DS.ink)
        case .guest: return (.clear, DS.ink2, DS.line)
        case .negative: return (.clear, DS.ink3, DS.sep)
        case .themed:
            let c: Color = t.isNeutral ? DS.ink : t.accent
            return (.clear, c, c.opacity(0.55))
        }
    }
}

/// 数字 + 単位。並べ替えの根拠・票・確率・回数・統計の値。
struct ImasMetric: View {
    let value: String
    var unit: String? = nil
    var size: ImasNumeralSize = .medium
    /// 強調する (1〜3 位・0 でない値など)。強調は墨、そうでなければ灰。色では飾らない。
    var emphasized: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(size.font)
                .foregroundStyle(emphasized || size == .large ? DS.ink : DS.ink2)
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
                Rectangle().fill(DS.fill)
                Rectangle()
                    .fill(theme.isNeutral ? DS.ink : theme.bar)
                    .frame(width: max(2, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}
