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

/**
 * チケット日程の種別 (カレンダーに出す申込締切 / 当落発表 / 配信アーカイブ終了)。
 * コアの `CalendarTicketKind` の移植 (iOS `TicketDateKind` と対応。受付開始の単日点と
 * 受付期間の帯はコアから廃止され、チケット画面にまとまった)。
 */
enum class TicketDateKind {
    DEADLINE,
    LOTTERY,
    /** 配信のアーカイブ (見逃し配信) を見られる最後の日。コアには対応する種別が無く、固定文言。 */
    ARCHIVE_END;

    /**
     * 語はコアの vocabulary (`TICKET_DATES`)。列名は `ticket_sales` の実列
     * (`ends_at` / `result_at`) で引く (H3: 廃止済みの `events` 列名では引けない)。
     */
    val label: String
        get() = when (this) {
            DEADLINE -> Vocab.ticketDate("ends_at")?.label.orEmpty()
            LOTTERY -> Vocab.ticketDate("result_at")?.label.orEmpty()
            ARCHIVE_END -> "アーカイブ終了"
        }
}

/** カレンダー用: チケット日程 1 件 (`ticket_sales` の期限日、または配信アーカイブの終了日)。 */
data class TicketCalendarRow(
    val eventId: String,
    val eventName: String,
    val brandColor: String?,
    /** YYYY-MM-DD */
    val date: String,
    val kind: TicketDateKind,
    /** 申込リンク (`ticket_sales.url`)。アーカイブ終了では null。 */
    val url: String?,
    val saleId: String,
    val saleName: String,
    /** 受付の種別。アーカイブ終了では null。 */
    val saleKind: uniffi.imas_core.TicketSaleKind?,
    /**
     * コアが組んだ表示文字列 (`"{event_name} ({sale_name})"`, M2)。
     * ライブ名を出すのに Kotlin 側で組み立て直さず、これをそのまま使う。
     */
    val label: String
)
