import SwiftUI

/// 絞り込み語に当たった部分へ色を敷いた文字列を作る (Android `rememberHighlighted` と 1:1)。
///
/// 「何で引っかかったか」の示し方が画面ごとに違うと、同じ結果なのに読み方を切り替えることに
/// なる。どの行でも「当たった箇所に同じ色を敷く」に揃えるため、色と組み立てはここ 1 箇所に置く。
///
/// 当たらない語 (漢字の曲名を読み仮名で引いた場合など、表記側に範囲が無いとき) や
/// 絞り込んでいないときは素の文字列を返す。一致判定は `String.searchMatchRange(of:)`
/// = コアの照合そのものに任せる (照合規則を二重に持たない)。
enum SearchHighlight {
    /// 文字が読める濃さで、かつ当たった箇所が拾える濃さ。
    private static let alpha: Double = 0.28

    /// - Parameter needle: 絞り込み語。nil / 空白のみなら色を敷かない。
    static func attributed(_ source: String, matching needle: String?,
                           scheme: ColorScheme) -> AttributedString {
        // 絞り込んでいない行が大半なので、`AttributedString` を組む前に降りる。
        let trimmed = needle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, let range = source.searchMatchRange(of: trimmed) else {
            return AttributedString(source)
        }
        var text = AttributedString(source)
        guard let from = AttributedString.Index(range.lowerBound, within: text),
              let to = AttributedString.Index(range.upperBound, within: text)
        else { return text }
        // 行のブランド色ではなく無彩シードのアクセント。ハイライトは「当たった箇所」を示す
        // 印であって、行の帰属を示す色ではない (ブランド色だとリードバーと意味が混ざる)。
        text[from ..< to].backgroundColor =
            ImasTheme.derive(seed: nil, scheme: scheme).accent.opacity(alpha)
        return text
    }
}
