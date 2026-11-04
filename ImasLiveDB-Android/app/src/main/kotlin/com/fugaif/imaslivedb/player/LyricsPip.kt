package com.fugaif.imaslivedb.player

import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import uniffi.imas_core.lyricHasTiming

/**
 * 歌詞をピクチャ・イン・ピクチャ (PiP) で出す。他のアプリを開いている間も、いま歌っている行が画面の隅に残る。
 * iOS `LyricsPictureInPicture` と対。
 *
 * Android の PiP はアクティビティごと小さな窓になるので、PiP の間は画面を [com.fugaif.imaslivedb.ui.lyrics.LyricsPipContent]
 * (いま歌っている行・歌う人・コール・次の行) に差し替える。歌詞は [LyricsSession] が預かったものから引く。
 *
 * - 歌詞プレイヤーの頭の記号で始める。
 * - 歌詞プレイヤーを開いたまま鳴らしてホームへ出たら、自分で浮かぶ (API 31 からは setAutoEnterEnabled、
 *   それより前は onUserLeaveHint)。
 * - PiP の窓の再生 / 一時停止はフル再生を操作する ([ACTION_TOGGLE_PLAY])。
 */
object LyricsPip {
    /** PiP の窓の再生 / 一時停止 (アプリの中だけで受ける)。 */
    const val ACTION_TOGGLE_PLAY = "com.fugaif.imaslivedb.LYRICS_PIP_TOGGLE_PLAY"

    private val _isInPip = MutableStateFlow(false)
    /** いま PiP の窓になっているか。 */
    val isInPip: StateFlow<Boolean> = _isInPip.asStateFlow()

    private val _playerVisible = MutableStateFlow(false)
    /** 歌詞プレイヤーを開いているか (鳴らしたままホームへ出たら自分で浮かぶ)。 */
    val playerVisible: StateFlow<Boolean> = _playerVisible.asStateFlow()

    fun setInPip(value: Boolean) { _isInPip.value = value }
    fun setPlayerVisible(value: Boolean) { _playerVisible.value = value }

    fun isSupported(context: Context): Boolean =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    /** 浮かべられる歌詞 (行の時刻があり、フル再生で読み込んでいる曲)。 */
    fun usableEntry(playback: LyricsPlayback): LyricsSession.Entry? =
        LyricsSession.entry(playback.loadedSongId.value)
            ?.takeIf { entry -> lyricHasTiming(entry.lyrics.lines.map { it.startMs?.toLong() }) }

    /** ホームへ出たら自分で浮かぶか。 */
    fun shouldAutoEnter(playback: LyricsPlayback): Boolean =
        _playerVisible.value && playback.isPlaying.value && usableEntry(playback) != null

    fun params(context: Context, playback: LyricsPlayback): PictureInPictureParams {
        val playing = playback.isPlaying.value
        val toggle = PendingIntent.getBroadcast(
            context, 0, Intent(ACTION_TOGGLE_PLAY).setPackage(context.packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val label = if (playing) "一時停止" else "再生"
        val icon = Icon.createWithResource(
            context, if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        )
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setActions(listOf(RemoteAction(icon, label, label, toggle)))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(shouldAutoEnter(playback))
            builder.setSeamlessResizeEnabled(false)
        }
        return builder.build()
    }

    /** 浮かべる。始められなければ false (端末が PiP を使えない・設定で切っている)。 */
    fun enter(context: Context, playback: LyricsPlayback): Boolean {
        val activity = context.findActivity() ?: return false
        if (!isSupported(activity)) return false
        return runCatching { activity.enterPictureInPictureMode(params(activity, playback)) }.getOrDefault(false)
    }

    private tailrec fun Context.findActivity(): Activity? = when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.findActivity()
        else -> null
    }
}
