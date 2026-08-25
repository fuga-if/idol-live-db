package com.fugaif.imaslivedb.data.model

/**
 * カレンダーの 1 エントリ (iOS `CalendarEntry` の移植。端末カレンダー由来の `personal` は
 * iOS 専用なので無い)。
 *
 * 生成は [com.fugaif.imaslivedb.data.repository.CalendarRepository]。並びは共有コアが
 * (ソート日付, 種別順位) で確定させたものが正で、受け取った順序をそのまま保つこと。
 */
sealed class CalendarEntry {
    /**
     * このエントリを日グリッドのどこに置くかを決める暦日 ("yyyy-MM-dd")。
     *
     * 誕生日・記念日は「表示範囲の年に展開した実出現日」で、起点日ではない。
     * [TicketPeriod] だけは帯の開始日で、被覆する各日への展開は表示側が行う
     * (iOS `CalendarView.groupByDate` と同じ分担)。
     */
    abstract val date: String

    data class Show(override val date: String, val row: CalShowRow) : CalendarEntry()

    /** 同日リリース曲まとめ。並びは title_kana 昇順 (NULL 先頭)。 */
    data class Release(override val date: String, val songs: List<CalReleaseRow>) : CalendarEntry()

    data class Birthday(override val date: String, val row: CalBirthdayRow) : CalendarEntry()

    data class StaffBirthday(override val date: String, val row: CalStaffBirthdayRow) : CalendarEntry()

    /** ブランド/アプリ記念日。[years] は [date] の年から見た周年数 (起点年当日は 0)。 */
    data class Anniversary(
        override val date: String,
        val row: CalAnniversaryRow,
        val years: Int
    ) : CalendarEntry()

    /** チケット日程の単日点 (申込締切 / 当落発表)。 */
    data class Ticket(override val date: String, val row: TicketCalendarRow) : CalendarEntry()

    /** チケット受付期間の日跨ぎ帯。[date] は受付開始日。 */
    data class TicketPeriod(override val date: String, val row: TicketPeriodRow) : CalendarEntry()
}
