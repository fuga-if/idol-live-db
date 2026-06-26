import SwiftUI

/// アイドル詳細ヘッダ — イメージカラーのグラデーション背景
struct GradientHeader: View {
    let color: Color

    var body: some View {
        LinearGradient(
            colors: [color.opacity(0.6), color.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 120)
    }
}
