package com.fugaif.imaslivedb.player

import com.fugaif.imaslivedb.data.model.Song

/**
 * プレイリスト (曲の並び) を Apple Music で順に鳴らす。iOS `PlaylistPlayback` と対。
 * フル再生できなければ鳴らさない (試聴は 30 秒で曲送りにならない)。
 */
object PlaylistPlayback {
    /** @return 鳴らし始められたか。false は SDK 無し・未契約・Apple Music にある曲が 1 つも無い。 */
    suspend fun play(playback: LyricsPlayback, songs: List<Song>, startAt: Int = 0): Boolean {
        val entries = songs.map { it.id to (it.appleMusicId ?: "") }
        return playback.startQueue(entries, startAt)
    }

    /** Apple Music で鳴らせない曲 (配信なし) の数。一覧で「n 曲は飛ばします」と出す。 */
    fun unplayableCount(songs: List<Song>): Int = songs.count { it.appleMusicId.isNullOrEmpty() }
}
