package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo

/** カレンダー用: 月内の公演 (イベント名・ブランド付き)。 */
data class CalShowRow(
    @ColumnInfo(name = "show_id") val showId: String,
    @ColumnInfo(name = "date") val date: String,
    @ColumnInfo(name = "show_name") val showName: String,
    @ColumnInfo(name = "event_id") val eventId: String,
    @ColumnInfo(name = "event_name") val eventName: String,
    @ColumnInfo(name = "brand_id") val brandId: String?
)

/** カレンダー用: 月内にリリースされた曲。 */
data class CalReleaseRow(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "title") val title: String,
    @ColumnInfo(name = "release_date") val releaseDate: String,
    @ColumnInfo(name = "brand_id") val brandId: String?
)

/** カレンダー用: 月内に誕生日を迎えるアイドル。 */
data class CalBirthdayRow(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "brand_id") val brandId: String,
    @ColumnInfo(name = "birthday") val birthday: String
)

/** カレンダー用: 月内に誕生日を迎える事務員。 */
data class CalStaffBirthdayRow(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "brand_id") val brandId: String,
    @ColumnInfo(name = "birthday") val birthday: String,
    @ColumnInfo(name = "role") val role: String?
)

/** カレンダー用: 月内に該当する記念日。 */
data class CalAnniversaryRow(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "label") val label: String,
    @ColumnInfo(name = "date") val date: String,
    @ColumnInfo(name = "brand_id") val brandId: String,
    @ColumnInfo(name = "kind") val kind: String
)

/** チケット日程の種別 (カレンダーに出す申込締切 / 当落発表)。iOS `TicketDateKind` の移植。 */
enum class TicketDateKind(val label: String) {
    DEADLINE("申込締切"),
    LOTTERY("当落発表")
}

/** カレンダー用: チケット日程 1 件 (events の ticket_deadline / ticket_lottery_date 由来)。 */
data class TicketCalendarRow(
    val eventId: String,
    val eventName: String,
    val brandColor: String?,
    /** YYYY-MM-DD */
    val date: String,
    val kind: TicketDateKind,
    val url: String?
)

/** カレンダー用: チケット受付期間 (受付開始 → 申込締切) の日跨ぎスパン。 */
data class TicketPeriodRow(
    val eventId: String,
    val eventName: String,
    val brandColor: String?,
    /** 受付開始 YYYY-MM-DD */
    val start: String,
    /** 申込締切 YYYY-MM-DD */
    val end: String,
    val url: String?
)
