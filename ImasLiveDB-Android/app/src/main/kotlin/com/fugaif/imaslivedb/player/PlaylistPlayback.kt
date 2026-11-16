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

    /**
     * フル尺で鳴らせず飛ばす曲の数 (Apple Music に無い曲と、聴き放題に無い版の曲)。一覧で「n 曲は飛ばします」と出す。
     * Spotify で鳴らすときは曲名で探すので、鳴らすまで分からない (0)。
     *
     * @param unstreamable [LyricsPlayback.unstreamableAppleMusicIds] を画面で集めた値 (変われば数え直す)。
     */
    fun unplayableCount(playback: LyricsPlayback, appleMusicIds: List<String?>, unstreamable: Set<String>): Int =
        appleMusicIds.count { skips(playback, it, unstreamable) }

    /** この曲をフル尺で鳴らせず飛ばすか (行を薄くして「聴けない」と出す)。数え方は [unplayableCount] と同じ。 */
    fun skips(playback: LyricsPlayback, appleMusicId: String?, unstreamable: Set<String>): Boolean =
        !playback.fullPlaysWithoutAppleMusicId && (appleMusicId.isNullOrEmpty() || appleMusicId in unstreamable)

    /** 並べた曲が聴き放題で鳴らせるかを調べる (画面を開いたときに 1 回。結果で [unplayableCount] が変わる)。 */
    suspend fun checkStreamable(playback: LyricsPlayback, appleMusicIds: List<String?>) =
        playback.checkStreamable(appleMusicIds.filterNotNull())
}
