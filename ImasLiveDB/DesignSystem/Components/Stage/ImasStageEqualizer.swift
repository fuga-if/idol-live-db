import SwiftUI

// =============================================================================
// ステージの再生インジケータ (docs/DESIGN_SYSTEM.md §12)
//
// ImasStageEqualizer  「再生中」を示す音楽ビジュアライザー (N 列 × M 行のバーが明滅)。
//                      イントロドンの `IDEQAnimation` を DS 部品として昇格したもの。
// =============================================================================

struct ImasStageEqualizer: View {
    var columns: Int = 16
    var rows: Int = 5
    var dotSize: CGFloat = 10
    var spacing: CGFloat = 3
    var interval: TimeInterval = 0.6
    var color: Color = QS.ink
    var isAnimating: Bool = true

    private static let baseHeights = [2, 3, 4, 2, 5, 3, 4, 5, 3, 5, 4, 2, 5, 3, 2, 3]

    @State private var heights: [Int] = baseHeights
    @State private var timer: Timer?

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { col in
                VStack(spacing: spacing) {
                    ForEach((0..<rows).reversed(), id: \.self) { row in
                        Rectangle()
                            .fill(color)
                            .frame(width: dotSize, height: dotSize)
                            .opacity(row < heights[col % heights.count] ? 0.85 : 0.12)
                    }
                }
            }
        }
        .frame(height: CGFloat(rows) * (dotSize + spacing) + spacing)
        .animation(.easeInOut(duration: 0.4), value: heights)
        .onAppear { refreshTimer() }
        .onChange(of: isAnimating) { _, _ in refreshTimer() }
        .onDisappear { timer?.invalidate() }
        .accessibilityHidden(true)
    }

    private func refreshTimer() {
        timer?.invalidate()
        timer = nil
        if isAnimating {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                Task { @MainActor in
                    var h = heights
                    for i in 0..<h.count {
                        let variation = Int.random(in: -1...1)
                        h[i] = max(1, min(rows, Self.baseHeights[i % Self.baseHeights.count] + variation))
                    }
                    heights = h
                }
            }
        } else {
            heights = Array(repeating: 1, count: columns)
        }
    }
}
