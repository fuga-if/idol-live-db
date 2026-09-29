package com.fugaif.imaslivedb.ui.events

import com.fugaif.imaslivedb.data.repository.SetlistRowMetaResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.imas_core.SetlistRowMetaRecord

/**
 * 同じ公演の行の添え物の読み直しが落ちても、区切りの見出しは前の答えのまま残る。
 * 別の公演に移って落ちたときは、前の公演の答えを持ち越さない (iOS L-8 のテストと同じ)。
 */
class RowMetaCacheTest {

    @Test
    fun failureKeepsTheSameShowsHeadingsButNotAnotherShows() {
        val cache = RowMetaCache()
        cache.loaded("sh1", SetlistRowMetaResult(rowsByItemId = mapOf("i1" to meta("i1", "アンコール"))))

        assertEquals("アンコール", cache.failed("sh1").rowsByItemId["i1"]?.sectionHeading)
        assertTrue(cache.failed("sh2").rowsByItemId.isEmpty())
        // 持ち越さなかった後は、元の公演でも前の答えは戻らない。
        assertTrue(cache.failed("sh1").rowsByItemId.isEmpty())
    }

    private fun meta(itemId: String, heading: String) = SetlistRowMetaRecord(
        itemId = itemId, performerLabel = null, unitNames = emptyList(), isFullCast = false,
        ordinal = 1u, ordinalLabel = "", isFirstPerformance = false, previousDate = null,
        sinceLabel = null, noteGroups = emptyList(), sectionHeading = heading, startsSection = true,
        lineup = null
    )
}
