package com.fugaif.imaslivedb.player

/**
 * 一覧の行の再生ボタン。iOS `MusicKitService.toggleSong` と対。
 *
 * Apple Music に繋がっていればフル尺、繋がっていなければ試聴 (30 秒)。
 * 未サインインのときにサインインの画面は出さない。一覧の行を押すたびにブラウザが開くと、
 * Apple Music を使わない人は試聴すら聴けなくなる (サインインは曲詳細の歌詞・プレイリストから)。
 */
object SongRowPlayback {
    fun isPlaying(playback: LyricsPlayback, songId: String): Boolean =
        AudioPreviewManager.playbackState.value.isPlaying(songId) ||
            (playback.loadedSongId.value == songId && playback.isPlaying.value)

    suspend fun toggle(playback: LyricsPlayback, songId: String, appleMusicId: String?, previewUrl: String?) {
        if (isPlaying(playback, songId)) {
            AudioPreviewManager.stop()
            playback.stop()
            return
        }
        if (playback.appleMusicState.value == AppleMusicState.READY && !appleMusicId.isNullOrEmpty()) {
            AudioPreviewManager.stop()
            if (playback.startFull(songId, appleMusicId)) return
        }
        // 未サインイン・配信なしの曲は試聴へ落とす。フル尺が残っていると 2 つ重なるので止める。
        if (previewUrl != null) {
            playback.stop()
            AudioPreviewManager.togglePreview(previewUrl, songId)
        }
    }
}
