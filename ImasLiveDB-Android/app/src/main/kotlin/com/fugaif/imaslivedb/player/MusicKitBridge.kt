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
    /** カタログ ID の曲を積んで頭から鳴らす。 */
    fun load(
        activity: Activity,
        developerToken: String,
        musicUserToken: String,
        catalogId: String,
        onPlayingChanged: (Boolean) -> Unit,
        onFailed: (String) -> Unit,
    )

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
