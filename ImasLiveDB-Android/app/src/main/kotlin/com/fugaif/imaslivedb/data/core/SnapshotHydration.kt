package com.fugaif.imaslivedb.data.core

/**
 * スナップショット経路の共通ヘルパ (実体化と並び順の規約)。
 *
 * 共有コア (imas-core) の一覧クエリは「表示順の id 列」または列の欠けた射影を返す。
 * Room のエンティティにはコアが持たない派生列 (idols.voice_actors 等) があるため、
 * **実体は必ずローカル store (Room) から引き直す**のがコア移行の規約。
 * ここにはその引き直し (hydration) と、SQL の並びを再現するための比較器を置く。
 */

/** SQLite の既定バインド変数上限 999 に対する安全マージン込みのチャンク幅。 */
internal const val SQLITE_IN_CHUNK = 900

/**
 * コアが返した表示順の id 列を Room の実体へ引き直す。
 *
 * Room の `WHERE id IN (...)` は順序を保証しないので、並びと重複は **id 列が正**として
 * 並べ直す。id 列がバインド変数上限を跨いでも落ちないよう分割して引く。
 * 引き直せなかった id (同期直後でローカルにまだ無い等) は落とす。
 */
internal suspend fun <T> hydrateInOrder(
    ids: List<String>,
    idOf: (T) -> String,
    fetchChunk: suspend (List<String>) -> List<T>
): List<T> {
    if (ids.isEmpty()) return emptyList()
    val byId = HashMap<String, T>(ids.size)
    for (chunk in ids.distinct().chunked(SQLITE_IN_CHUNK)) {
        for (row in fetchChunk(chunk)) byId[idOf(row)] = row
    }
    return ids.mapNotNull { byId[it] }
}

/**
 * SQLite の BINARY 照合 (UTF-8 バイト列の符号なし比較) と厳密に一致する並び。
 *
 * Kotlin の `String.compareTo` は UTF-16 コード単位の比較で、サロゲート域
 * (絵文字等) の順序が SQL の `ORDER BY name` と食い違う。コア側でソートされていない
 * 集合を SQL 時代と同じ並びに戻すときはこれを使う。
 */
internal val SQLITE_BINARY_ORDER = Comparator<String> { a, b ->
    val x = a.toByteArray(Charsets.UTF_8)
    val y = b.toByteArray(Charsets.UTF_8)
    val n = minOf(x.size, y.size)
    for (i in 0 until n) {
        val d = (x[i].toInt() and 0xFF) - (y[i].toInt() and 0xFF)
        if (d != 0) return@Comparator d
    }
    x.size - y.size
}
