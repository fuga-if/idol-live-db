package com.fugaif.imaslivedb.data.model

import com.fugaif.imaslivedb.data.community.CommunityApi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/**
 * [WeightedSampling] の単体テスト。iOS の `WeightedSamplingTests` と 1:1。
 *
 * 「おすすめが毎回同じにならない」「近い曲が中心に出る」「遠い曲もたまに出る」の
 * 3 つが同時に成り立つことを見る。1 つでも欠けると機能として意味が変わる。
 */
class WeightedSamplingTest {

    private data class Candidate(val id: String, val score: Double)

    /** 実データを模した候補: 近い曲 1、中くらい 2、少しだけ被っている曲 3。 */
    private val pool = listOf(
        Candidate("core", 0.33),
        Candidate("pop", 0.20),
        Candidate("mid", 0.15),
        Candidate("minor", 0.12),
        Candidate("graze1", 0.08),
        Candidate("graze2", 0.07),
    )

    private fun draw(seed: Int, count: Int = 3): List<String> =
        WeightedSampling.pick(pool, count, Random(seed)) { it.score }.map { it.id }

    // --- 基本の性質 ---

    @Test fun returnsRequestedCount() {
        assertEquals(3, draw(1).size)
    }

    @Test fun neverRepeatsTheSameItem() {
        for (seed in 0 until 50) {
            val picked = draw(seed)
            assertEquals("同じ曲が 2 回出た: $picked", picked.size, picked.toSet().size)
        }
    }

    @Test fun countLargerThanPoolReturnsEverything() {
        val picked = WeightedSampling.pick(pool, 99, Random(3)) { it.score }
        assertEquals(pool.map { it.id }.toSet(), picked.map { it.id }.toSet())
    }

    @Test fun zeroCountReturnsEmpty() {
        assertTrue(WeightedSampling.pick(pool, 0, Random(3)) { it.score }.isEmpty())
    }

    @Test fun emptyPoolReturnsEmpty() {
        assertTrue(WeightedSampling.pick(emptyList<Candidate>(), 3, Random(3)) { it.score }.isEmpty())
    }

    // --- 「毎回同じにならない」 ---

    @Test fun resultVariesAcrossDraws() {
        val results = (0 until 40).map { draw(it).joinToString(",") }.toSet()
        assertTrue("毎回同じ組み合わせしか出ていない", results.size > 1)
    }

    // --- 「近い曲が中心」かつ「遠い曲もたまに出る」 ---

    @Test fun higherWeightAppearsMoreOften() {
        val counts = mutableMapOf<String, Int>()
        for (seed in 0 until 600) {
            for (id in draw(seed)) counts[id] = (counts[id] ?: 0) + 1
        }
        assertTrue(
            "最も近い曲が最も遠い曲より出にくい: $counts",
            (counts["core"] ?: 0) > (counts["graze2"] ?: 0))
        assertTrue("$counts", (counts["core"] ?: 0) > (counts["minor"] ?: 0))
    }

    /** 少しだけ被っている曲も出る (完全に締め出されない)。 */
    @Test fun lowWeightItemsStillAppear() {
        val appeared = mutableSetOf<String>()
        for (seed in 0 until 600) appeared.addAll(draw(seed))
        assertTrue("最も弱い候補が一度も出ていない", appeared.contains("graze2"))
        assertEquals("出番のない候補がある: $appeared", pool.size, appeared.size)
    }

    // --- 重み 0 / 負の扱い ---

    @Test fun zeroWeightIsNotPickedWhilePositivesRemain() {
        val items = listOf(Candidate("a", 1.0), Candidate("b", 1.0), Candidate("zero", 0.0))
        for (seed in 0 until 40) {
            val picked = WeightedSampling.pick(items, 2, Random(seed)) { it.score }.map { it.id }
            assertFalse("重み 0 が選ばれた: $picked", picked.contains("zero"))
        }
    }

    @Test fun zeroWeightFillsWhenNothingElseIsLeft() {
        val items = listOf(Candidate("a", 1.0), Candidate("zero", 0.0))
        assertEquals(
            setOf("a", "zero"),
            WeightedSampling.pick(items, 2, Random(5)) { it.score }.map { it.id }.toSet())
    }

    @Test fun negativeWeightIsTreatedAsZero() {
        val items = listOf(Candidate("a", 1.0), Candidate("neg", -3.0))
        assertEquals(
            listOf("a"),
            WeightedSampling.pick(items, 1, Random(5)) { it.score }.map { it.id })
    }

    // --- 旧サーバ互換 (score なし) ---

    /**
     * アプリと Worker は別々に配信されるので、新しいアプリが旧サーバに当たる期間がありうる。
     * score が無くても共有タグ数を重みに代用し、おすすめが空にならないこと。
     */
    @Test fun legacyEntriesFallBackToSharedTags() {
        val legacy = listOf(
            CommunityApi.SimilarSongEntry("b", 3),
            CommunityApi.SimilarSongEntry("c", 2),
            CommunityApi.SimilarSongEntry("d", 1),
        )
        assertEquals(3.0, legacy[0].pickWeight, 0.0)
        val picked = WeightedSampling.pick(legacy, 2, Random(1)) { it.pickWeight }
        assertEquals(2, picked.size)
        assertEquals(2, picked.map { it.songId }.toSet().size)
    }

    @Test fun scoreIsPreferredWhenPresent() {
        val entry = CommunityApi.SimilarSongEntry("b", 7, 0.41)
        assertEquals(0.41, entry.pickWeight, 0.0)
    }
}
