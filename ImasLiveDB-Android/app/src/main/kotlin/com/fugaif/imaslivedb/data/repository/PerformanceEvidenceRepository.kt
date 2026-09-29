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
 * 集計はコアのスナップショットだけが答える (SQL の代わりの経路は持たない)。
 *
 * ## FFI / クエリの回数
 * 曲詳細を 1 回開くのに叩くコア呼び出しは **1 回だけ** (`songPerformanceInsights` が
 * 共起と歌唱者を束ねて返す)。行ごとには引かない。
 * コアは id しか返さないが、実体は Room から引き直す (`hydrateInOrder` の規約。
 * Room のエンティティにはコアが持たない派生列があるため)。
 */
class PerformanceEvidenceRepository(
    private val db: AppDatabase,
    private val snapshots: SnapshotStoreProvider
) {

    suspend fun fetchSongPerformanceEvidence(
        songId: String,
        coLimit: Int = CO_OCCURRING_DISPLAY_COUNT,
        singerLimit: Int = SINGER_DISPLAY_COUNT
    ): SongPerformanceEvidence {
        val co = coLimit.coerceAtLeast(0)
        val singer = singerLimit.coerceAtLeast(0)
        val raw = snapshots.query { store ->
            store.songPerformanceInsights(songId, co.toUInt(), singer.toUInt())
        }
        return assemble(
            coRows = raw.coOccurring.map { CoOccurrenceRow(it.songId, it.together.toInt()) },
            performances = raw.coOccurring.associate { it.songId to it.performances.toInt() },
            singerRows = raw.singers.map { SingerTallyRow(it.idolId, it.times.toInt(), it.total.toInt()) }
        )
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
