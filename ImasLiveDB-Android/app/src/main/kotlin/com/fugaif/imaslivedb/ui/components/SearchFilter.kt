package com.fugaif.imaslivedb.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import uniffi.imas_core.TextSearchCatalog

/**
 * 一覧・ピッカー共通の絞り込み。照合規則はコア (`domain/text_search_index.rs`) に一任する。
 *
 * 各画面で `lowercase().contains()` を書くと、**そこだけ かなを畳まない検索欄**ができる。
 * 実際にユニット一覧・各ピッカーがそうなっていて、曲一覧では「あるすとろめりあ」で
 * 当たるのにピッカーでは当たらない、という説明の付かない差になっていた。
 *
 * 索引は `items` が変わった時だけ組み直し、1 打鍵 = `matchingIndices` 1 回で済ませる
 * (項目ごとに FFI を跨がない)。並びは入力順のままなので、ブランド絞り込みのような
 * 別条件は前後どちらで掛けてもよい。
 *
 * @param spellings 1 項目ぶんの綴り列。読み・別名・CV など、引かせたい表記を全部入れる
 *                  (null は落とされる)。
 */
@Composable
fun <T> rememberSearchFiltered(
    items: List<T>,
    query: String,
    spellings: (T) -> List<String?>
): List<T> {
    val catalog = remember(items) {
        TextSearchCatalog(items.map { spellings(it).filterNotNull() })
    }
    // 索引の実体は Rust 側にある。items が入れ替わったら / 画面を離れたら明示的に返す。
    // Cleaner 任せでも最後には解放されるが、それは GC の都合で、いつかは決まらない。
    DisposableEffect(catalog) { onDispose { catalog.close() } }

    return remember(catalog, query) {
        val needle = query.trim()
        if (needle.isEmpty()) items
        else catalog.matchingIndices(needle).mapNotNull { items.getOrNull(it.toInt()) }
    }
}

/**
 * Compose の外 (ViewModel 等) から使う版。索引を使い捨てるので、
 * **打鍵ごとに呼ぶ用途には向かない**。数百件までの一覧で使うこと。
 */
fun <T> searchFiltered(items: List<T>, query: String, spellings: (T) -> List<String?>): List<T> {
    val needle = query.trim()
    if (needle.isEmpty()) return items
    return TextSearchCatalog(items.map { spellings(it).filterNotNull() }).use { catalog ->
        catalog.matchingIndices(needle).mapNotNull { items.getOrNull(it.toInt()) }
    }
}
