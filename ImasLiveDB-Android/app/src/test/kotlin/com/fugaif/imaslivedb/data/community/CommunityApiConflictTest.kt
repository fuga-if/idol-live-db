package com.fugaif.imaslivedb.data.community

import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import com.fugaif.imaslivedb.data.net.WorkerResponse
import com.fugaif.imaslivedb.testing.FakeWorkerTransport
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * 本文を読む必要のある 4xx (409 = 同名の既存タグ・429 = お題の上限)。
 *
 * サーバは 409 で既存のタグを本文に返すので、それを採用して作成を冪等にする。
 * 429 は通信失敗と区別して「上限に達した」と案内する (どちらも CommunityApi のコメントどおり)。
 */
@RunWith(RobolectricTestRunner::class)
class CommunityApiConflictTest {

    private val context = RuntimeEnvironment.getApplication()

    private fun api(code: Int, body: String) = CommunityApi(
        WorkerHttpClient(context, { "jwt" }, FakeWorkerTransport { WorkerResponse(code, body) })
    )

    @Test
    fun existingTagIsAdoptedOnConflict() = runBlocking {
        val body = """{"tag":{"id":"t1","name":"推し曲","description":null,"category":"mood","color":"#ff0000","created_at":1,"total_uses":3}}"""
        val expected = CommunityApi.TagCreateResult.Success(
            CommunityApi.CommunityTag("t1", "推し曲", null, "mood", "#ff0000", 1, 3),
            alreadyExisted = true
        )
        assertEquals(expected, api(409, body).createTag("推し曲"))
        assertEquals(expected, api(409, body).createIdolTagOption("推し曲"))
        assertEquals(expected, api(409, body).createUnitTagOption("推し曲"))
    }

    @Test
    fun pollLimitIsReportedAsRateLimited() = runBlocking {
        val result = api(429, """{"error":"poll_limit"}""").createPoll(
            title = "好きな曲", description = null, targetType = "song", days = 7,
            candidateScope = CommunityApi.PollCandidateScope.ALL, scopeBrandIds = null, scopeEntityIds = null
        )
        assertEquals(CommunityApi.PollCreateResult.RateLimited, result)
    }
}
