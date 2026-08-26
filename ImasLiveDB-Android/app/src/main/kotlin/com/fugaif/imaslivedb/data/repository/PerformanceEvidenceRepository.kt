package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.core.hydrateInOrder
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.CoOccurrenceRow
import com.fugaif.imaslivedb.data.model.CoOccurringSong
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.SingerTallyRow
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongPerformanceEvidence
import com.fugaif.imaslivedb.data.model.SongSingerTally

/**
 * 披露実績の集計 (共起曲 / 歌唱者) の読み取り口。iOS の
 * `CorePerformanceEvidenceRepository` と 1:1。
 *
 * ## 経路
 * スナップショットがあればコア、無ければ Room。他のリポジトリと同じフォールバック規約に
 * 従う。Android でスナップショットが無い局面は珍しくない —— ネイティブ .so 未同梱の
 * コントリビュータービルド、初回同期前 (Room がまだ DB ファイルを作っていない)、load 失敗
 * —— ので、フォールバックが無いと「そのビルドでは曲詳細に節が最初から存在しない」ことになる。
 *
 * 数え方は Room 経路も**コアと 1:1 に揃えてある** ([SongDao.fetchCoOccurringSongs] の注記)。
 * 経路で根拠の数字が変わるなら、根拠として出す意味が無い。
 *
 * ## FFI / クエリの回数
 * 曲詳細を 1 回開くのに叩くコア呼び出しは **1 回だけ** (`songPerformanceInsights` が
 * 共起と歌唱者を束ねて返す)。Room 経路も固定 4 クエリ。どちらも行ごとには引かない。
 * コアは id しか返さないが、実体は Room から引き直す (`hydrateInOrder` の規約。
 * Room のエンティティにはコアが持たない派生列があるため)。
 */
class PerformanceEvidenceRepository(
    private val db: AppDatabase,
    // null = スナップショット経路なし (テスト・ネイティブ未同梱ビルド)。Room 経路のみで動く。
    private val snapshots: SnapshotStoreProvider? = null
) {

    suspend fun fetchSongPerformanceEvidence(
        songId: String,
        coLimit: Int = CO_OCCURRING_DISPLAY_COUNT,
        singerLimit: Int = SINGER_DISPLAY_COUNT
    ): SongPerformanceEvidence {
        val co = coLimit.coerceAtLeast(0)
        val singer = singerLimit.coerceAtLeast(0)
        val raw = snapshots?.query { store ->
            store.songPerformanceInsights(songId, co.toUInt(), singer.toUInt())
        } ?: return fetchFromRoom(songId, co, singer)

        // コアの行を SQL 経路と同じ形に均してから組み立てる。両経路で組み立てを共有すれば、
        // 片方だけ並び順や分母の扱いが変わる余地が無くなる。
        return assemble(
            coRows = raw.coOccurring.map { CoOccurrenceRow(it.songId, it.together.toInt()) },
            performances = raw.coOccurring.associate { it.songId to it.performances.toInt() },
            singerRows = raw.singers.map { SingerTallyRow(it.idolId, it.times.toInt(), it.total.toInt()) }
        )
    }

    /** スナップショットが使えないときの Room 経路 (固定 4 クエリ)。 */
    private suspend fun fetchFromRoom(
        songId: String,
        coLimit: Int,
        singerLimit: Int
    ): SongPerformanceEvidence {
        val dao = db.songDao()
        val coRows =
            if (coLimit > 0) dao.fetchCoOccurringSongs(songId, coLimit) else emptyList<CoOccurrenceRow>()
        // 分母は上位が決まってから 1 回だけ引く (行ごとには引かない)。
        val performances = if (coRows.isEmpty()) {
            emptyMap<String, Int>()
        } else {
            dao.fetchSongShowCounts(coRows.map { it.songId }).associate { it.songId to it.cnt }
        }
        val singerRows =
            if (singerLimit > 0) dao.fetchSongSingerTallies(songId, singerLimit) else emptyList<SingerTallyRow>()
        return assemble(coRows, performances, singerRows)
    }

    /**
     * id 列 → Room 実体。id ごとに引かず 1 クエリ (チャンク分割) で解決する。
     * 引き直せなかった id (同期直後でローカルにまだ無い等) は落とす。回数だけあっても
     * 曲名/名前の無い行は読めない。集計が返した順 (回数の多い順) はそのまま保つ。
     */
    private suspend fun assemble(
        coRows: List<CoOccurrenceRow>,
        performances: Map<String, Int>,
        singerRows: List<SingerTallyRow>
    ): SongPerformanceEvidence {
        val songs = hydrateInOrder(coRows.map { it.songId }, Song::id) {
            db.songDao().fetchSongsByIds(it)
        }.associateBy { it.id }
        val idols = hydrateInOrder(singerRows.map { it.idolId }, Idol::id) {
            db.songDao().fetchIdolsByIds(it)
        }.associateBy { it.id }

        return SongPerformanceEvidence(
            coOccurring = coRows.mapNotNull { row ->
                songs[row.songId]?.let {
                    CoOccurringSong(
                        song = it,
                        together = row.together,
                        performances = performances[row.songId] ?: 0
                    )
                }
            },
            singers = singerRows.mapNotNull { row ->
                idols[row.idolId]?.let {
                    SongSingerTally(idol = it, times = row.times, total = row.total)
                }
            }
        )
    }

    companion object {
        /** 共起曲の表示件数。関連楽曲 (8 件) と同じ長さに揃える。 */
        const val CO_OCCURRING_DISPLAY_COUNT = 8
        /** 歌唱者の表示件数。全体曲は 50 人以上が歌っているので上位だけ出す。 */
        const val SINGER_DISPLAY_COUNT = 10
    }
}
