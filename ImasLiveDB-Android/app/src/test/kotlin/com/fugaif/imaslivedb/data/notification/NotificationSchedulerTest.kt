package com.fugaif.imaslivedb.data.notification

import android.Manifest
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/** 通知の予定表を作れなかったとき、今の予約を消さずに残す (RedTeam A-M2)。 */
@RunWith(RobolectricTestRunner::class)
class NotificationSchedulerTest {

    private val app = RuntimeEnvironment.getApplication()

    @Test
    fun failedPlanKeepsTheCurrentReservations() = runBlocking {
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        val prefs = NotificationPrefs(app)
        prefs.setScheduledIds(listOf("bday_a", "monday_meme_0"))

        NotificationScheduler.rescheduleAll(app, NotificationScheduler.RescheduleReason.REFRESH) { _, _, _ -> throw IllegalStateException("snapshot unavailable") }

        assertEquals(setOf("bday_a", "monday_meme_0"), prefs.scheduledIds().toSet())
    }

    @Test
    fun successfulPlanReplacesTheReservations() = runBlocking {
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        val prefs = NotificationPrefs(app)
        prefs.setScheduledIds(listOf("bday_a"))

        NotificationScheduler.rescheduleAll(app, NotificationScheduler.RescheduleReason.REFRESH) { _, _, _ -> emptyList() }

        assertEquals(emptyList<String>(), prefs.scheduledIds())
    }

    /** OFF にした直後は、予定表を作れなくても予約を消す (OFF にした通知が鳴り続けない)。 */
    @Test
    fun failedPlanAfterTurningOffClearsTheReservations() = runBlocking {
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        val prefs = NotificationPrefs(app)
        prefs.setScheduledIds(listOf("bday_a"))

        NotificationScheduler.rescheduleAll(app, NotificationScheduler.RescheduleReason.SETTING_TURNED_OFF) { _, _, _ ->
            throw IllegalStateException("snapshot unavailable")
        }

        assertEquals(emptyList<String>(), prefs.scheduledIds())
    }

    /** 規則の表 (iOS NotificationPendingUpdateTests と同じ)。 */
    @Test
    fun pendingUpdateTable() {
        val s = NotificationScheduler
        val refresh = NotificationScheduler.RescheduleReason.REFRESH
        val off = NotificationScheduler.RescheduleReason.SETTING_TURNED_OFF
        assertEquals(NotificationScheduler.PendingUpdate.REPLACE, s.pendingUpdate(true, true, refresh))
        assertEquals(NotificationScheduler.PendingUpdate.KEEP, s.pendingUpdate(true, false, refresh))
        assertEquals(NotificationScheduler.PendingUpdate.CLEAR, s.pendingUpdate(true, false, off))
        assertEquals(NotificationScheduler.PendingUpdate.CLEAR, s.pendingUpdate(false, false, refresh))
    }
}
