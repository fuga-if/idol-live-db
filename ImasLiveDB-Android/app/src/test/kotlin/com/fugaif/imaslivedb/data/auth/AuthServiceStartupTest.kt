package com.fugaif.imaslivedb.data.auth

import android.content.Context
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * 認証情報の保存先 (EncryptedSharedPreferences) が開けない端末でも、AuthService が落ちない。
 *
 * キーストアが壊れた端末では暗号化 prefs の作成が例外になる。以前はそれがコンストラクタから
 * 飛び、起動時の refreshMe や設定画面が触れた瞬間にアプリが落ち、起動のたびに落ち続けた。
 * Robolectric には AndroidKeyStore が無いので、ここでは実際に作成が失敗する。
 */
@RunWith(RobolectricTestRunner::class)
class AuthServiceStartupTest {

    @Test
    fun startsSignedOutWhenSecurePrefsCannotBeOpened() = runBlocking {
        val auth = AuthService(RuntimeEnvironment.getApplication())

        assertEquals(AuthState(), auth.state.value)
        assertNull(auth.sessionToken)
        // どれもサーバや保存先に触れる前に黙って終わる (例外を投げない)。
        auth.refreshMe()
        auth.markBannedFromServer()
        auth.signOut()
        assertTrue(!auth.state.value.isSignedIn)
    }

    /**
     * 保存先が壊れていて開けないときは、壊れた保存先を消して開き直す。開き直せたら
     * 未サインインとして動き、次のサインインをそこに保存できる (null のまま動くと、
     * サインインしても保存先が無く、起動のたびにサインインし直しになる)。
     */
    @Test
    fun brokenSecurePrefsAreDeletedAndReopened() {
        val context: Context = RuntimeEnvironment.getApplication()
        // 前回までの (もう読めない) 保存先が残っている。
        val leftover = context.getSharedPreferences(SECURE_PREFS, Context.MODE_PRIVATE)
        leftover.edit().putString("session_token", "garbage").commit()
        var attempts = 0
        val auth = AuthService(context, openSecurePrefs = { ctx ->
            attempts++
            val prefs = ctx.getSharedPreferences(SECURE_PREFS, Context.MODE_PRIVATE)
            // 読めないものが残っている間は開けない (キーストアの鍵と合わない、の代わり)。
            check(!prefs.contains("session_token")) { "AEADBadTagException の代わり" }
            prefs
        })

        // 1 回目 → 開き直し (消さない) → 消して開き直す、の 3 回。
        assertEquals(3, attempts)
        assertEquals(AuthState(), auth.state.value)
        assertNull(auth.sessionToken)
        assertFalse(context.getSharedPreferences(SECURE_PREFS, Context.MODE_PRIVATE).contains("session_token"))
    }

    /**
     * キーストアの一時的な失敗 (1 回目だけ開けない) では、保存先を消さずに開き直し、
     * サインインしたままでいる (RedTeam A-L3)。
     */
    @Test
    fun aTransientFailureDoesNotSignOut() {
        val context: Context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences(SECURE_PREFS, Context.MODE_PRIVATE).edit()
            .putString("session_token", "jwt").commit()
        var attempts = 0
        val auth = AuthService(context, openSecurePrefs = { ctx ->
            attempts++
            check(attempts > 1) { "キーストアが一時的に使えない" }
            ctx.getSharedPreferences(SECURE_PREFS, Context.MODE_PRIVATE)
        })

        assertEquals("jwt", auth.sessionToken)
        assertTrue(auth.state.value.isSignedIn)
    }

    private companion object {
        const val SECURE_PREFS = "imas_auth_secure"
    }
}
