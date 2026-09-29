package com.fugaif.imaslivedb.data.community

import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import com.fugaif.imaslivedb.data.net.WorkerResponse
import com.fugaif.imaslivedb.testing.FakeWorkerTransport
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/** セトリ予想 (みんなの予想) の取得と投票 ([SetlistPredictionService])。 */
@RunWith(RobolectricTestRunner::class)
class SetlistPredictionServiceTest {

    private val context = RuntimeEnvironment.getApplication()

    @Test
    fun parsesPredictionsInServerOrder() = runBlocking {
        val transport = FakeWorkerTransport {
            WorkerResponse(
                200,
                """[{"show_id":"sh","song_id":"s2","vote_count":5,"has_user_voted":true},
                   {"show_id":"sh","song_id":"s1","vote_count":2,"has_user_voted":false},
                   {"show_id":"sh","vote_count":1}]"""
            )
        }
        val service = SetlistPredictionService(WorkerHttpClient(context, { "jwt" }, transport))

        val predictions = service.fetch("sh")

        // 曲 ID の無い行は出せないので落とす。並びはサーバのまま。
        assertEquals(listOf("s2", "s1"), predictions.map { it.songId })
        assertEquals(5, predictions[0].voteCount)
        assertTrue(predictions[0].hasUserVoted)
        assertFalse(predictions[1].hasUserVoted)
        assertEquals("GET", transport.requests.single().method)
        assertTrue(transport.requests.single().url.endsWith("/shows/sh/predictions"))
    }

    @Test
    fun voteSendsSongIdAndDropsTheCacheOfThatShow() = runBlocking {
        val transport = FakeWorkerTransport { request ->
            if (request.method == "GET") WorkerResponse(200, "[]")
            else WorkerResponse(200, """{"song_id":"s1","vote_count":1}""")
        }
        val service = SetlistPredictionService(WorkerHttpClient(context, { "jwt" }, transport))

        service.fetch("sh")
        service.vote("sh", "s1")
        service.fetch("sh")

        // 自分の票が has_user_voted に出るよう、投票の後は取り直す。
        assertEquals(listOf("GET", "POST", "GET"), transport.requests.map { it.method })
        assertEquals("""{"song_id":"s1"}""", transport.requests[1].body)
    }

    @Test
    fun voteLimitIsItsOwnError() = runBlocking {
        val service = SetlistPredictionService(
            WorkerHttpClient(context, { "jwt" }, FakeWorkerTransport { WorkerResponse(409, "vote limit") })
        )
        try {
            service.vote("sh", "s1")
            fail("409 は上限の和文に握り替える")
        } catch (_: SetlistPredictionService.VoteLimitReached) {
        }
    }

    @Test
    fun unauthorizedIsReportedForTheLoginPrompt() = runBlocking {
        val service = SetlistPredictionService(
            WorkerHttpClient(context, { null }, FakeWorkerTransport { WorkerResponse(401, null) })
        )
        try {
            service.unvote("sh", "s1")
            fail("401 はログイン誘導に回す")
        } catch (_: SetlistPredictionService.Unauthorized) {
        }
    }

    /** 自分の票は利用者ごとの値なので、サインアウトの後に前の人の票を出さない。 */
    @Test
    fun votesOfThePreviousAccountAreNotShownAfterSignOut() = runBlocking {
        var session: String? = "jwt-a"
        val transport = FakeWorkerTransport { request ->
            val mine = request.headers["Authorization"] == "Bearer jwt-a"
            WorkerResponse(200, """[{"song_id":"s1","vote_count":3,"has_user_voted":$mine}]""")
        }
        val service = SetlistPredictionService(WorkerHttpClient(context, { session }, transport))

        assertTrue(service.fetch("sh").single().hasUserVoted)
        session = null
        assertFalse(service.fetch("sh").single().hasUserVoted)
    }
}
