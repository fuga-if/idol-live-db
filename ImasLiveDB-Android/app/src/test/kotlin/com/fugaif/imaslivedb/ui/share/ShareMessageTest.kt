package com.fugaif.imaslivedb.ui.share

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.imas_core.sharePollInvitePayload
import uniffi.imas_core.sharePollUrl

/**
 * 共有の包み ([ShareMessage]) がコアの答えをそのまま返すことのスモークテスト。
 * 文面と URL の規則はコア (share_text) のテストが持つ。
 */
class ShareMessageTest {

    @Test
    fun pollInviteIsTheCoreAnswerWithTheLinkToThePoll() {
        val payload = ShareMessage.pollInvitePayload("poll 1", "推し曲", endsAtMs = Long.MAX_VALUE, isActive = true)

        // 締切が未知 (Long.MAX_VALUE) の値は「締切なし」として渡る。
        assertEquals(sharePollInvitePayload("poll 1", "推し曲", null, true, 0), payload)
        assertEquals(sharePollUrl("poll 1"), payload.url)
        assertTrue(payload.message.contains("推し曲"))
    }
}
