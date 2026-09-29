package com.fugaif.imaslivedb.data.net

import android.content.Context
import com.fugaif.imaslivedb.data.auth.AuthService
import com.fugaif.imaslivedb.data.backup.BackupTransferApi
import com.fugaif.imaslivedb.data.backup.BackupTransferException
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.community.DeviceIdentity
import com.fugaif.imaslivedb.data.community.DiscordLinkService
import com.fugaif.imaslivedb.data.community.SetlistLikeService
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.testing.FakeWorkerTransport
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * Worker のクライアントが共通の [WorkerHttpClient] を通して送り、失敗の扱い (null / 例外 / 文言) は
 * クライアントごとに元のままであること。送信はフェイクに差し替える。
 */
@RunWith(RobolectricTestRunner::class)
class WorkerClientsTest {

    private val context: Context = RuntimeEnvironment.getApplication()

    private fun http(transport: FakeWorkerTransport, token: String? = "jwt") =
        WorkerHttpClient(context, { token }, transport)

    // --- 共通部分 ---

    @Test
    fun requestCarriesBaseUrlDeviceIdAndSession() {
        val transport = FakeWorkerTransport()
        http(transport).request("POST", "/songs/s1/tags", org.json.JSONObject().put("a", 1))
        http(transport, token = null).request("GET", "/tags")
        http(transport).request("POST", "/auth/login", authorized = false)

        val (withToken, withoutToken, login) = transport.requests
        assertEquals("https://imas-live-api.tokata3011.workers.dev/songs/s1/tags", withToken.url)
        assertEquals("POST", withToken.method)
        assertEquals("""{"a":1}""", withToken.body)
        assertEquals("application/json", withToken.headers["Content-Type"])
        assertEquals(DeviceIdentity.get(context), withToken.headers["X-Device-Id"])
        assertEquals("Bearer jwt", withToken.headers["Authorization"])
        assertNull(withoutToken.headers["Authorization"])
        assertNull(withoutToken.body)
        assertNull(login.headers["Authorization"])
    }

    // --- 失敗の扱いはクライアントごとに元のまま ---

    @Test
    fun communityApiTurnsFailuresIntoEmptyResults() = runBlocking {
        val serverError = CommunityApi(http(FakeWorkerTransport { WorkerResponse(500, "oops") }))
        assertEquals(emptyList<CommunityApi.SongTag>(), serverError.songTags("s1"))
        assertFalse(serverError.applyTag("s1", "t1"))

        val offline = CommunityApi(http(FakeWorkerTransport { null }))
        assertEquals(emptyList<CommunityApi.SongTag>(), offline.songTags("s1"))
        assertNull(offline.penlightVotes("s1"))
    }

    @Test
    fun editApiMapsStatusesToItsExceptions() = runBlocking {
        val auth = AuthService(context)
        fun api(code: Int) = EditApi(http(FakeWorkerTransport { WorkerResponse(code, "{}") }), auth)

        assertThrows<EditApi.ApiException.NotAuthorized> { api(401).good(1) }
        assertThrows<EditApi.ApiException.RateLimited> { api(429).good(1) }
        assertThrows<EditApi.ApiException.Server> { api(500).good(1) }
        assertFalse(auth.state.value.isBanned)
        assertThrows<EditApi.ApiException.Banned> { api(403).good(1) }
        assertTrue("403 は BAN として認証状態に反映する", auth.state.value.isBanned)
        assertThrows<EditApi.ApiException.Transport> {
            EditApi(http(FakeWorkerTransport { null }), auth).good(1)
        }
    }

    @Test
    fun backupTransferKeepsItsMessages() = runBlocking {
        suspend fun message(transport: FakeWorkerTransport): String? = try {
            BackupTransferApi(http(transport)).fetchTransferCode("abcd")
            null
        } catch (e: BackupTransferException) {
            e.message
        }
        assertEquals("コードが無効か期限切れです", message(FakeWorkerTransport { WorkerResponse(404, null) }))
        assertEquals("通信に失敗しました (HTTP 500)", message(FakeWorkerTransport { WorkerResponse(500, null) }))
        assertEquals("通信に失敗しました", message(FakeWorkerTransport { null }))

        val ok = FakeWorkerTransport { WorkerResponse(200, """{"payload":"p"}""") }
        assertEquals("p", BackupTransferApi(http(ok)).fetchTransferCode(" abcd "))
        assertTrue(ok.requests.single().url.endsWith("/transfer/ABCD"))
    }

    @Test
    fun setlistLikesAskForSignInOnUnauthorized() = runBlocking {
        val service = SetlistLikeService(http(FakeWorkerTransport { WorkerResponse(401, null) }))
        assertThrows<SetlistLikeService.Unauthorized> { service.like("sh1", "s1") }
        assertEquals(emptyList<SetlistLikeService.LikeEntry>(), service.fetch("sh1"))
    }

    @Test
    fun discordLinkReturnsUrlAndMapsFailuresToMessages() = runBlocking {
        val ok = FakeWorkerTransport {
            WorkerResponse(200, """{"url":"https://discord.com/oauth2/authorize?state=x"}""")
        }
        assertEquals("https://discord.com/oauth2/authorize?state=x", DiscordLinkService(http(ok)).authorizeUrl())
        val sent = ok.requests.single()
        assertEquals("POST", sent.method)
        assertTrue(sent.url.endsWith("/discord/link"))
        assertEquals("{}", sent.body)
        assertEquals("Bearer jwt", sent.headers["Authorization"])

        suspend fun message(transport: FakeWorkerTransport): String? = try {
            DiscordLinkService(http(transport)).authorizeUrl()
            null
        } catch (e: DiscordLinkService.LinkException) {
            e.message
        }
        assertEquals(DiscordLinkService.NOT_CONFIGURED_MESSAGE,
            message(FakeWorkerTransport { WorkerResponse(503, """{"error":"discord_not_configured"}""") }))
        assertEquals(DiscordLinkService.GENERIC_MESSAGE, message(FakeWorkerTransport { WorkerResponse(429, null) }))
        assertEquals(DiscordLinkService.GENERIC_MESSAGE, message(FakeWorkerTransport { WorkerResponse(401, null) }))
        assertEquals(DiscordLinkService.GENERIC_MESSAGE, message(FakeWorkerTransport { WorkerResponse(200, "{}") }))
        assertEquals(DiscordLinkService.GENERIC_MESSAGE, message(FakeWorkerTransport { null }))
    }

    private suspend inline fun <reified T : Throwable> assertThrows(block: suspend () -> Unit) {
        try {
            block()
        } catch (e: Throwable) {
            if (e is T) return
            fail("${T::class.simpleName} を期待したが ${e::class.simpleName}: ${e.message}")
        }
        fail("${T::class.simpleName} が投げられなかった")
    }
}
