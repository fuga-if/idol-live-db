package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.core.hydrateInOrder
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.CoOccurringSong
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongPerformanceEvidence
import com.fugaif.imaslivedb.data.model.SongSingerTally

/**
 * 披露実績の集計 (共起曲 / 歌唱者) の読み取り口。iOS の
 * `CorePerformanceEvidenceRepository` と 1:1。
 *
 * 他のリポジトリと違い **Room へのフォールバックを持たない**。この集計はスナップショット
 * 全走査 (セトリ 13,777 件・出演者 60,383 件) が前提で、等価な SQL が無いため。
 * スナップショットが使えないときは [SongPerformanceEvidence.EMPTY] を返し、画面は
 * その節を出さない (旧経路が無い機能なので、これが「壊れていない」状態)。
 *
 * ## FFI の回数
 * 曲詳細を 1 回開くのに叩くコア呼び出しは **1 回だけ** (`songPerformanceInsights` が
 * 共起と歌唱者を束ねて返す)。行ごとに引かないこと。
 * コアは id しか返さないが、実体は Room から引き直す (`hydrateInOrder` の規約。
 * Room のエンティティにはコアが持たない派生列があるため)。
 */
class PerformanceEvidenceRepository(
    private val db: AppDatabase,
    // null = スナップショット経路なし (テスト・ネイティブ未同梱ビルド)。常に空を返す。
    private val snapshots: SnapshotStoreProvider? = null
) {

    suspend fun fetchSongPerformanceEvidence(
        songId: String,
        coLimit: Int = CO_OCCURRING_DISPLAY_COUNT,
        singerLimit: Int = SINGER_DISPLAY_COUNT
    ): SongPerformanceEvidence {
        val raw = snapshots?.query { store ->
            store.songPerformanceInsights(
                songId,
                coLimit.coerceAtLeast(0).toUInt(),
                singerLimit.coerceAtLeast(0).toUInt()
            )
        } ?: return SongPerformanceEvidence.EMPTY

        // id 列 → Room 実体。id ごとに引かず 1 クエリ (チャンク分割) で解決する。
        // 引き直せなかった id (同期直後でローカルにまだ無い等) は落とす。回数だけあっても
        // 曲名/名前の無い行は読めない。
        val songs = hydrateInOrder(raw.coOccurring.map { it.songId }, Song::id) {
            db.songDao().fetchSongsByIds(it)
        }.associateBy { it.id }
        val idols = hydrateInOrder(raw.singers.map { it.idolId }, Idol::id) {
            db.songDao().fetchIdolsByIds(it)
        }.associateBy { it.id }

        return SongPerformanceEvidence(
            // コアが返した回数の多い順をそのまま保つ (並べ直さない)。
            coOccurring = raw.coOccurring.mapNotNull { row ->
                songs[row.songId]?.let {
                    CoOccurringSong(song = it, together = row.together.toInt(), performances = row.performances.toInt())
                }
            },
            singers = raw.singers.mapNotNull { row ->
                idols[row.idolId]?.let {
                    SongSingerTally(idol = it, times = row.times.toInt(), total = row.total.toInt())
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
