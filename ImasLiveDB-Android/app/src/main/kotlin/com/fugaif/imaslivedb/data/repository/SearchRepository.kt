package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.core.FuzzySearch
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.core.hydrateInOrder
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.SearchResults
import com.fugaif.imaslivedb.data.model.Song

/** 検索スコープ。UI 上の絞り込み単位 (iOS `UnifiedSearchScope` の移植)。 */
enum class SearchScope(val label: String, val prompt: String, val emptyNoun: String) {
    ALL("すべて", "ライブ・楽曲・アイドルを検索", "項目"),
    EVENTS("ライブ", "ライブ名 / 会場で検索", "ライブ"),
    SONGS("楽曲", "曲名で検索", "楽曲"),
    IDOLS("アイドル", "アイドル名 / CV名で検索", "アイドル");

    /** このスコープで結果セクションを表示するか。 */
    fun includes(other: SearchScope): Boolean = this == ALL || this == other
}

/**
 * 横断検索。
 *
 * 「すべて」スコープの曲検索だけ共有コア (imas-core) の globalSearch を第一経路にしている。
 * 深い曲検索・ライブ検索・アイドル検索は、対応するコア API の条件が Android の仕様や
 * スキーマと食い違うので SQL 経路のまま (各メソッドのコメント参照)。
 */
class SearchRepository(
    private val db: AppDatabase,
    // null = スナップショット経路なし (テスト等)。その場合は常に SQL 経路。
    private val snapshots: SnapshotStoreProvider? = null,
    // 曲のあいまい一致 (「もしかして」) はここが持たず SongRepository に委ねる。
    // 曲一覧と同じ素を使わないと、同じ入力で画面ごとに違う候補が出る。
    private val songs: SongRepository = SongRepository(db, snapshots)
) {

    /**
     * スコープに応じた検索。「すべて」は3種を各20件、スコープ指定時は該当種別のみ深く引く。
     */
    suspend fun search(query: String, scope: SearchScope = SearchScope.ALL): SearchResults {
        return when (scope) {
            SearchScope.ALL -> {
                val hits = searchSongs(query, SHALLOW_LIMIT, deep = false)
                SearchResults(
                    songs = hits,
                    idols = searchIdols(query, SHALLOW_LIMIT),
                    events = searchEvents(query, SHALLOW_LIMIT),
                    fuzzySongs = fuzzySongs(query, hits, SHALLOW_LIMIT)
                )
            }
            SearchScope.SONGS -> {
                val hits = searchSongs(query, DEEP_LIMIT, deep = true)
                SearchResults(
                    songs = hits, idols = emptyList(), events = emptyList(),
                    fuzzySongs = fuzzySongs(query, hits, DEEP_LIMIT)
                )
            }
            SearchScope.IDOLS -> SearchResults(
                songs = emptyList(), idols = searchIdols(query, DEEP_LIMIT), events = emptyList()
            )
            SearchScope.EVENTS -> SearchResults(
                songs = emptyList(), idols = emptyList(), events = searchEvents(query, DEEP_LIMIT)
            )
        }
    }

    /**
     * 打った語では引けなかった曲を、あいまい一致で拾う (「もしかして」)。
     *
     * 打った通りに十分見つかっているときは足さない。既に 30 件出ている画面の末尾に
     * 候補を積んでも読まれず、一致の精度を疑わせるだけになる。
     *
     * 呼び出し元 (SearchViewModel) が 200ms の debounce を通しているので、打鍵ごとには走らない。
     */
    private suspend fun fuzzySongs(query: String, shown: List<Song>, exactLimit: Int): List<Song> {
        // 上限に張り付いた = まだ先があるということ。打った通りに出ているので候補は要らない。
        // (「すべて」は各 20 件までなので、件数だけ見ても「本当に少ない」か判別できない)
        if (shown.size >= exactLimit || shown.size > FuzzySearch.SUGGEST_THRESHOLD) return emptyList()
        val ids = songs.fuzzySongIds(query, shown.mapTo(HashSet()) { it.id })
        if (ids.isEmpty()) return emptyList()
        // 実体を引くのは当たった数十件だけ。並びはコアが返した順が正なので保って戻す。
        return hydrateInOrder(ids, Song::id) { db.songDao().fetchSongsByIds(it) }
    }

    /**
     * アイドル検索。**SQL 経路のまま残す。**
     *
     * コアの searchIdols は CV 名を idol_voice_actors テーブル経由でしか見ないが、
     * Android のスキーマに idol_voice_actors は無く、CV 名は idols.voice_actors
     * (カンマ区切りの1列) が持っている。コアへ寄せると「CV 名でアイドルを引く」という
     * このアプリの主要な探し方がヒットゼロになるため、Android に idol_voice_actors を
     * 載せる (= 同期対象に加える) までは SQL が正。
     * 名前/かな/ローマ字/別名・sort_order 順・limit の条件は両者一致している。
     */
    private suspend fun searchIdols(query: String, limit: Int): List<Idol> {
        return db.searchDao().searchIdols("%$query%", limit)
    }

    private suspend fun searchSongs(query: String, limit: Int, deep: Boolean): List<Song> {
        if (!deep) {
            // コアの globalSearch は曲について title/title_kana の部分一致・上限 20 件で、
            // Android の「すべて」スコープと同条件。上限が固定なので、200 件まで引く
            // 深いスコープ (楽曲タブ) には使えず、そちらは SQL のまま。
            snapshots?.query { store -> store.globalSearch(query).songIds }
                ?.let { return hydrateInOrder(it, Song::id) { ids -> db.songDao().fetchSongsByIds(ids) } }
        }
        return db.searchDao().searchSongs("%$query%", limit)
    }

    /**
     * ライブ検索は会場名 (shows.venue) 一致も含むのが Android の仕様。コアの globalSearch は
     * イベント名しか見ず、会場で探す動線が消えるため SQL 経路のまま
     * (会場一致は venuesMatching が別 API で、事前に event_id 集合を要求するので置換にならない)。
     */
    private suspend fun searchEvents(query: String, limit: Int) =
        db.searchDao().searchEvents("%$query%", limit)

    private companion object {
        const val SHALLOW_LIMIT = 20
        const val DEEP_LIMIT = 200
    }
}
