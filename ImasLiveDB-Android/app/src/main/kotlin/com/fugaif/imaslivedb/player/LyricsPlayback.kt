package com.fugaif.imaslivedb.player

import kotlinx.coroutines.flow.StateFlow

/**
 * 歌詞と再生の繋ぎ。iOS の `LyricsPlayback` (DetailSheet が MusicKitService から組む) と同じ口。
 *
 * 追従・記録・ジャンプはフル再生 (Apple Music / Spotify) だけ。30 秒試聴は曲のどこを切り出したか
 * 分からないので、行の時刻と突き合わせられない。
 *
 * 実装は [RoutedLyricsPlayback] が [AppleMusicLyricsPlayback] (MusicKit for Android) と
 * [SpotifyLyricsPlayback] (Spotify アプリの操作) に振り分ける。SDK の AAR が無いビルドや、
 * Apple Music に繋げない端末では [isAvailable] が false で、画面は「再生できない」と出す。
 */
/** Apple Music に繋がっているか (画面が「サインイン」の案内を出すかを決める)。 */
enum class AppleMusicState {
    /** この端末・このビルドでは鳴らせない (SDK の AAR が無い等)。 */
    UNAVAILABLE,
    /** まだサインインしていない。 */
    SIGNED_OUT,
    /** アプリ内ブラウザでサインインしている最中。戻ってくると鳴り始める。 */
    SIGNING_IN,
    /** 鳴らせる。 */
    READY,
}

interface LyricsPlayback {
    /** Apple Music に繋がっているか。 */
    val appleMusicState: StateFlow<AppleMusicState>
    /** アプリ内ブラウザで Apple Music にサインインする。終えて戻ると、頼まれていた曲を鳴らし始める。 */
    fun signIn()

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

    /**
     * 曲を順に積んでフル再生する (プレイリスト)。iOS `MusicKitService.playQueue` と対。
     * Apple Music に無い曲は飛ばす。始められなければ false。
     *
     * @param entries 積む順の `songs.id` と Apple Music の id。
     * @param startAt `entries` の何番目から鳴らすか。その曲が Apple Music に無ければ、次に鳴らせる曲から。
     */
    suspend fun startQueue(entries: List<Pair<String, String>>, startAt: Int): Boolean

    /** 曲を順に積んで鳴らしているか (曲送りのボタンを出すか)。 */
    val hasQueue: StateFlow<Boolean>
    /** 積んだ曲の次があるか。 */
    val canSkipNext: StateFlow<Boolean>
    /** 次の曲へ。 */
    fun skipNext()
    /** 前の曲へ (少し進んでいれば今の曲の頭へ)。 */
    fun skipPrevious()

    fun seek(ms: Int)
    fun togglePlay()
    fun stop()

    /**
     * 「次はこれ」— 積んだ最後の曲まで来たら、コアが選んだ曲 (共起 → 同じ歌い手 → 同じブランド) を
     * 1 曲先まで足して流し続けるか (端末の設定。既定は切。iOS `MusicKitService.autoplayNext` と対)。
     */
    val autoplayNext: StateFlow<Boolean>
    fun setAutoplayNext(value: Boolean)

    /** 積んだ曲の、いまの曲より後ろに残っている分 (songs.id と、「次はこれ」で足した曲ならその理由)。 */
    val upcomingQueue: StateFlow<List<Pair<String, String?>>>

    /** Apple Music の id が無い曲もフル尺で鳴らせるか (Spotify は曲名で探して鳴らす)。 */
    val fullPlaysWithoutAppleMusicId: Boolean get() = false
}

/** 再生できない環境の実装 (SDK の AAR が無いビルド等)。画面は「Apple Music で再生できません」と出す。 */
object NoLyricsPlayback : LyricsPlayback {
    override val appleMusicState: StateFlow<AppleMusicState> =
        kotlinx.coroutines.flow.MutableStateFlow(AppleMusicState.UNAVAILABLE)
    override fun signIn() {}
    override val isAvailable: StateFlow<Boolean> = kotlinx.coroutines.flow.MutableStateFlow(false)
    override val loadedSongId: StateFlow<String?> = kotlinx.coroutines.flow.MutableStateFlow(null)
    override val isPlaying: StateFlow<Boolean> = kotlinx.coroutines.flow.MutableStateFlow(false)
    override fun positionMs(): Int? = null
    override fun durationMs(): Int? = null
    override suspend fun startFull(songId: String, appleMusicId: String): Boolean = false
    override suspend fun startQueue(entries: List<Pair<String, String>>, startAt: Int): Boolean = false
    override val hasQueue: StateFlow<Boolean> = kotlinx.coroutines.flow.MutableStateFlow(false)
    override val canSkipNext: StateFlow<Boolean> = kotlinx.coroutines.flow.MutableStateFlow(false)
    override fun skipNext() {}
    override fun skipPrevious() {}
    override fun seek(ms: Int) {}
    override fun togglePlay() {}
    override fun stop() {}
    override val autoplayNext: StateFlow<Boolean> = kotlinx.coroutines.flow.MutableStateFlow(false)
    override fun setAutoplayNext(value: Boolean) {}
    override val upcomingQueue: StateFlow<List<Pair<String, String?>>> = kotlinx.coroutines.flow.MutableStateFlow(emptyList())
}
