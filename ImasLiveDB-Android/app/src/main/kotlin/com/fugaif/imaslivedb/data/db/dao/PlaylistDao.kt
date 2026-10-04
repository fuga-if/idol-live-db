package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.fugaif.imaslivedb.data.model.Playlist
import com.fugaif.imaslivedb.data.model.PlaylistItem

/**
 * プレイリストの読み書き。並べ替え・足し方の規則はコア (`domain/play_queue.rs`)。
 * ここは行の出し入れだけで、曲の並びは「全部書き直す」1 本にする (位置の付け直しを散らさない)。
 */
@Dao
interface PlaylistDao {

    @Query("SELECT * FROM playlists ORDER BY updated_at DESC")
    suspend fun getAll(): List<Playlist>

    @Query("SELECT * FROM playlists WHERE id = :id")
    suspend fun get(id: String): Playlist?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(playlist: Playlist)

    @Query("UPDATE playlists SET name = :name, updated_at = :updatedAt WHERE id = :id")
    suspend fun rename(id: String, name: String, updatedAt: String)

    @Query("UPDATE playlists SET updated_at = :updatedAt WHERE id = :id")
    suspend fun touch(id: String, updatedAt: String)

    /** 公開した「みんなのプレイリスト」の id を覚える (null で外す)。 */
    @Query("UPDATE playlists SET published_id = :publishedId WHERE id = :id")
    suspend fun setPublishedId(id: String, publishedId: String?)

    @Query("DELETE FROM playlists WHERE id = :id")
    suspend fun delete(id: String)

    @Query("SELECT song_id FROM playlist_items WHERE playlist_id = :playlistId ORDER BY position")
    suspend fun songIds(playlistId: String): List<String>

    @Query("SELECT COUNT(*) FROM playlist_items WHERE playlist_id = :playlistId")
    suspend fun songCount(playlistId: String): Int

    @Query("DELETE FROM playlist_items WHERE playlist_id = :playlistId")
    suspend fun clearItems(playlistId: String)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertItems(items: List<PlaylistItem>)

    /** 曲の並びを丸ごと書き直す (全消し→入れ直し)。1 トランザクションで行う。 */
    @Transaction
    suspend fun replaceSongIds(playlistId: String, songIds: List<String>, updatedAt: String) {
        clearItems(playlistId)
        insertItems(songIds.mapIndexed { index, songId -> PlaylistItem(playlistId, songId, index) })
        touch(playlistId, updatedAt)
    }

    @Query("SELECT id FROM playlists")
    suspend fun allIds(): List<String>

    /** バックアップからの非破壊復元: 既に存在する id は挿入せず 0 を返す。 */
    @Transaction
    suspend fun insertIfAbsent(playlist: Playlist, songIds: List<String>): Boolean {
        if (get(playlist.id) != null) return false
        upsert(playlist)
        insertItems(songIds.mapIndexed { index, songId -> PlaylistItem(playlist.id, songId, index) })
        return true
    }
}
