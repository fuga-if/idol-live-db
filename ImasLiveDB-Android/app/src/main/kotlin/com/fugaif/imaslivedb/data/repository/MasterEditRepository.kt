package com.fugaif.imaslivedb.data.repository

import androidx.room.withTransaction
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.SetlistItem
import com.fugaif.imaslivedb.data.model.SetlistPerformer
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongArtist
import com.fugaif.imaslivedb.data.model.SongVideo

/**
 * 編集をサーバが反映した (POST /edits が Applied) ときに、その値を端末の DB に写す口。
 *
 * 画面から DAO へ直接書かない。書き込みは 1 回の保存ごとに 1 トランザクションにし
 * (途中で止まって半分だけ入る、を防ぐ)、書き終えたらスナップショットを作り直す。
 * 作り直さないと、スナップショット経由で読む口だけが次の同期まで編集前の値を返し、
 * 「編集直後に自分の編集が見えない」回帰になる (iOS の `SnapshotInvalidating*` と同じ役割)。
 * reload は DB 全読みで数百 ms かかるが、await して完了させる。保存は「保存中…」を
 * 出したままの操作で、戻った時点で全経路が新しい値を返すことのほうが重要。
 */
class MasterEditRepository(
    private val db: AppDatabase,
    private val snapshots: SnapshotStoreProvider
) {
    suspend fun applyIdol(idol: Idol) = write { db.syncDao().upsertIdols(listOf(idol)) }

    suspend fun applyEvent(event: Event) = write { db.syncDao().upsertEvents(listOf(event)) }

    suspend fun applyShow(show: Show) = write { db.syncDao().upsertShows(listOf(show)) }

    /** 曲と、新しく作った曲の原唱者。 */
    suspend fun applySong(song: Song, newArtists: List<SongArtist>) = write {
        db.syncDao().upsertSongs(listOf(song))
        if (newArtists.isNotEmpty()) db.syncDao().upsertSongArtists(newArtists)
    }

    /** 参考動画。song_videos はスナップショットに載らないので作り直さない。 */
    suspend fun applySongVideo(video: SongVideo) {
        db.syncDao().upsertSongVideos(listOf(video))
    }

    /**
     * セトリ編集の保存後、サーバ確定値でローカル DB を全置換する (iOS `showWriting.replaceSetlist` と同じ)。
     * 行の削除・歌唱者の削除・行と歌唱者の書き込みを 1 トランザクションにする。
     */
    suspend fun replaceSetlist(
        deletedItemIds: List<String>,
        deletedPerformers: List<Pair<String, String>>,
        items: List<SetlistItem>,
        performers: List<SetlistPerformer>
    ) = write {
        val dao = db.setlistDao()
        if (deletedItemIds.isNotEmpty()) dao.deleteItems(deletedItemIds)
        for ((itemId, idolId) in deletedPerformers) dao.deletePerformer(itemId, idolId)
        if (items.isNotEmpty()) dao.upsertItems(items)
        if (performers.isNotEmpty()) dao.upsertPerformers(performers)
    }

    /** 1 トランザクションで書き、書き終えたらスナップショットを作り直す。 */
    private suspend fun write(block: suspend () -> Unit) {
        db.withTransaction { block() }
        snapshots.reload()
    }
}
