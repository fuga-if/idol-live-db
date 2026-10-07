package com.fugaif.imaslivedb.ui.components

import android.content.Context
import android.widget.Toast
import androidx.credentials.exceptions.GetCredentialCancellationException
import com.fugaif.imaslivedb.data.auth.AuthService

/**
 * ログインして、失敗したら一言出す。ボタンから呼ぶ口はこれだけにする。
 *
 * [AuthService.signIn] は失敗を Result で返すだけなので、呼び元が捨てると
 * 「押しても何も起きない」になる (本番署名の鍵が Google 側に無いときなど)。
 * アカウント選択を自分で閉じたときは失敗ではないので黙る。
 */
suspend fun AuthService.signInWithFeedback(activityContext: Context) {
    signIn(activityContext).onFailure { e ->
        if (e is GetCredentialCancellationException) return@onFailure
        Toast.makeText(activityContext, "ログインできませんでした。時間をおいてもう一度お試しください", Toast.LENGTH_LONG).show()
    }
}
