package com.fugaif.imaslivedb.data.local

import android.content.Context
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/** アプリ内レビューを出す条件。iOS `ReviewPrompt` と同じ (参加登録 3 回・初回から 3 日・120 日空け・版ごと 1 回)。 */
@RunWith(RobolectricTestRunner::class)
class ReviewPromptTest {

    private val context: Context = RuntimeEnvironment.getApplication()
    private var clock = 1_000_000_000_000L
    private fun prompt(version: String = "1.0") = ReviewPrompt(context, version) { clock }
    private fun days(n: Long) = n * 86_400_000L

    @After fun clear() {
        context.getSharedPreferences("review_prompt", Context.MODE_PRIVATE).edit().clear().commit()
    }

    private fun ready(p: ReviewPrompt) {
        p.registerLaunch()
        repeat(3) { p.noteMilestone() }
        clock += days(3)
    }

    @Test fun waitsForThreeAttendanceMarks() {
        val p = prompt()
        p.registerLaunch()
        repeat(2) { p.noteMilestone() }
        clock += days(10)
        assertFalse(p.shouldAsk())
        p.noteMilestone()
        assertTrue(p.shouldAsk())
    }

    @Test fun waitsThreeDaysFromFirstLaunch() {
        val p = prompt()
        p.registerLaunch()
        repeat(3) { p.noteMilestone() }
        clock += days(3) - 1
        assertFalse(p.shouldAsk())
        clock += 1
        assertTrue(p.shouldAsk())
    }

    @Test fun laterLaunchKeepsFirstLaunchDate() {
        val p = prompt()
        p.registerLaunch()
        clock += days(2)
        p.registerLaunch()
        repeat(3) { p.noteMilestone() }
        clock += days(1)
        assertTrue(p.shouldAsk())
    }

    @Test fun asksOncePerVersion() {
        val p = prompt()
        ready(p)
        assertTrue(p.shouldAsk())
        clock += days(365)
        assertFalse(p.shouldAsk())
    }

    @Test fun waitsCooldownEvenOnNewVersion() {
        ready(prompt("1.0"))
        assertTrue(prompt("1.0").shouldAsk())
        clock += days(120) - 1
        assertFalse(prompt("1.1").shouldAsk())
        clock += 1
        assertTrue(prompt("1.1").shouldAsk())
    }
}
