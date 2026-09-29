package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.testing.SeededDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * イベントの出演・欠席 ([EventRepository.fetchEventAttendance]) を、本物の seed で確かめる。
 *
 * 母集団と出席の規則はコアの `eventAttendance` が持つ (iOS も同じものを使う)。Android の
 * 写しは母集団を idol_brands で引いていたので、多重所属の 765AS の 13 人が ML のライブで
 * 「欠席」に並んでいた。
 */
@RunWith(RobolectricTestRunner::class)
class EventAttendanceTest {

    private lateinit var seeded: SeededDatabase
    private lateinit var repository: EventRepository

    @Before
    fun setUp() {
        seeded = SeededDatabase(RuntimeEnvironment.getApplication())
        repository = EventRepository(seeded.db, seeded.snapshots)
    }

    @After
    fun tearDown() {
        seeded.close()
    }

    @Test
    fun attendanceIsTheCoreRecord() = runBlocking {
        val record = seeded.snapshots.query { it.eventAttendance(ML_13TH) }
        assertNotNull(record)
        val attendance = repository.fetchEventAttendance(ML_13TH)
        assertNotNull(attendance)

        assertEquals(record!!.brandIdolIds, attendance!!.brandIdols.map { it.id })
        assertEquals(record.shows.map { it.id }, attendance.shows.map { it.id })
        assertEquals(record.presenceByShow.mapValues { it.value.toSet() }, attendance.presenceByShow)
        assertEquals(record.leadByShow.mapValues { it.value.toSet() }, attendance.leadByShow)
        assertEquals(record.guestByShow.mapValues { it.value.toSet() }, attendance.guestByShow)
        // 塊はコアのものをそのまま (見出し・並び・顔ぶれ)。
        assertEquals(record.groups.map { it.label }, attendance.groups.map { it.label })
        assertEquals(record.groups.map { it.idolIds }, attendance.groups.map { g -> g.idols.map { it.id } })
    }

    /** ML のライブの欠席に、所属が ML でない人 (多重所属の 765AS) を出さない。 */
    @Test
    fun absenteesBelongToTheEventBrand() = runBlocking {
        val attendance = repository.fetchEventAttendance(ML_13TH)
        assertNotNull(attendance)
        val outsiders = attendance!!.absentIdols.filter { it.brandId != "ml" }.map { it.id }
        assertTrue("ML 以外の人が欠席に出ている: $outsiders", outsiders.isEmpty())
    }

    private companion object {
        const val ML_13TH = "ev_the_idolm@ster_million_live_13thlive"
    }
}
