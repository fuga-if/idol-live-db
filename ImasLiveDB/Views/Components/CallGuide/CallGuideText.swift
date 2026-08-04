import SwiftUI

// =============================================================================
// コールガイドの文字位置まわり
//
// ⚠️ アンカーの `start` / `end` は **Unicode スカラー単位**のオフセット。
// Swift の `String.Index` と行き来するときは必ず `String.unicodeScalars` を基準に数える。
// UTF-16 (`NSRange` / `String.utf16`) と混同すると、サロゲートペア (絵文字) や
// 結合文字を含む行でアンカーが 1〜2 文字ズレる。サーバ (Worker) 側も同じスカラー基準。
// =============================================================================

enum CallGuideText {

    /// 行内の 1 書記素クラスタ。編集モードの範囲選択はこの粒度でしか選ばせない
    /// (スカラー単位で選ばせると濁点や絵文字の途中で切れてしまう)。
    struct Cell: Identifiable, Hashable {
        /// 行内での並び順。選択範囲の比較にそのまま使う。
        let id: Int
        let text: String
        /// この書記素クラスタが占めるスカラー範囲 (`start` は含む / `end` は含まない)。
        let scalarStart: Int
        let scalarEnd: Int
    }

    /// 行を書記素クラスタに割り、それぞれのスカラー範囲を添えて返す。
    static func cells(of text: String) -> [Cell] {
        var result: [Cell] = []
        var scalarOffset = 0
        for (index, character) in text.enumerated() {
            let width = character.unicodeScalars.count
            result.append(Cell(id: index,
                               text: String(character),
                               scalarStart: scalarOffset,
                               scalarEnd: scalarOffset + width))
            scalarOffset += width
        }
        return result
    }

    /// 行の総スカラー数。
    static func scalarCount(of text: String) -> Int { text.unicodeScalars.count }

    /// スカラー範囲を切り出す。範囲外・逆転は nil (壊れたアンカーを描かないため)。
    static func slice(_ text: String, start: Int, end: Int) -> String? {
        let scalars = Array(text.unicodeScalars)
        guard start >= 0, end <= scalars.count, start < end else { return nil }
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }

    /// 行内で強調表示するアンカー 1 件。
    struct Highlight {
        let start: Int
        let end: Int
        let color: Color
    }

    /// アンカー範囲に色を敷いた行を組み立てる。
    ///
    /// `Text` の連結 (`Text(a) + Text(b)`) では背景色を付けられないので `AttributedString` を使う。
    /// 重なり合うアンカーは先勝ちで、後から来た重複部分は捨てる (両方描くと色が濁って
    /// どちらの範囲かが読めなくなるため)。
    static func attributed(_ text: String, highlights: [Highlight]) -> AttributedString {
        let scalars = Array(text.unicodeScalars)
        var result = AttributedString()
        var cursor = 0
        for highlight in highlights.sorted(by: { $0.start < $1.start }) {
            let start = max(highlight.start, cursor)
            let end = min(highlight.end, scalars.count)
            guard start < end else { continue }
            if start > cursor {
                result += AttributedString(String(String.UnicodeScalarView(scalars[cursor..<start])))
            }
            var segment = AttributedString(String(String.UnicodeScalarView(scalars[start..<end])))
            var container = AttributeContainer()
            container.swiftUI.backgroundColor = highlight.color.opacity(0.18)
            container.swiftUI.underlineStyle = .single
            segment.mergeAttributes(container)
            result += segment
            cursor = end
        }
        if cursor < scalars.count {
            result += AttributedString(String(String.UnicodeScalarView(scalars[cursor...])))
        }
        return result
    }

    /// 同一行に複数のアンカーがあるときの対応付け記号 (①②③…)。
    /// 10 件を超えたら素の数字に落とす (丸数字は ⑳ までしか無い上に読みにくい)。
    static func anchorMarker(_ index: Int) -> String {
        let circled = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"]
        return index < circled.count ? circled[index] : "(\(index + 1))"
    }
}

// MARK: - 折り返しレイアウト

/// 幅に収まらなくなったら次の行に送る、素朴なフロー配置。
///
/// 編集モードの 1 文字セル並べと、凡例チップの折り返しに使う。`LazyVGrid` は列数固定
/// なので文字幅がバラバラな (全角/半角混在の) セルには使えない。
struct CallGuideFlowLayout: Layout {
    var itemSpacing: CGFloat = 0
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                widest = max(widest, x - itemSpacing)
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + itemSpacing
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, x - itemSpacing)
        return CGSize(width: maxWidth.isFinite ? maxWidth : max(widest, 0), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(size))
            x += size.width + itemSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
