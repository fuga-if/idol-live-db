package com.fugaif.imaslivedb.data.model

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * [DailyPick] の単体テスト。iOS の `DailyPickTests` と同じ観点。
 *
 * 日付キーは `game_streak_v1` に保存済みの文字列と突き合わせる契約なので、
 * 表記が 1 文字でも変わると既存ユーザーの連続記録が黙って切れる。
 * ここでは「コアの表記」と「置換前に使っていた [DateTimeFormatter.ISO_LOCAL_DATE]」が
 * 一致し続けること (= 移送でユーザーの記録が壊れないこと) も併せて固定する。
 */
class DailyPickTest {

    // --- dayKey ---

    @Test fun dayKeyIsZeroPadded() {
        assertEquals("2026-01-05", DailyPick.dayKey(LocalDate.of(2026, 1, 5)))
        assertEquals("2026-12-31", DailyPick.dayKey(LocalDate.of(2026, 12, 31)))
    }

    /** 置換前の書式 (ISO_LOCAL_DATE) と同じ文字列であること = 保存済みキーと突き合う。 */
    @Test fun dayKeyMatchesLegacyIsoFormat() {
        listOf(
            LocalDate.of(2026, 1, 5),
            LocalDate.of(2026, 8, 26),
            LocalDate.of(2024, 2, 29),
            LocalDate.of(1999, 11, 9)
        ).forEach { date ->
            assertEquals(date.format(DateTimeFormatter.ISO_LOCAL_DATE), DailyPick.dayKey(date))
        }
    }

    // --- previousDayKey ---

    @Test fun previousDayKeyGoesBackOneDay() {
        assertEquals("2026-08-25", DailyPick.previousDayKey(LocalDate.of(2026, 8, 26)))
    }

    /** 月またぎ・年またぎはカレンダー任せ (コアでグレゴリオ演算をしない理由)。 */
    @Test fun previousDayKeyCrossesMonthAndYear() {
        assertEquals("2026-07-31", DailyPick.previousDayKey(LocalDate.of(2026, 8, 1)))
        assertEquals("2025-12-31", DailyPick.previousDayKey(LocalDate.of(2026, 1, 1)))
    }

    /** うるう日も落とさない (2/29 の前日は 2/28、3/1 の前日は 2/29)。 */
    @Test fun previousDayKeyHandlesLeapDay() {
        assertEquals("2024-02-28", DailyPick.previousDayKey(LocalDate.of(2024, 2, 29)))
        assertEquals("2024-02-29", DailyPick.previousDayKey(LocalDate.of(2024, 3, 1)))
    }
}
