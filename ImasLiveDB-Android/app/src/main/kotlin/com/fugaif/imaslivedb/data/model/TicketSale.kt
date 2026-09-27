package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * チケット受付 (マスタ)。**みんなで共有する事実**。
 *
 * 判定・並び・注目受付・期間文字列・検査文言は一切ここに持たせない。共有コア
 * (`uniffi.imas_core.SnapshotStore.ticketSalesForEvent` / `ticketSaleSpotlight` /
 * `ticketSaleDeadlines`、`validateTicketSaleDraft`) が判断し、この行はその材料
 * (CloudKit の写し) を保存するだけ。
 *
 * [showIds] はカンマ区切りの show id (空/欠損 = 全公演対象)。[kind] は
 * `lottery` / `first_come` / `resale` / `same_day` の生値で、検査はしない
 * (取り込みは寛容にし、検査は domain とローダが持つ — 共有コアの `CkTicketSaleRow` と同じ理由)。
 *
 * FK は宣言しない (他のマスタ表と揃えてあり、親が後から届く差分同期で子行が
 * 1 件ずつ落ちるのを避けるため。整合はコアのローダが読む時に見る)。
 */
@Entity(
    tableName = "ticket_sales",
    indices = [Index(name = "idx_ticket_sales_event", value = ["event_id"])]
)
data class TicketSale(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "event_id")
    val eventId: String,

    /** カンマ区切りの show id。空/欠損 = 全公演対象。 */
    @ColumnInfo(name = "show_ids")
    val showIds: String? = null,

    /** `lottery` / `first_come` / `resale` / `same_day` (のはず。検査しない)。 */
    @ColumnInfo(name = "kind")
    val kind: String,

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "starts_at")
    val startsAt: String? = null,

    @ColumnInfo(name = "ends_at")
    val endsAt: String? = null,

    @ColumnInfo(name = "result_at")
    val resultAt: String? = null,

    @ColumnInfo(name = "url")
    val url: String? = null,

    @ColumnInfo(name = "note")
    val note: String? = null,

    @ColumnInfo(name = "source_url")
    val sourceUrl: String,

    @ColumnInfo(name = "sort_order", defaultValue = "0")
    val sortOrder: Long = 0
)
