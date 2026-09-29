package com.fugaif.imaslivedb.data.auth

import android.content.Context
import com.fugaif.imaslivedb.data.net.WorkerRequest
import com.fugaif.imaslivedb.data.net.WorkerResponse
import com.fugaif.imaslivedb.testing.FakeWorkerTransport
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.util.Base64

/**
 * セッション JWT の再発行 (iOS と同じ条件。判断はコアの auth_* 規則)。
 * 401 を受けたら 1 回だけ `/auth/refresh` を試して送り直し、通らなければ失効させる。
 * 前面に出たときは、期限が近いものだけを先回りで再発行する。
 */
@RunWith(RobolectricTestRunner::class)
class AuthSessionRefreshTest {

    private val context: Context = RuntimeEnvironment.getApplication()
    private val now = 1_800_000_000L
    private val old = token(exp = now + 60L * 60 * 24 * 200)
    private val renewed = token(exp = now + 60L * 60 * 24 * 365)

    @Test
    fun unauthorizedRequestIsRetriedWithTheRenewedSession() = runBlocking {
        val transport = FakeWorkerTransport { request ->
            when {
                request.url.endsWith("/auth/refresh") -> refreshed(renewed)
                request.bearer() == old -> WorkerResponse(401, """{"error":"Unauthorized"}""")
                else -> WorkerResponse(200, """{"isAdmin":false,"isBanned":false,"displayName":"P"}""")
            }
        }
        val auth = signedIn(transport, old)

        auth.refreshMe()

        assertEquals(listOf("/auth/me" to old, "/auth/refresh" to old, "/auth/me" to renewed), transport.sent())
        assertEquals(renewed, auth.sessionToken)
        assertTrue(auth.state.value.isSignedIn)
    }

    @Test
    fun sessionExpiresWhenRenewalIsRefused() = runBlocking {
        val transport = FakeWorkerTransport { WorkerResponse(401, """{"error":"Unauthorized"}""") }
        val auth = signedIn(transport, old)

        auth.refreshMe()

        assertEquals(listOf("/auth/me" to old, "/auth/refresh" to old), transport.sent())
        assertNull(auth.sessionToken)
        assertFalse(auth.state.value.isSignedIn)
    }

    @Test
    fun foregroundRenewsOnlyASessionCloseToExpiry() = runBlocking {
        val fresh = FakeWorkerTransport { refreshed(renewed) }
        signedIn(fresh, old).refreshSessionIfDue(now)
        assertEquals(emptyList<Pair<String, String?>>(), fresh.sent())

        val nearExpiry = token(exp = now + 60L * 60 * 24)
        val transport = FakeWorkerTransport { refreshed(renewed) }
        val auth = signedIn(transport, nearExpiry)
        auth.refreshSessionIfDue(now)
        assertEquals(listOf("/auth/refresh" to nearExpiry), transport.sent())
        assertEquals(renewed, auth.sessionToken)
    }

    private fun signedIn(transport: FakeWorkerTransport, session: String): AuthService {
        val prefs = context.getSharedPreferences("auth_test_${System.nanoTime()}", Context.MODE_PRIVATE)
        prefs.edit().putString("session_token", session).commit()
        return AuthService(context, transport, openSecurePrefs = { prefs })
    }

    private fun refreshed(session: String) = WorkerResponse(
        200, JSONObject().put("sessionToken", session).put("uid", "u1").put("isAdmin", false).toString()
    )

    private fun WorkerRequest.bearer(): String? = headers["Authorization"]?.removePrefix("Bearer ")

    private fun FakeWorkerTransport.sent() =
        requests.map { it.url.substringAfter(".dev") to it.bearer() }

    /** Worker が出すのと同じ claim の JWT (署名はコアが見ないので中身は何でもよい)。 */
    private fun token(exp: Long): String {
        val enc = Base64.getUrlEncoder().withoutPadding()
        val header = enc.encodeToString("""{"alg":"HS256","typ":"JWT"}""".toByteArray())
        val payload = enc.encodeToString(
            """{"iss":"imas-live-db","aud":"imas-live-db-ios","sub":"u1","iat":${now - 100},"exp":$exp}""".toByteArray()
        )
        return "$header.$payload.sig"
    }
}
