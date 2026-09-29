package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.ui.search.CrossTabSearchCounts

/** 検索スコープ。UI 上の絞り込み単位 (iOS `UnifiedSearchScope` の移植)。 */
enum class SearchScope(val label: String, val prompt: String, val emptyNoun: String) {
    ALL("すべて", "ライブ・楽曲・アイドルを検索", "項目"),
    EVENTS("ライブ", "ライブ名 / 会場で検索", "ライブ"),
    SONGS("楽曲", "曲名で検索", "楽曲"),
    IDOLS("アイドル", "アイドル名 / CV名で検索", "アイドル")
}

/**
 * 各一覧の検索欄が出す「他のタブに N 件」の数え口。照合と数え方は共有コア (imas-core) が持つ。
 * (横断検索の画面は畳んだので、結果の実体を引く口は無い)
 */
class SearchRepository(private val snapshots: SnapshotStoreProvider) {

    /**
     * 打った語が種別ごとに何件当たるか (打ち切りなし)。
     *
     * 各一覧の検索欄が「他のタブに N 件」を出すために使う。実体は要らないので数だけ返す。
     * 上限で切らないのは、「20 件」と出しておいて実は 137 件ある、では移る判断の
     * 根拠にならないため。
     *
     * スナップショットの読み込みを待ってから数える。
     */
    suspend fun crossTabCounts(query: String): CrossTabSearchCounts =
        snapshots.query { store ->
            val c = store.searchCounts(query)
            CrossTabSearchCounts(
                songs = c.songs.toInt(), idols = c.idols.toInt(), events = c.events.toInt())
        }

    /**
     * 打った語がライブの「今後の予定」「開催済み」それぞれに何件あるか。
     *
     * 「ライブに N 件」から飛んだとき、当たりが過去のライブなのに既定の
     * 「今後の予定」へ着地すると 0 件の画面が出る。件数を見せて誘っておいて空を
     * 出すのは、この導線の趣旨に反するので、当たりのある側へ着地させる。
     */
    suspend fun eventSearchSides(query: String, todayKey: String): Pair<Int, Int> =
        snapshots.query { store ->
            val s = store.eventSearchSides(query, todayKey)
            s.upcoming.toInt() to s.past.toInt()
        }
}
