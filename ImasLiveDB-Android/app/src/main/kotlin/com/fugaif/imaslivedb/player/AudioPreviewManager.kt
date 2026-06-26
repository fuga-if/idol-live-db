package com.fugaif.imaslivedb.player

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import androidx.media3.common.AudioAttributes as Media3AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class PlaybackState(
    val isPlaying: Boolean = false,
    val nowPlayingUrl: String? = null,
    val nowPlayingTitle: String? = null
)

/**
 * Singleton audio preview manager backed by ExoPlayer (Media3).
 * Handles audio focus, and exposes [playbackState] as a [StateFlow].
 *
 * Must be initialised via [init] before use (call from Application.onCreate).
 * Mirrors iOS MusicKitService.shared preview logic.
 */
object AudioPreviewManager {

    private val _playbackState = MutableStateFlow(PlaybackState())
    val playbackState: StateFlow<PlaybackState> = _playbackState.asStateFlow()

    private var player: ExoPlayer? = null
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private var focusChangeListener: AudioManager.OnAudioFocusChangeListener? = null

    /**
     * Initialise ExoPlayer and AudioManager.
     * Call once from [android.app.Application.onCreate].
     */
    fun init(context: Context) {
        if (player != null) return

        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        val media3AudioAttributes = Media3AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .build()

        player = ExoPlayer.Builder(context.applicationContext)
            .setAudioAttributes(media3AudioAttributes, /* handleAudioFocus= */ false)
            .build()
            .also { exoPlayer ->
                exoPlayer.addListener(object : Player.Listener {
                    override fun onIsPlayingChanged(isPlaying: Boolean) {
                        val current = _playbackState.value
                        _playbackState.value = current.copy(isPlaying = isPlaying)
                        if (!isPlaying) abandonAudioFocus()
                    }

                    override fun onPlaybackStateChanged(playbackState: Int) {
                        if (playbackState == Player.STATE_ENDED) {
                            stop()
                        }
                    }
                })
            }
    }

    /**
     * Toggle preview playback:
     * - If [url] matches the currently playing track → pause/stop.
     * - Otherwise → start playing the new URL.
     */
    fun togglePreview(url: String, title: String) {
        val current = _playbackState.value
        if (current.nowPlayingUrl == url && current.isPlaying) {
            stop()
            return
        }
        playUrl(url, title)
    }

    /** Stop playback and clear state. */
    fun stop() {
        player?.stop()
        player?.clearMediaItems()
        _playbackState.value = PlaybackState()
        abandonAudioFocus()
    }

    /** Release ExoPlayer resources. Call from Application.onTerminate or when no longer needed. */
    fun release() {
        stop()
        player?.release()
        player = null
    }

    // --- Private helpers ---

    private fun playUrl(url: String, title: String) {
        val exo = player ?: return
        if (!requestAudioFocus()) return

        _playbackState.value = PlaybackState(
            isPlaying = false,
            nowPlayingUrl = url,
            nowPlayingTitle = title
        )

        exo.stop()
        exo.setMediaItem(MediaItem.fromUri(url))
        exo.prepare()
        exo.play()
    }

    private fun requestAudioFocus(): Boolean {
        val am = audioManager ?: return true

        val listener = AudioManager.OnAudioFocusChangeListener { focusChange ->
            when (focusChange) {
                AudioManager.AUDIOFOCUS_LOSS,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> stop()
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> player?.volume = 0.3f
                AudioManager.AUDIOFOCUS_GAIN -> player?.volume = 1f
            }
        }.also { focusChangeListener = it }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setOnAudioFocusChangeListener(listener)
                .build()
                .also { focusRequest = it }
            am.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(
                listener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun abandonAudioFocus() {
        val am = audioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { am.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(focusChangeListener)
        }
        focusChangeListener = null
    }
}
