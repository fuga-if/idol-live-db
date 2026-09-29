package com.fugaif.imaslivedb.ui.edit

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** 語彙に無い種別のイベントを直しても、黙って別の種別に書き換えない (iOS EventEditKindTests と同じ)。 */
class EventEditKindTest {

    @Test
    fun unknownKindKeepsAnUnchangedOption() {
        val options = eventKindEditOptions("future_kind")
        // 選び直さない限り、元の生の値がそのまま状態に残り送り返される。
        assertEquals("future_kind" to "変更しない (future_kind)", options.last())
        assertFalse("受け皿の「その他」は選択肢に出さない", options.any { it.first == "other" })
    }

    @Test
    fun knownKindHasNoExtraOption() {
        val options = eventKindEditOptions("festival")
        assertFalse(options.any { it.second.startsWith("変更しない") })
        assertEquals(options, eventKindEditOptions(null))
    }
}
