package com.fugaif.imaslivedb.data.producercard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.imas_core.StreetpassTuning
import uniffi.imas_core.streetpassTuning

/** すれちがいの待ち行列 (次に繋いでよい時刻・古い相手と溢れた相手の捨て方・同じ相手は 1 つ)。 */
class StreetPassPeerQueueTest {
    private val tuning = StreetpassTuning(
        reconnectAfterReadSeconds = 3600u, reconnectAfterFailureSeconds = 180u, queueMax = 3u,
        queueStaleSeconds = 20u, connectTimeoutSeconds = 10u, mtuWaitSeconds = 2u, tickSeconds = 60u
    )

    @Test
    fun sameDeviceIsQueuedOnceAndRefreshed() {
        val q = StreetPassPeerQueue<String>(tuning)
        assertTrue(q.offer("a", "A", 0))
        assertFalse("見つけ直しは入れ直さない (Main に移らない)", q.offer("a", "A", 15_000))
        assertEquals(1, q.size())
        // 見つけ直しで時刻が新しくなったので、最初に見つけてから 20 秒を過ぎても捨てない。
        assertEquals("a", q.take(30_000)?.first)
    }

    @Test
    fun staleAndOverflowAreDropped() {
        val q = StreetPassPeerQueue<String>(tuning)
        q.offer("old", "O", 0)
        q.offer("b", "B", 10_000)
        assertEquals("20 秒より古いものは捨てる", "b", q.take(25_000)?.first)
        assertNull(q.take(25_000))

        listOf("1", "2", "3", "4").forEachIndexed { i, id -> q.offer(id, id, i.toLong()) }
        assertEquals("長さの上限を超えたら古いものから", 3, q.size())
        assertFalse(q.contains("1"))
        assertEquals("2", q.take(10)?.first)
    }

    @Test
    fun nextAllowedTimeDependsOnOutcome() {
        val q = StreetPassPeerQueue<String>(tuning)
        q.finished("read", read = true, nowMs = 0)
        q.finished("failed", read = false, nowMs = 0)
        assertFalse(q.offer("failed", "F", 179_000))
        assertTrue("失敗は 180 秒後から", q.offer("failed", "F", 180_000))
        assertFalse(q.offer("read", "R", 3_599_000))
        assertTrue("読めた相手は 1 時間後から", q.offer("read", "R", 3_600_000))
        q.reset()
        assertEquals(0, q.size())
    }

    @Test
    fun tuningComesFromCore() {
        val core = streetpassTuning()
        assertEquals(3600u, core.reconnectAfterReadSeconds)
        assertEquals(180u, core.reconnectAfterFailureSeconds)
    }
}
