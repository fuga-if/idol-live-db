package com.fugaif.imaslivedb.player

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.apple.android.music.playback.controller.MediaPlayerController
import com.apple.android.music.playback.controller.MediaPlayerControllerFactory
import com.apple.android.music.playback.model.MediaItemType
import com.apple.android.music.playback.model.MediaPlayerException
import com.apple.android.music.playback.model.PlaybackState
import com.apple.android.music.playback.model.PlayerQueueItem
import com.apple.android.music.playback.queue.CatalogPlaybackQueueItemProvider
import com.apple.android.sdk.authentication.TokenProvider

/**
 * MusicKit for Android の再生器。イントロドンの RealMusicKitBridge から、歌詞の追従に要る
 * 「積んで鳴らす・位置を読む・位置を動かす」だけを持ってきた。
 *
 * 再生器は 1 つを使い回してキューを積み替える (曲ごとに作ると古い再生器が残って 2 曲鳴る)。
 */
@Suppress("unused")
class RealMusicKitBridge : MusicKitBridge {
    private var controller: MediaPlayerController? = null
    private var tokens: Pair<String, String>? = null
    /** SDK にコールバックを配らせる Handler。 */
    private val sdkHandler = Handler(Looper.getMainLooper())
    private var onPlaying: (Boolean) -> Unit = {}
    private var onFailedNow: (String) -> Unit = {}

    override fun load(
        activity: Activity,
        developerToken: String,
        musicUserToken: String,
        catalogId: String,
        onPlayingChanged: (Boolean) -> Unit,
        onFailed: (String) -> Unit,
    ) {
        onPlaying = onPlayingChanged
        onFailedNow = onFailed
        // 先にネイティブを読ませる。createLocalController が内部で呼ぶ FairPlay の JNI に
        // 静的初期化が無く、素のアプリでは UnsatisfiedLinkError で落ちる (イントロドンで実測)。
        runCatching { System.loadLibrary("appleMusicSDK") }
            .onFailure { Log.w(TAG, "libappleMusicSDK.so を読めない: ${it.message}") }
        // トークンが替わったら再生器を作り直す (古いトークンで叩き続けると 401)。
        if (tokens != developerToken to musicUserToken) {
            controller?.release()
            controller = null
            tokens = developerToken to musicUserToken
        }
        val player = controller ?: create(activity, developerToken, musicUserToken).also { controller = it }
        val queue = CatalogPlaybackQueueItemProvider.Builder()
            .items(MediaItemType.SONG, catalogId)
            .build()
        player.prepare(queue, true)
    }

    private fun create(activity: Activity, developerToken: String, userToken: String): MediaPlayerController {
        val provider = object : TokenProvider {
            override fun getDeveloperToken(): String = developerToken
            override fun getUserToken(): String = userToken
        }
        val player = MediaPlayerControllerFactory.createLocalController(activity, sdkHandler, provider)
        player.addListener(object : MediaPlayerController.Listener {
            override fun onPlayerStateRestored(c: MediaPlayerController) = Unit
            override fun onPlaybackStateChanged(c: MediaPlayerController, old: Int, new: Int) {
                onPlaying(new == PlaybackState.PLAYING)
            }
            override fun onPlaybackStateUpdated(c: MediaPlayerController) = Unit
            override fun onBufferingStateChanged(c: MediaPlayerController, buffering: Boolean) = Unit
            override fun onCurrentItemChanged(c: MediaPlayerController, prev: PlayerQueueItem?, next: PlayerQueueItem?) = Unit
            override fun onItemEnded(c: MediaPlayerController, item: PlayerQueueItem, at: Long) = Unit
            override fun onMetadataUpdated(c: MediaPlayerController, item: PlayerQueueItem) = Unit
            override fun onPlaybackQueueChanged(c: MediaPlayerController, items: List<PlayerQueueItem>) = Unit
            override fun onPlaybackQueueItemsAdded(c: MediaPlayerController, i: Int, j: Int, k: Int) = Unit
            override fun onPlaybackError(c: MediaPlayerController, e: MediaPlayerException) {
                Log.w(TAG, "再生エラー type=${e.type} error=${e.errorCode}")
                onFailedNow("この曲は Apple Music で鳴らせませんでした")
            }
            override fun onPlaybackRepeatModeChanged(c: MediaPlayerController, mode: Int) = Unit
            override fun onPlaybackShuffleModeChanged(c: MediaPlayerController, mode: Int) = Unit
        })
        return player
    }

    override fun positionMs(): Long? = controller?.takeIf { it.currentItem != null }?.currentPosition
    override fun durationMs(): Long? = controller?.duration?.takeIf { it > 0 }
    /** 準備前に頼まれた seek。積んだ直後は canSeek() が false で、そのまま呼ぶと黙って捨てられる。 */
    private var pendingSeek: Long? = null

    override fun seek(ms: Long) {
        pendingSeek = ms.coerceAtLeast(0)
        trySeek(0L)
    }

    /** 準備ができるまで 250 ms おきに待ってから動かす (最大 3 秒)。後から頼まれた位置が勝つ。 */
    private fun trySeek(waitedMs: Long) {
        val c = controller ?: return
        val target = pendingSeek ?: return
        if (c.canSeek() && c.duration > 0) {
            c.seekToPosition(target)
            pendingSeek = null
            return
        }
        if (waitedMs >= 3_000L) { pendingSeek = null; return }
        sdkHandler.postDelayed({ trySeek(waitedMs + 250L) }, 250L)
    }
    override fun play() { controller?.play() }
    override fun pause() { controller?.pause() }
    override fun release() {
        controller?.release()
        controller = null
    }

    private companion object { const val TAG = "MusicKitBridge" }
}
