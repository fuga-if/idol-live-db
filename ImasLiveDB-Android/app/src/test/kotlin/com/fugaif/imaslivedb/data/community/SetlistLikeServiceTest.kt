package com.fugaif.imaslivedb.data.community

import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import com.fugaif.imaslivedb.data.net.WorkerResponse
import com.fugaif.imaslivedb.testing.FakeWorkerTransport
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * 👍 の集計は利用者ごとの値 (has_user_liked) を含むので、サインアウト・別アカウントへの
 * 切り替えの後に前の人の値を出してはいけない (60 秒の短い覚え書きの中でも)。
 */
@RunWith(RobolectricTestRunner::class)
class SetlistLikeServiceTest {

    private val context = RuntimeEnvironment.getApplication()

    @Test
    fun likesOfThePreviousAccountAreNotShownAfterSignOut() = runBlocking {
        var session: String? = "jwt-a"
        var requests = 0
        val transport = FakeWorkerTransport { request ->
            requests++
            // サインイン中の人は自分の 👍 が付いている。サインアウト後は誰の 👍 でもない。
            val mine = request.headers["Authorization"] == "Bearer jwt-a"
            WorkerResponse(200, """[{"song_id":"s1","like_count":3,"has_user_liked":$mine}]""")
        }
        val service = SetlistLikeService(WorkerHttpClient(context, { session }, transport))

        assertTrue(service.fetch("show1").single().hasUserLiked)

        session = null // サインアウト
        val afterSignOut = service.fetch("show1").single()
        assertFalse("サインアウト後も前のアカウントの 👍 が出ている", afterSignOut.hasUserLiked)
        assertEquals(2, requests)
    }

    @Test
    fun sameSessionReusesTheShortCache() = runBlocking {
        var requests = 0
        val transport = FakeWorkerTransport {
            requests++
            WorkerResponse(200, """[{"song_id":"s1","like_count":3,"has_user_liked":true}]""")
        }
        val service = SetlistLikeService(WorkerHttpClient(context, { "jwt-a" }, transport))
        service.fetch("show1")
        service.fetch("show1")
        assertEquals(1, requests)
    }
}
