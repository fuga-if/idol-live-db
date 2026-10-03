package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Playlist
import com.fugaif.imaslivedb.data.model.PlaylistSummary
import java.time.Instant
import java.util.UUID
import uniffi.imas_core.playlistAppendSongs

/**
 * プレイリストの読み書き (端末ローカル)。並びの規則はコア
 * (`playlistAppendSongs` / `playlistMoveSong`)。iOS `PlaylistStoring` と同じ口。
 */
class PlaylistRepository(private val db: AppDatabase) {

    private val dao get() = db.playlistDao()

    suspend fun summaries(): List<PlaylistSummary> =
        dao.getAll().map { playlist ->
            val ids = dao.songIds(playlist.id)
            PlaylistSummary(playlist = playlist, songCount = ids.size, firstSongId = ids.firstOrNull())
        }

    suspend fun songIds(playlistId: String): List<String> = dao.songIds(playlistId)

    suspend fun create(name: String): Playlist {
        val now = Instant.now().toString()
        val playlist = Playlist(id = UUID.randomUUID().toString(), name = name, createdAt = now, updatedAt = now)
        dao.upsert(playlist)
        return playlist
    }

    suspend fun rename(id: String, name: String) {
        dao.rename(id, name, Instant.now().toString())
    }

    suspend fun delete(id: String) {
        dao.delete(id)
    }

    /** 曲の並びを丸ごと書き直す (足す・外す・並べ替えはコアで並びを作ってからこれを呼ぶ)。 */
    suspend fun setSongIds(playlistId: String, songIds: List<String>) {
        dao.replaceSongIds(playlistId, songIds, Instant.now().toString())
    }

    /** 曲を後ろに足す (既にある曲は足さない)。 */
    suspend fun append(playlistId: String, adding: List<String>) {
        val existing = dao.songIds(playlistId)
        setSongIds(playlistId, playlistAppendSongs(existing, adding))
    }

    /** バックアップ用の id 一覧 (重複判定はコアが id で行う)。 */
    suspend fun allIds(): List<String> = dao.allIds()

    /** バックアップ用。プレイリストと曲の並びを全部。 */
    suspend fun allForBackup(): List<Pair<Playlist, List<String>>> =
        dao.getAll().map { it to dao.songIds(it.id) }

    /**
     * バックアップからの非破壊復元: ローカルに無い id のプレイリストだけ足す。
     * 既にある id は**触らない** (中身を混ぜたり並びを変えたりしない)。
     */
    suspend fun restoreIfAbsent(playlists: List<Pair<Playlist, List<String>>>): Int {
        var inserted = 0
        for ((playlist, songIds) in playlists) {
            if (dao.insertIfAbsent(playlist, songIds)) inserted++
        }
        return inserted
    }
}
