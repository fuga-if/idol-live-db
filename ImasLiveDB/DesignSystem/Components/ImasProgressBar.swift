import SwiftUI

// =============================================================================
// ラベル無しの線形プログレス (docs/DESIGN_SYSTEM.md §10.4)
//
// ImasProgressBar  0〜1 の割合を細い線で見せる (対戦の進み具合・つづきからの達成率)。
//                  ラベル付きの内訳なら `ImasStatBar`、輪なら `ImasProgressRing`。
// =============================================================================

struct ImasProgressBar: View {
    /// 0〜1。
    let fraction: Double
    var seed: String? = nil
    var brand: String? = nil

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: nil, env: envTheme, scheme: scheme)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.fill)
                Capsule()
                    .fill(t.isNeutral ? DS.sys : t.bar)
                    .frame(width: max(6, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: fraction)
        .accessibilityElement()
        .accessibilityLabel("\(Int((fraction * 100).rounded()))パーセント")
    }
}
