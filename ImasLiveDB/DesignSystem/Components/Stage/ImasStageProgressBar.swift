import SwiftUI

// =============================================================================
// ステージの線メーター (docs/DESIGN_SYSTEM.md §12)
//
// ImasStageProgressBar  ペンライトが 20 本を超える・総数が決まらないときの進捗の線。
//                        イントロドンのラッシュ (残り時間) ・全曲チャレンジ (進んだ量) で使う。
// =============================================================================

/// ペンライトの代わりに使う細い線メーター。
struct ImasStageProgressBar: View {
    /// 0〜1。
    let fraction: Double
    /// 残りわずか・緊急のときに朱へ替える。
    var isUrgent: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(QS.raised)
                Capsule()
                    .fill(isUrgent ? QS.stamp : QS.ink)
                    .frame(width: max(4, geo.size.width * min(1, max(0, fraction))))
                    .animation(.linear(duration: 0.15), value: fraction)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("\(Int((fraction * 100).rounded()))パーセント")
    }
}
