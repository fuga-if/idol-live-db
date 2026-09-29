package com.fugaif.imaslivedb.ui.events

import com.fugaif.imaslivedb.data.repository.SetlistForecastReading
import com.fugaif.imaslivedb.data.repository.SetlistPredictionVoting
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import uniffi.imas_core.ForecastReason
import uniffi.imas_core.ForecastReasonRecord
import uniffi.imas_core.ForecastShowFlag
import uniffi.imas_core.ForecastShowFlagRecord
import uniffi.imas_core.ForecastSongRecord
import uniffi.imas_core.SetlistForecastRecord

/**
 * セトリ予想の画面の「機械予測」の節 ([SetlistForecastModel])。iOS `SetlistForecastViewModelTests` と 1:1。
 *
 * 点数・順位・理由の規則はコア (`setlist_forecast.rs` の `#[test]`) が持つので、ここでは見ない。
 * 見るのは、みんなの予想に入っている曲を隠すこと・格上げ・失敗したときに節を出さないこと。
 */
@RunWith(RobolectricTestRunner::class)
class SetlistForecastModelTest {

    private class Boom : Exception("boom")

    private class FakeReading(
        private val record: SetlistForecastRecord? = null,
        private val fail: Boolean = false
    ) : SetlistForecastReading {
        override suspend fun setlistForecast(showId: String, limit: Int): SetlistForecastRecord? {
            if (fail) throw Boom()
            return record
        }
    }

    private class FakeVoting(var fail: Boolean = false) : SetlistPredictionVoting {
        val votedSongIds = mutableListOf<String>()
        override suspend fun vote(showId: String, songId: String) {
            if (fail) throw Boom()
            votedSongIds += songId
        }
    }

    private fun song(id: String, rank: Int) = ForecastSongRecord(
        rank = rank.toUInt(), songId = id, title = "曲$id", score = 0.5,
        reasons = listOf(ForecastReasonRecord(ForecastReason.FREQUENTLY_PERFORMED, "よく歌われている"))
    )

    private fun record(songIds: List<String>, flags: List<ForecastShowFlagRecord> = emptyList()) =
        SetlistForecastRecord(
            showId = "show1",
            songs = songIds.mapIndexed { i, id -> song(id, i + 1) },
            flags = flags,
            trainingShowCount = 100u
        )

    private fun model(reading: FakeReading, voting: FakeVoting = FakeVoting()) =
        SetlistForecastModel("show1", reading, voting)

    // ---- みんなの予想に入っている曲を隠す ----

    @Test
    fun hidesSongsAlreadyInPredictions() = runBlocking {
        val m = model(FakeReading(record(listOf("a", "b", "c"))))
        m.load()

        val visible = m.state.value.visibleSongs(setOf("b"))

        assertEquals(listOf("a", "c"), visible.map { it.songId })
        // 順位はコアの答えのまま (詰め直さない)。
        assertEquals(listOf(1u, 3u), visible.map { it.rank })
    }

    @Test
    fun showsAtMostTwentyAfterHiding() = runBlocking {
        val m = model(FakeReading(record((1..30).map { "s$it" })))
        m.load()

        val visible = m.state.value.visibleSongs(setOf("s1", "s2"))

        assertEquals(SetlistForecastModel.DISPLAY_LIMIT, visible.size)
        assertEquals("s3", visible.first().songId)
    }

    // ---- 格上げ ----

    @Test
    fun promoteSuccessRemovesSongFromForecast() = runBlocking {
        val voting = FakeVoting()
        val m = model(FakeReading(record(listOf("a", "b"))), voting)
        m.load()

        m.promote("a")

        assertEquals(listOf("a"), voting.votedSongIds)
        assertEquals(listOf("b"), m.state.value.visibleSongs(emptySet()).map { it.songId })
        assertNull(m.state.value.promotingSongId)
    }

    @Test
    fun promoteFailureKeepsSongAndThrows() = runBlocking {
        val m = model(FakeReading(record(listOf("a", "b"))), FakeVoting(fail = true))
        m.load()

        try {
            m.promote("a")
            fail("投票の失敗は呼び出し側 (画面の既存のエラー表示) に渡す")
        } catch (_: Boom) {
        }

        assertEquals(listOf("a", "b"), m.state.value.visibleSongs(emptySet()).map { it.songId })
        assertNull(m.state.value.promotingSongId)
    }

    // ---- 失敗・対象外は節を出さない ----

    @Test
    fun loadFailureHidesSection() = runBlocking {
        val m = model(FakeReading(fail = true))
        m.load()

        assertEquals("失敗したら節を出さない", SetlistForecastModel.Phase.Unavailable, m.state.value.phase)
        assertTrue(m.state.value.visibleSongs(emptySet()).isEmpty())
    }

    @Test
    fun notForecastableShowHidesSection() = runBlocking {
        val m = model(FakeReading(record = null))
        m.load()

        assertEquals("対象外の公演は節を出さない", SetlistForecastModel.Phase.Unavailable, m.state.value.phase)
    }

    // ---- 出演者未発表の注記 ----

    @Test
    fun castUnannouncedNoteUsesCoreLabel() = runBlocking {
        val flag = ForecastShowFlagRecord(ForecastShowFlag.CAST_UNANNOUNCED, "出演者未発表のため精度が低い")
        val m = model(FakeReading(record(listOf("a"), listOf(flag))))
        m.load()

        assertEquals("出演者未発表のため精度が低い", m.state.value.castUnannouncedNote)
    }
}
