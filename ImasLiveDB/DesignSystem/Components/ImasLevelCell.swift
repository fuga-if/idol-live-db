import SwiftUI

// =============================================================================
// 段階 1 マス (docs/DESIGN_SYSTEM.md §10.4)
//
// ImasLevelCell  習熟度の 1 曲・クイズの 1 項目のような「段階のマス」。未設定 (0) は
//                面を持たず点線の枠だけ。連続する割合なら `ImasMeter`、輪なら `ImasProgressRing`。
//                色の塗り分けは呼び出し側のドメイン (`MasteryPalette` など) に委ねる。
// =============================================================================

struct ImasLevelCell: View {
    let level: UInt8
    let steps: UInt8
    var size: CGFloat = 14
    /// 0 以外の段の塗り色。ドメインごとの段階の色 (習熟度の段階色など) を渡す。
    let fill: (UInt8, UInt8) -> Color

    init(level: UInt8, steps: UInt8, size: CGFloat = 14, fill: @escaping (UInt8, UInt8) -> Color) {
        self.level = level
        self.steps = steps
        self.size = size
        self.fill = fill
    }

    var body: some View {
        let radius: CGFloat = size > 10 ? 3 : 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return shape
            .fill(level == 0 ? Color.clear : fill(level, steps))
            .overlay { if level == 0 { shape.strokeBorder(DS.ink3, lineWidth: 1) } }
            .frame(width: size, height: size)
    }
}
