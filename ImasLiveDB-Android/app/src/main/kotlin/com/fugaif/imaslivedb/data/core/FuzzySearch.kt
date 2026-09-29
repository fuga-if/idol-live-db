package com.fugaif.imaslivedb.data.core

import android.util.Log
import uniffi.imas_core.fuzzyMatchesMulti

/**
 * あいまい一致 (「もしかして」) の口。iOS `FuzzySearchCatalog` と同じ役割。
 *
 * 本体は imas-core (Rust) の `domain/fuzzy_search.rs`。既存の検索は SQL の
 * `LIKE '%語%'` しか見ないので、打ち間違い・カタカナ/ひらがな・音引きの揺れは
 * そこで 0 件になる。編集距離で「だいたい合っている」候補を拾うのがこちら。
 *
 * ## なぜ綴りを 1 件につき複数渡すか
 * 編集距離は漢字とかなを寄せられない (「願」と「ねが」を同一視する術がない)。
 * 曲名だけを渡すと、ひらがなで打つ人は漢字の曲名に永久に当たらない。
 * `songs.title_kana` の読みを 2 本目の綴りとして併せて渡すことで
 * 「おねがいしんでれら」→「お願い！シンデレラ」が当たるようになる。
 *
 * ## 呼び出し規約
 * **1 回の検索 = 1 FFI 呼び出し**。全件ぶんの綴りを 1 回渡して、当たった項目の
 * 添字列を受け取る。呼び出し側は手元の配列を添字で引く (添字は「渡した配列の添字」
 * なので、綴り表と一覧の並びは必ず同じにすること)。
 */
object FuzzySearch {

    /** 部分一致がこれより多く当たっているときは「もしかして」を足さない。 */
    const val SUGGEST_THRESHOLD = 30

    /** 追加する候補の上限。 */
    const val LIMIT = 20

    private const val TAG = "FuzzySearch"

    // ネイティブライブラリが同梱されていないビルド (Rust 未ビルドのコントリビューター環境)
    // では uniffi の呼び出しがリンクエラーで落ちる。SnapshotStoreProvider と同じ流儀で
    // 「あいまい検索なし」に落として、部分一致だけで機能を失わずに動かす。
    @Volatile
    private var available = true

    /**
     * あいまい候補の添字を、**既に出ている添字を除いて**返す。
     *
     * コアは部分一致で拾えた件も `exact` として上位に返す。それらは呼び出し側で既に
     * 一覧に出ているので、その席のぶんだけ多めに引いてから間引く
     * (`limit` は並べ替えの後に効くため、素朴に `limit` だけ引くと全部が既出で埋まる)。
     */
    fun extraIndices(
        spellings: List<List<String>>,
        needle: String,
        shown: Set<Int>,
        limit: Int = LIMIT
    ): List<Int> {
        if (!available || spellings.isEmpty() || needle.isBlank() || limit <= 0) return emptyList()
        val hits = runCatching {
            fuzzyMatchesMulti(spellings, needle, (shown.size + limit).toUInt())
        }.onFailure {
            available = false
            Log.w(TAG, "あいまい検索が使えない → 部分一致のみで継続", it)
        }.getOrNull() ?: return emptyList()

        val extras = ArrayList<Int>(limit)
        for (hit in hits) {
            val index = hit.index.toInt()
            if (index in shown || index !in spellings.indices) continue
            extras.add(index)
            if (extras.size >= limit) break
        }
        return extras
    }
}
