package com.fugaif.imaslivedb.player

import kotlinx.coroutines.flow.StateFlow

/**
 * 歌詞と再生の繋ぎ。iOS の `LyricsPlayback` (DetailSheet が MusicKitService から組む) と同じ口。
 *
 * 追従・記録・ジャンプは Apple Music のフル再生だけ。30 秒試聴は曲のどこを切り出したか
 * 分からないので、行の時刻と突き合わせられない。
 *
 * 実装は [AppleMusicLyricsPlayback] (MusicKit for Android)。SDK の AAR が無いビルドや、
 * Apple Music に繋げない端末では [isAvailable] が false で、画面は「再生できない」と出す。
 */
interface LyricsPlayback {
    /** Apple Music で鳴らせる状態か (SDK・トークン・サインインが揃っている)。 */
    val isAvailable: StateFlow<Boolean>
    /** 今フル尺で読み込んでいる曲の songs.id (一時停止中も含む)。無ければ null。 */
    val loadedSongId: StateFlow<String?>
    /** 鳴っているか。 */
    val isPlaying: StateFlow<Boolean>

    /** 今の再生位置 (ms)。フル再生していなければ null。周期で読む (観測対象ではない)。 */
    fun positionMs(): Int?
    /** 曲の長さ (ms)。分からなければ null。 */
    fun durationMs(): Int?

    /**
     * この曲をフル尺で鳴らし始める。始められなければ false (未サインイン・未契約・SDK 無し)。
     * 必要ならサインインの画面を出す。
     */
    suspend fun startFull(songId: String, appleMusicId: String): Boolean
    fun seek(ms: Int)
    fun togglePlay()
    fun stop()
}

/** 再生できない環境の実装 (SDK の AAR が無いビルド等)。画面は「Apple Music で再生できません」と出す。 */
object NoLyricsPlayback : LyricsPlayback {
    override val isAvailable: StateFlow<Boolean> = kotlinx.coroutines.flow.MutableStateFlow(false)
    override val loadedSongId: StateFlow<String?> = kotlinx.coroutines.flow.MutableStateFlow(null)
    override val isPlaying: StateFlow<Boolean> = kotlinx.coroutines.flow.MutableStateFlow(false)
    override fun positionMs(): Int? = null
    override fun durationMs(): Int? = null
    override suspend fun startFull(songId: String, appleMusicId: String): Boolean = false
    override fun seek(ms: Int) {}
    override fun togglePlay() {}
    override fun stop() {}
}
