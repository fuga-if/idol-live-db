package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "events")
data class Event(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "brand_id")
    val brandId: String?,

    @ColumnInfo(name = "name")
    val name: String,

    /** ライブ名の読み。漢字のライブ名をかなで引けるようにする (曲・アイドルと同じ扱い)。 */
    @ColumnInfo(name = "name_kana")
    val nameKana: String? = null,

    @ColumnInfo(name = "event_type")
    val eventType: String,

    @ColumnInfo(name = "is_streaming")
    val isStreaming: Boolean,

    @ColumnInfo(name = "is_solo", defaultValue = "1")
    val isSolo: Boolean = true,

    @ColumnInfo(name = "kind", defaultValue = "'live'")
    val kind: String = "live",

    // 廃止・読まない・書かない。チケット受付の日程は `ticket_sales` (TicketSale) が正
    // (SnapshotStore.ticketSalesForEvent / ticketSaleSpotlight)。列は Room の実 DB 照合に
    // 要るので残す (Room 2.6.1 は宣言と実 DB の列を厳密一致で照合するため、消すと
    // 移行のたび起動不能になる)。旧版アプリが CloudKit の Event からまだ読み書きするので
    // 同期 (SyncMappers.events) は引き続きこの列へ写す。
    @ColumnInfo(name = "ticket_open_date")
    val ticketOpenDate: String? = null,

    @ColumnInfo(name = "ticket_deadline")
    val ticketDeadline: String? = null,

    @ColumnInfo(name = "ticket_lottery_date")
    val ticketLotteryDate: String? = null,

    @ColumnInfo(name = "ticket_url")
    val ticketUrl: String? = null,

    @ColumnInfo(name = "joint_brand_ids")
    val jointBrandIds: String? = null
)
