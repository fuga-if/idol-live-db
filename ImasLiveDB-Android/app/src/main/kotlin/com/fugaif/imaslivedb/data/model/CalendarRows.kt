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
 * チケット日程の種別 (カレンダーに出す受付開始 / 申込締切 / 当落発表)。
 * コアの `CalendarTicketKind` の移植 (iOS `TicketDateKind` と対応)。
 */
enum class TicketDateKind {
    /** 受付開始 (締切が無い/開始より前の受付だけの単日点)。 */
    START,
    DEADLINE,
    LOTTERY;

    /**
     * 語はコアの vocabulary (`TICKET_DATES`)。列名は `ticket_sales` の実列
     * (`starts_at` / `ends_at` / `result_at`) で引く (H3: 廃止済みの `events` 列名では引けない)。
     */
    val label: String
        get() = when (this) {
            START -> Vocab.ticketDate("starts_at")?.label.orEmpty()
            DEADLINE -> Vocab.ticketDate("ends_at")?.label.orEmpty()
            LOTTERY -> Vocab.ticketDate("result_at")?.label.orEmpty()
        }
}

/** カレンダー用: チケット日程 1 件 (`ticket_sales` の 1 行につき、期間帯にならない日程)。 */
data class TicketCalendarRow(
    val eventId: String,
    val eventName: String,
    val brandColor: String?,
    /** YYYY-MM-DD */
    val date: String,
    val kind: TicketDateKind,
    /** 申込リンク (`ticket_sales.url`)。 */
    val url: String?,
    val saleId: String,
    val saleName: String,
    val saleKind: uniffi.imas_core.TicketSaleKind,
    /**
     * コアが組んだ表示文字列 (`"{event_name} ({sale_name})"`, M2)。
     * ライブ名を出すのに Kotlin 側で組み立て直さず、これをそのまま使う。
     */
    val label: String
)

/**
 * カレンダー用の日跨ぎスパン。チケットの受付期間 (受付開始 → 申込締切) と、配信のアーカイブを
 * 見られる期間の 2 種類がある (帯の描き方は同じ。iOS `TicketPeriodRow` と同じ形)。
 */
data class TicketPeriodRow(
    val eventId: String,
    val eventName: String,
    val brandColor: String?,
    /** 受付開始 YYYY-MM-DD */
    val start: String,
    /** 申込締切 YYYY-MM-DD */
    val end: String,
    val url: String?,
    /** 帯の識別子。受付は受付 id、アーカイブはライブ id と期間から組む。 */
    val saleId: String,
    /** 受付名。アーカイブでは対象公演の短い名 (`DAY1・DAY2`。1 公演のライブは空)。 */
    val saleName: String,
    /** 受付の種別。アーカイブでは null。 */
    val saleKind: uniffi.imas_core.TicketSaleKind?,
    /** コアが組んだ表示文字列 (`"{event_name} ({sale_name})"`, M2)。 */
    val label: String,
    val kind: Kind = Kind.SALE
) {
    enum class Kind {
        /** チケットの受付期間。 */
        SALE,
        /** 配信のアーカイブ (見逃し配信) を見られる期間。 */
        ARCHIVE
    }

    /** 期間の種類の短い呼び名 (`受付` / `アーカイブ`)。月セル・週の終日レーンの頭に付ける。 */
    val kindLabel: String
        get() = when (kind) {
            Kind.SALE -> "受付"
            Kind.ARCHIVE -> "アーカイブ"
        }
}
