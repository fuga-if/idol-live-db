package com.fugaif.imaslivedb.player

import android.app.Activity

/**
 * MusicKit for Android (Apple の再生 SDK) に触る口。
 *
 * **実装は `src/withSdk/` にあり、`app/libs/` に SDK の AAR を置いたときだけコンパイルされる。**
 * AAR は Apple Developer から各自が落とす再配布不可の配布物なので git に入れない
 * (`*.aar` は .gitignore 済み)。AAR が無いビルドでは [createOrNull] が null を返し、
 * 歌詞の追従は「Apple Music で再生できません」になる。
 *
 * サインインはここを通らない。SDK の認証は端末の Apple Music アプリにサインイン済みだと
 * 結果が返らない不具合があるので (FB24754184)、ブラウザで通す ([AppleMusicAuth])。
 * イントロドンの Android 版 (RealMusicKitBridge) と同じ作り。
 */
interface MusicKitBridge {
    /**
     * カタログ ID を順に積んで鳴らす (プレイリスト)。SDK がネイティブに持つ複数曲キュー
     * ([com.apple.android.music.playback.controller.MediaPlayerController.skipToNextItem] 等) を使う。
     * 単曲再生も要素数 1 のキューとして積む (「次はこれ」で後から 1 曲足せるように)。
     *
     * @param catalogIds 積む順。
     * @param startIndex 何番目から鳴らすか。
     * @param onCurrentItemChanged 今鳴っている曲のカタログ ID (曲送り・SDK 側の操作・自然な曲の終わりで変わったとき)。
     */
    fun loadQueue(
        activity: Activity,
        developerToken: String,
        musicUserToken: String,
        catalogIds: List<String>,
        startIndex: Int,
        onPlayingChanged: (Boolean) -> Unit,
        onCurrentItemChanged: (String?) -> Unit,
        onFailed: (String) -> Unit,
    )

    /** 積んだ曲の次があるか (曲送りのボタンを出すか)。 */
    fun canSkipToNext(): Boolean
    /** 次の曲へ。 */
    fun skipToNext()
    /** 前の曲へ (SDK のネイティブキュー内移動。頭出しにするかの判断は呼び出し側が [seek] で行う)。 */
    fun skipToPrevious()

    /** 今のキューの末尾にもう 1 曲積めるか (「次はこれ」を足せるか)。 */
    fun canAppendToQueue(): Boolean
    /** キューの末尾にこのカタログ ID の曲を積む (「次はこれ」)。積めなければ false。 */
    fun appendToQueue(catalogId: String): Boolean

    /** 今の再生位置 (ms)。積んでいなければ null。 */
    fun positionMs(): Long?
    /** 曲の長さ (ms)。分からなければ null。 */
    fun durationMs(): Long?
    fun seek(ms: Long)
    fun play()
    fun pause()
    fun release()

    companion object {
        /** `withSdk` の実装があればそれを、無ければ null。 */
        fun createOrNull(): MusicKitBridge? = runCatching {
            Class.forName("com.fugaif.imaslivedb.player.RealMusicKitBridge")
                .getDeclaredConstructor().newInstance() as MusicKitBridge
        }.getOrNull()
    }
}
