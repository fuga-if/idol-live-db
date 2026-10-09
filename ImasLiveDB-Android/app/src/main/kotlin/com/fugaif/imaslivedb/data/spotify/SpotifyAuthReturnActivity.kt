package com.fugaif.imaslivedb.data.spotify

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.fugaif.imaslivedb.MainActivity
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Spotify のログイン (アプリ内ブラウザ) から戻ってくる口 (`imaslivedb://spotify-callback`)。
 *
 * 受け取った code を [SpotifyService.completeSignIn] に渡し、MainActivity を CLEAR_TOP で
 * 呼び直してブラウザを畳む (`MusicAuthReturnActivity` と同じ畳み方)。
 */
class SpotifyAuthReturnActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val callback = intent?.data
        if (callback != null) {
            val service = AppModule.from(this).spotifyService
            scope.launch { service.completeSignIn(callback) }
        }
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        )
        finish()
    }

    private companion object {
        /** 画面より長く生きる (交換の途中で画面を閉じても最後まで終える)。 */
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    }
}
