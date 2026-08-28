package com.fugaif.imaslivedb.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import com.fugaif.imaslivedb.data.core.TextSearch
import com.fugaif.imaslivedb.ui.theme.ImasTheme

/** iOS の `.opacity(0.28)` と同値。文字が読める濃さで、かつ当たった箇所が拾える濃さ。 */
private const val HIGHLIGHT_ALPHA = 0.28f

/**
 * 絞り込み語に当たった部分へ色を敷いた文字列を作る (iOS `SongRowView.highlighted(_:in:)` 相当)。
 *
 * 「何で引っかかったか」の示し方が画面ごとに違うと、同じ一覧なのに読み方を切り替えることに
 * なる。どの行でも「当たった箇所に同じ色を敷く」に揃えるため、色と組み立てはここ 1 箇所に置く。
 *
 * 当たらない語 (漢字の曲名を読み仮名で引いた場合など、表記側に範囲が無いとき) や
 * 絞り込んでいないときは素の文字列を返す。判定は [TextSearch] = コアの照合そのものに任せる。
 *
 * @param needle 絞り込み語。null / 空白のみなら色を敷かない。
 */
@Composable
fun rememberHighlighted(source: String, needle: String?): AnnotatedString {
    val trimmed = needle?.trim().orEmpty()
    // 行のブランド色ではなく無彩シードのアクセント。ハイライトは「当たった箇所」を示す印で
    // あって、行の帰属を示す色ではない (ブランド色だとリードバーと意味が混ざる)。
    val accent = ImasTheme.derive(seed = null, dark = true).accent
    return remember(source, trimmed, accent) {
        val span = trimmed.takeIf { it.isNotEmpty() }?.let { TextSearch.matchRange(source, it) }
        if (span == null) {
            AnnotatedString(source)
        } else {
            buildAnnotatedString {
                append(source)
                addStyle(SpanStyle(background = accent.copy(alpha = HIGHLIGHT_ALPHA)), span.start, span.end)
            }
        }
    }
}
