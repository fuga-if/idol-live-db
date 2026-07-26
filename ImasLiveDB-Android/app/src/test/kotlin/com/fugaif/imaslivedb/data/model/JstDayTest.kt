package com.fugaif.imaslivedb.data.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset

/**
 * [JstDay] の単体テスト。iOS の `JSTDayTests` と 1:1。
 * 「今日」の判定が端末のタイムゾーンに引きずられないこと、日付境界が JST 基準であることを見る。
 */
class JstDayTest {

    /** UTC の絶対時刻から Clock を作る (端末 TZ に依存しない固定値)。 */
    private fun at(iso: String): Clock =
        Clock.fixed(Instant.parse(iso), ZoneOffset.UTC)

    // --- today ---

    /** JST 15:00 (= UTC 06:00) は当然その日。 */
    @Test fun todayInMiddleOfJstDay() {
        assertEquals("2026-07-26", JstDay.today(at("2026-07-26T06:00:00Z")))
    }

    /** JST 00:01 (= 前日 UTC 15:01) は既に翌日扱い。 */
    @Test fun todayJustAfterJstMidnight() {
        assertEquals("2026-07-26", JstDay.today(at("2026-07-25T15:01:00Z")))
    }

    /** JST 23:59 (= UTC 14:59) はまだその日。 */
    @Test fun todayJustBeforeJstMidnight() {
        assertEquals("2026-07-26", JstDay.today(at("2026-07-26T14:59:00Z")))
    }

    /**
     * ハワイ (UTC-10) では現地 7/25 だが、JST では 7/26。
     * 端末 TZ に引きずられると日本で終わった公演が「これから」に出てしまう。
     */
    @Test fun todayIsJstRegardlessOfDeviceTimeZone() {
        // UTC 2026-07-26 01:00 = ハワイ 07-25 15:00 = JST 07-26 10:00
        assertEquals("2026-07-26", JstDay.today(at("2026-07-26T01:00:00Z")))
    }

    /** 月またぎ / 年またぎでもゼロ埋め書式が崩れない。 */
    @Test fun todayFormatAcrossBoundaries() {
        assertEquals("2026-01-01", JstDay.today(at("2025-12-31T15:00:00Z")))
        assertEquals("2026-01-09", JstDay.today(at("2026-01-08T15:00:00Z")))
    }

    // --- isTodayOrLater ---

    /** 開催日当日はまだ終わっていないので「未来」扱い。 */
    @Test fun sameDayCountsAsFuture() {
        assertTrue(JstDay.isTodayOrLater("2026-07-26", at("2026-07-26T06:00:00Z")))
    }

    @Test fun pastDateIsNotFuture() {
        assertFalse(JstDay.isTodayOrLater("2026-07-25", at("2026-07-26T06:00:00Z")))
    }

    @Test fun futureDateIsFuture() {
        assertTrue(JstDay.isTodayOrLater("2026-08-01", at("2026-07-26T06:00:00Z")))
    }

    /** 日付未定 (空文字) は未来にしない。 */
    @Test fun emptyDateIsNotFuture() {
        assertFalse(JstDay.isTodayOrLater("", at("2026-07-26T06:00:00Z")))
    }

    /** ハワイにいても、日本で今日の公演は「未来」のまま。 */
    @Test fun sameDayIsFutureEvenWhenDeviceIsBehindJst() {
        assertTrue(JstDay.isTodayOrLater("2026-07-26", at("2026-07-26T01:00:00Z")))
    }

    // --- date ---

    /** 日数差の計算に使う LocalDate 版も同じ境界。 */
    @Test fun dateMatchesTodayString() {
        val clock = at("2026-07-25T15:01:00Z")
        assertEquals(JstDay.today(clock), JstDay.date(clock).toString())
    }
}
