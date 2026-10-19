package com.fugaif.imaslivedb.data.community

import com.fugaif.imaslivedb.data.auth.AuthService
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import com.fugaif.imaslivedb.data.net.WorkerResponse
import com.fugaif.imaslivedb.testing.FakeWorkerTransport
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * 編集履歴・タグ説明の履歴・お気に入りランキングは一度に全件を読まず、1 ページずつ読む
 * (iOS と同じ契約: 履歴は before、ランキングは limit/offset)。
 */
@RunWith(RobolectricTestRunner::class)
class HistoryPagingApiTest {

    private val context = RuntimeEnvironment.getApplication()

    private fun http(transport: FakeWorkerTransport) = WorkerHttpClient(context, { "jwt" }, transport)

    @Test
    fun tagHistoryPagesWithLimitAndBeforeId() = runBlocking {
        val transport = FakeWorkerTransport {
            WorkerResponse(
                200,
                """[{"id":41,"tag_id":"t1","description_after":"新しい説明","description_before":null,
                    "edited_by":"abcd1234","edited_at":1700000000}]"""
            )
        }
        val api = CommunityApi(http(transport))

        val first = api.tagHistory("t1")
        api.idolTagOptionHistory("t1", before = 41)
        api.unitTagOptionHistory("t1", before = 41)

        assertEquals(41, first!!.single().id)
        assertEquals("新しい説明", first.single().descriptionAfter)
        val urls = transport.requests.map { it.url }
        assertTrue(urls[0], urls[0].endsWith("/tags/t1/history?limit=30"))
        assertTrue(urls[1], urls[1].endsWith("/idol-tags/t1/history?limit=30&before=41"))
        assertTrue(urls[2], urls[2].endsWith("/unit-tags/t1/history?limit=30&before=41"))
    }

    @Test
    fun tagHistoryFailureIsNullNotEmpty() = runBlocking {
        // 読み足しの失敗を「もう無い」と取り違えないよう、通信失敗は null で返す。
        assertNull(CommunityApi(http(FakeWorkerTransport { null })).tagHistory("t1"))
        assertEquals(
            emptyList<CommunityApi.TagHistoryEntry>(),
            CommunityApi(http(FakeWorkerTransport { WorkerResponse(200, "[]") })).tagHistory("t1")
        )
    }

    @Test
    fun favoritesRankingSendsLimitAndOffset() = runBlocking {
        val transport = FakeWorkerTransport { WorkerResponse(200, """[{"song_id":"s1","count":3}]""") }
        val ranking = CommunityApi(http(transport)).favoritesRanking(offset = 400)

        assertEquals(listOf(CommunityApi.FavoriteRankingDto("s1", 3)), ranking)
        val url = transport.requests.single().url
        assertTrue(url, url.endsWith("/favorites/ranking?limit=200&offset=400"))
    }

    @Test
    fun recordHistoryReturnsNextCursorAndSendsItAsBefore() = runBlocking {
        val transport = FakeWorkerTransport { request ->
            if (request.url.contains("before=")) {
                WorkerResponse(200, """{"history":[],"next":null}""")
            } else {
                WorkerResponse(
                    200,
                    """{"history":[{"id":7,"batchId":3,"op":"update","changedFields":["title"],
                        "editorName":"P","createdAt":1700000000000,"reverted":false}],
                        "next":"1700000000000|7"}"""
                )
            }
        }
        val api = EditApi(http(transport), AuthService(context))

        val first = api.recordHistory("Song", "s1")
        assertEquals(listOf(7), first.entries.map { it.id })
        assertEquals("1700000000000|7", first.next)

        val second = api.recordHistory("Song", "s1", before = first.next)
        assertNull("next が null なら最後まで読んだ", second.next)
        val url = transport.requests[1].url
        assertTrue(url, url.endsWith("/master/Song/s1/history?limit=30&before=1700000000000%7C7"))
    }

    @Test
    fun recordHistoryFromOldServerHasNoNext() = runBlocking {
        // 古いサーバは next を返さない。続きは無いものとして扱う。
        val transport = FakeWorkerTransport { WorkerResponse(200, """{"history":[]}""") }
        assertNull(EditApi(http(transport), AuthService(context)).recordHistory("Song", "s1").next)
    }
}
