package com.fugaif.imaslivedb.player

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.fugaif.imaslivedb.MainActivity

/**
 * Apple Music のサインイン (アプリ内ブラウザ) から戻ってくる口 (`imaslivedb://music-auth`)。
 *
 * アプリ内ブラウザは MainActivity の上に積まれるので、ここから MainActivity を
 * CLEAR_TOP で呼び直してブラウザを畳み、元の画面へ戻す。トークンは URL に載っていない
 * (Worker に一度だけ預けてある) ので、受け取りは [AppleMusicLyricsPlayback] が
 * MainActivity の再開を合図に取りに行く。
 */
class MusicAuthReturnActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        )
        finish()
    }
}
