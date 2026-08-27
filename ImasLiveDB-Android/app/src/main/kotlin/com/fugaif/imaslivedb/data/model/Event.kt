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
) {
    /** `joint_brand_ids` をリストにして返す。null/空文字列は空リスト。 */
    val jointBrandIdList: List<String>
        get() = jointBrandIds?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList()
}
