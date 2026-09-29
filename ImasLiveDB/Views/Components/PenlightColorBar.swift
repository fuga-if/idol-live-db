import SwiftUI

/// 複数のペンライト色を横並びの帯で表示するコンポーネント
struct PenlightColorBar: View {
    let colors: [String]
    var height: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let w = colors.isEmpty ? 0 : geo.size.width / CGFloat(colors.count)
            HStack(spacing: 0) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, hex in
                    Rectangle()
                        .fill(Color(hexString: hex, default: .gray))
                        .frame(width: w, height: height)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .combine)
        // 読み上げの文 (「ペンライト: 2色 ピンク、白」) はコアが組む。
        .accessibilityLabel(penlightAccessibilityLabel(hexes: colors))
    }
}
