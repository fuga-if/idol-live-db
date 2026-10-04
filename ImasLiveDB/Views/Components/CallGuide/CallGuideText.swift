import CoreText
import SwiftUI
import UIKit

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
        /// いま編集中のアンカーか。確定済みのアンカー (淡く敷く) と見分けるため、
        /// 編集中はもっと濃く出す。同じ濃さだと「どれを今いじっているか」が消える。
        var isPending: Bool = false
        /// 歌詞と同じ文字の同時コール (一緒に叫ぶところ)。コールの行を出さない代わりに、敷く色を濃くして太字にする。
        var isEcho: Bool = false
    }

    /// アンカー範囲に色を敷いた行を組み立てる。
    ///
    /// `Text` の連結 (`Text(a) + Text(b)`) では背景色を付けられないので `AttributedString` を使う。
    /// 重なり合うアンカーは先勝ちで、後から来た重複部分は捨てる (両方描くと色が濁って
    /// どちらの範囲かが読めなくなるため)。
    /// 括弧で書いた脇の字 (被せ・歌わない字) は一段小さく薄くする (`asides: false` で止める。編集シート用)。
    static func attributed(_ text: String, highlights: [Highlight], asides: Bool = true) -> AttributedString {
        let scalars = Array(text.unicodeScalars)
        let owner = owners(count: scalars.count, highlights: highlights)
        let aside = asides ? ImasRubyText.asides(text) : [Bool](repeating: false, count: scalars.count)
        var result = AttributedString()
        var k = 0
        while k < scalars.count {
            let start = k
            let current = owner[k]
            while k < scalars.count, owner[k] == current, aside[k] == aside[start] { k += 1 }
            var segment = AttributedString(String(String.UnicodeScalarView(scalars[start..<k])))
            if aside[start] {
                segment.font = .imasFootnote
                segment.foregroundColor = DS.ink2
            }
            if let current {
                let highlight = highlights[current]
                var container = AttributeContainer()
                // 閲覧中のアンカーは本文の邪魔をしないよう薄く敷く。編集中のアンカー
                // (シートの「アンカー」欄) は**そこが主役**なので、はっきり出す。
                // 同じ濃さにすると、行の中のどこに掛かるのかが読み取れない。
                container.swiftUI.backgroundColor = highlight.color.opacity(opacity(highlight))
                if highlight.isPending || highlight.isEcho {
                    container.swiftUI.font = (aside[start] ? Font.imasFootnote : .imasBody).weight(.bold)
                }
                container.swiftUI.underlineStyle = .single
                segment.mergeAttributes(container)
            }
            result += segment
        }
        return result
    }

    /// 振り仮名のある行 (UILabel で描く)。アンカーの敷き方は `attributed` と同じ。
    static func rubyAttributed(_ text: String, highlights: [Highlight], font: UIFont, color: UIColor) -> NSAttributedString {
        let owner = owners(count: text.unicodeScalars.count, highlights: highlights)
        let bold = Font.imasScaledUIFont(17, weight: .bold)
        let asideBold = Font.imasScaledUIFont(13, weight: .bold)
        let aside = ImasRubyText.asides(text)
        return ImasRubyText.attributed(text, font: font, color: color, lineSpacing: 5,
                                       asideFont: Font.imasScaledUIFont(13), asideColor: UIColor(DS.ink2)) { k in
            guard let index = owner[k] else { return [:] }
            let highlight = highlights[index]
            var attrs: [NSAttributedString.Key: Any] = [
                .backgroundColor: UIColor(highlight.color.opacity(opacity(highlight))),
                NSAttributedString.Key(kCTUnderlineStyleAttributeName as String): CTUnderlineStyle.single.rawValue,
            ]
            if highlight.isPending || highlight.isEcho { attrs[.font] = aside[k] ? asideBold : bold }
            return attrs
        }
    }

    private static func opacity(_ highlight: Highlight) -> Double {
        highlight.isPending ? 0.55 : highlight.isEcho ? 0.32 : 0.18
    }

    /// 各スカラーがどのアンカーに入るか (重なりは先勝ち。後から来た重複部分は捨てる)。
    private static func owners(count: Int, highlights: [Highlight]) -> [Int?] {
        var owner = [Int?](repeating: nil, count: count)
        var cursor = 0
        for (index, highlight) in highlights.enumerated().sorted(by: { $0.element.start < $1.element.start }) {
            let start = max(highlight.start, cursor)
            let end = min(highlight.end, count)
            guard start < end else { continue }
            for k in start..<end { owner[k] = index }
            cursor = end
        }
        return owner
    }

    /// 同一行に複数のアンカーがあるときの対応付け記号 (①②③…)。
    /// 10 件を超えたら素の数字に落とす (丸数字は ⑳ までしか無い上に読みにくい)。
    static func anchorMarker(_ index: Int) -> String {
        let circled = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"]
        return index < circled.count ? circled[index] : "(\(index + 1))"
    }

    // MARK: - 指の位置 → 文字

    /// 指の位置に対応する書記素セルの添字。なぞって範囲を選ぶときの当たり判定。
    ///
    /// 素直に「矩形の中に入っているセル」を探すだけでは足りない。歌詞行は折り返すので
    ///   * 行間の隙間 (セルの縦の余白の外)
    ///   * 行末の余白 (最後の文字より右)
    /// に指がいる時間がそれなりにあり、そこで nil を返すと選択がガタつく。そこで
    /// **縦の帯 (どの折り返し行にいるか) を先に決めてから**、その行の中で最も近いセルに寄せる。
    /// 帯にも入っていなければ (行の上下にはみ出したら) 全セルから最短距離で選ぶ。
    ///
    /// `frames` は行内の同じ座標系で測ったセルの矩形 (セル添字 → 矩形)。
    static func cellIndex(at point: CGPoint, in frames: [Int: CGRect]) -> Int? {
        if let hit = frames.first(where: { $0.value.contains(point) })?.key { return hit }
        let sameRow = frames.filter { point.y >= $0.value.minY && point.y <= $0.value.maxY }
        let pool = sameRow.isEmpty ? frames : sameRow
        // 距離が並んだときに添字の小さい方を選ぶ (どのセルに寄るかを決定的にする)。
        return pool
            .min { lhs, rhs in
                let a = distance(point, lhs.value), b = distance(point, rhs.value)
                return a == b ? lhs.key < rhs.key : a < b
            }?.key
    }

    /// 点と矩形の距離。比較にしか使わないので平方根は取らない (矩形の中なら 0)。
    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

// MARK: - 折り返しレイアウト
//
// 編集モードの 1 文字セル並べと、凡例チップの折り返しは DS の `FlowLayout`
// (`DesignSystem/Components/ImasLayout.swift`) をそのまま使う (旧 `CallGuideFlowLayout`
// は引数名違いだけの重複実装だったため統合した)。
