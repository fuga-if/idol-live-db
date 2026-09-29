package com.fugaif.imaslivedb.ui.polls

import android.app.Application
import android.os.Looper
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import com.fugaif.imaslivedb.data.net.WorkerResponse
import com.fugaif.imaslivedb.testing.FakeWorkerTransport
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/**
 * 投票のお題の一覧は `GET /polls` を 1 回呼ぶだけで作る (お題ごとに詳細を取りに行かない)。
 */
@RunWith(RobolectricTestRunner::class)
class PollsViewModelTest {

    private val app: Application = RuntimeEnvironment.getApplication()

    @Test
    fun listIsBuiltFromOneRequest() {
        val transport = FakeWorkerTransport { request ->
            check(request.url.contains("/polls?status=active")) { "一覧以外を読んだ: ${request.url}" }
            WorkerResponse(200, POLLS)
        }
        val api = CommunityApi(WorkerHttpClient(app, { null }, transport))
        val viewModel = PollsViewModel(app, api) { type, id -> "$type:$id" }

        viewModel.refresh()
        val deadline = System.currentTimeMillis() + 10_000
        while (viewModel.uiState.value.isLoading && System.currentTimeMillis() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }

        assertEquals(1, transport.requests.size)
        val cards = viewModel.uiState.value.cards
        assertEquals(listOf("p1", "p2"), cards.map { it.poll.id })
        assertEquals(listOf(12, 0), cards.map { it.poll.totalVotes })
        assertEquals(listOf("song:s1", null), cards.map { it.topEntityName })
        assertEquals(CommunityApi.PollCandidateScope.BRAND, cards[0].poll.candidateScope)
        assertEquals(listOf("765as", "cg"), cards[0].poll.scopeBrandIds)
    }

    private companion object {
        val FAR = System.currentTimeMillis() / 1000 + 86_400 * 30
        val POLLS = """
            [{"id":"p1","title":"夏の曲","target_type":"song","status":"active","ends_at":$FAR,
              "candidate_scope":"brand","scope_brand_ids":["765as","cg"],"scope_entity_ids":[],
              "total_votes":12,"entry_count":4,"my_vote_count":0,"top_entity_id":"s1"},
             {"id":"p2","title":"推しユニット","target_type":"unit","status":"active","ends_at":$FAR,
              "candidate_scope":"all","scope_brand_ids":[],"scope_entity_ids":[],
              "total_votes":0,"entry_count":0,"my_vote_count":0,"top_entity_id":null}]
        """.trimIndent()
    }
}
