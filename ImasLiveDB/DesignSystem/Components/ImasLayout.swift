import SwiftUI

/// 幅で折り返して並べる (チップ・歌唱者・タグ)。アプリで折り返しはこれ 1 つ。
///
/// 1 つが並べる幅より広いときは幅に収めて置く (中の文字は省略される)。以前は幅を
/// 測らずに置いていたので、長いライブ名のチップが画面の外へはみ出していた。
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    /// 行と行の間。nil なら `spacing` と同じ。
    var lineSpacing: CGFloat? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        let rowGap = lineSpacing ?? spacing
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
            }
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + rowGap
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
        }

        let width = maxWidth.isFinite ? maxWidth : usedWidth
        return (CGSize(width: width, height: y + rowHeight), frames)
    }
}
