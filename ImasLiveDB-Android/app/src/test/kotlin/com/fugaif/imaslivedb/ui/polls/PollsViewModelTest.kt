package com.fugaif.imaslivedb.ui.polls

import android.app.Application
import android.os.Looper
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import com.fugaif.imaslivedb.data.net.WorkerResponse
import com.fugaif.imaslivedb.testing.FakeWorkerTransport
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
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

    /**
     * 終了タブは `status=past` の件数既定 20 で古いお題が切れるため、`/polls/months` で月を取り、
     * 最初は新しい月だけ読んで、末尾まで見たら 1 か月古い月を読む (iOS PollListViewModel と同じ契約)。
     */
    @Test
    fun pastLoadsNewestMonthThenGoesBackOneMonthAtATime() {
        val past = System.currentTimeMillis() / 1000 - 86_400 * 30
        val transport = FakeWorkerTransport { request ->
            when {
                request.url.contains("/polls/months") -> WorkerResponse(200, MONTHS)
                request.url.contains("month=2026-10") -> WorkerResponse(
                    200,
                    """[{"id":"oct","title":"10月のお題","target_type":"song","status":"removed","ends_at":$past,
                        "candidate_scope":"all","scope_brand_ids":[],"scope_entity_ids":[],
                        "total_votes":0,"entry_count":0,"my_vote_count":0,"top_entity_id":null}]""".trimIndent()
                )
                request.url.contains("month=2026-09") -> WorkerResponse(
                    200,
                    """[{"id":"sep1","title":"9月のお題1","target_type":"song","status":"removed","ends_at":$past,
                        "candidate_scope":"all","scope_brand_ids":[],"scope_entity_ids":[],
                        "total_votes":0,"entry_count":0,"my_vote_count":0,"top_entity_id":null},
                       {"id":"sep2","title":"9月のお題2","target_type":"song","status":"removed","ends_at":$past,
                        "candidate_scope":"all","scope_brand_ids":[],"scope_entity_ids":[],
                        "total_votes":0,"entry_count":0,"my_vote_count":0,"top_entity_id":null}]""".trimIndent()
                )
                else -> throw AssertionError("想定外のリクエスト: ${request.url}")
            }
        }
        val api = CommunityApi(WorkerHttpClient(app, { null }, transport))
        val viewModel = PollsViewModel(app, api) { type, id -> "$type:$id" }

        viewModel.setShowActive(false)
        idleUntil { !viewModel.uiState.value.isLoading }

        assertEquals(listOf("oct"), viewModel.uiState.value.pastSections.flatMap { it.cards }.map { it.poll.id })
        assertEquals(true, viewModel.uiState.value.hasMorePast)

        viewModel.loadMorePast()
        idleUntil { !viewModel.uiState.value.isLoadingMore }

        assertEquals(listOf("2026-10", "2026-09"), viewModel.uiState.value.pastSections.map { it.month.month })
        assertEquals(
            listOf("oct", "sep1", "sep2"),
            viewModel.uiState.value.pastSections.flatMap { it.cards }.map { it.poll.id }
        )
        assertEquals(false, viewModel.uiState.value.hasMorePast)

        // 読み直しても、さかのぼった月は畳まない (詳細から戻ったときに相当)。
        viewModel.refresh()
        idleUntil { !viewModel.uiState.value.isLoading }
        assertEquals(listOf("2026-10", "2026-09"), viewModel.uiState.value.pastSections.map { it.month.month })
    }

    /**
     * 開催中タブは 20 件ずつ。末尾まで見たら offset を進めて次のページを読み、
     * 読み直し (詳細から戻ったとき) は読んだ件数ぶんを 1 回で取り直して一覧を畳まない。
     */
    @Test
    fun activeLoadsTwentyAtATimeAndReloadKeepsLoadedCount() {
        val all = (1..25).map { "a$it" }
        val transport = FakeWorkerTransport { request ->
            check(request.url.contains("/polls?status=active")) { "一覧以外を読んだ: ${request.url}" }
            val limit = Regex("limit=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            val offset = Regex("offset=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            WorkerResponse(200, activeJson(all.drop(offset).take(limit)))
        }
        val api = CommunityApi(WorkerHttpClient(app, { null }, transport))
        val viewModel = PollsViewModel(app, api) { type, id -> "$type:$id" }

        viewModel.refresh()
        idleUntil { !viewModel.uiState.value.isLoading }
        assertEquals(all.take(20), viewModel.uiState.value.cards.map { it.poll.id })
        assertEquals(true, viewModel.uiState.value.hasMoreActive)
        assertTrue(transport.requests.last().url.contains("limit=20&offset=0"))

        viewModel.loadMoreActive()
        idleUntil { !viewModel.uiState.value.isLoadingMore }
        assertEquals(all, viewModel.uiState.value.cards.map { it.poll.id })
        assertEquals(false, viewModel.uiState.value.hasMoreActive)
        assertTrue(transport.requests.last().url.contains("limit=20&offset=20"))

        viewModel.refresh()
        idleUntil { transport.requests.size >= 3 }
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(3, transport.requests.size)
        assertTrue(transport.requests[2].url.contains("limit=25&offset=0"))
        assertEquals(all, viewModel.uiState.value.cards.map { it.poll.id })
    }

    /** 終了したお題は 1 位の票数 (top_vote_count) を読む。無投票・古いサーバでは null。 */
    @Test
    fun pastPollParsesTopVoteCount() {
        val past = System.currentTimeMillis() / 1000 - 86_400 * 30
        val transport = FakeWorkerTransport { request ->
            when {
                request.url.contains("/polls/months") -> WorkerResponse(200, """[{"month":"2026-10","label":"2026.10","count":2}]""")
                request.url.contains("month=2026-10") -> WorkerResponse(
                    200,
                    """[{"id":"won","title":"決着","target_type":"song","status":"active","ends_at":$past,
                        "total_votes":9,"top_entity_id":"s1","top_vote_count":5},
                       {"id":"none","title":"無投票","target_type":"song","status":"active","ends_at":$past,
                        "total_votes":0,"top_entity_id":null,"top_vote_count":null}]""".trimIndent()
                )
                else -> throw AssertionError("想定外のリクエスト: ${request.url}")
            }
        }
        val api = CommunityApi(WorkerHttpClient(app, { null }, transport))
        val viewModel = PollsViewModel(app, api) { type, id -> "$type:$id" }

        viewModel.setShowActive(false)
        idleUntil { !viewModel.uiState.value.isLoading }

        val cards = viewModel.uiState.value.pastSections.flatMap { it.cards }
        assertEquals(listOf(5, null), cards.map { it.poll.topVoteCount })
        assertEquals(listOf("song:s1", null), cards.map { it.topEntityName })
    }

    private fun idleUntil(condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 10_000
        while (!condition() && System.currentTimeMillis() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
    }

    private companion object {
        fun activeJson(ids: List<String>): String = ids.joinToString(",", "[", "]") { id ->
            """{"id":"$id","title":"$id","target_type":"song","status":"active","ends_at":$FAR,
               "total_votes":0,"top_entity_id":null}"""
        }

        val FAR = System.currentTimeMillis() / 1000 + 86_400 * 30
        val POLLS = """
            [{"id":"p1","title":"夏の曲","target_type":"song","status":"active","ends_at":$FAR,
              "candidate_scope":"brand","scope_brand_ids":["765as","cg"],"scope_entity_ids":[],
              "total_votes":12,"entry_count":4,"my_vote_count":0,"top_entity_id":"s1"},
             {"id":"p2","title":"推しユニット","target_type":"unit","status":"active","ends_at":$FAR,
              "candidate_scope":"all","scope_brand_ids":[],"scope_entity_ids":[],
              "total_votes":0,"entry_count":0,"my_vote_count":0,"top_entity_id":null}]
        """.trimIndent()
        val MONTHS = """
            [{"month":"2026-10","label":"2026.10","count":1},
             {"month":"2026-09","label":"2026.09","count":2}]
        """.trimIndent()
    }
}
