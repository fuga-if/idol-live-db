package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "shows",
    indices = [
        Index(name = "idx_shows_event", value = ["event_id"]),
        Index(name = "idx_shows_date", value = ["date"]),
        Index(name = "idx_shows_venue_id", value = ["venue_id"])
    ]
)
data class Show(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "event_id")
    val eventId: String,

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "date")
    val date: String,

    /** 会場の生文字列 (当時名)。venueId が未解決の公演でも表示が壊れないようフォールバックとして残す。 */
    @ColumnInfo(name = "venue")
    val venue: String?,

    /** 会場 ID。名前が変わっても履歴が分断されないよう、同一性はこちらで持つ。配信のみは null。 */
    @ColumnInfo(name = "venue_id")
    val venueId: String? = null,

    /** ホール/構成名 (メインアリーナ / 幕張イベントホール / スタジアムモード 等)。 */
    @ColumnInfo(name = "hall")
    val hall: String? = null,

    /** 配信プラットフォーム (ASOBI STAGE 等)。配信は会場ではないのでここへ逃がす。 */
    @ColumnInfo(name = "stream_platform")
    val streamPlatform: String? = null,

    @ColumnInfo(name = "venue_city")
    val venueCity: String?,

    @ColumnInfo(name = "start_time")
    val startTime: String?,

    @ColumnInfo(name = "sort_order")
    val sortOrder: Int,

    @ColumnInfo(name = "performer_type")
    val performerType: String?
) {
    val isCharacterLive: Boolean get() = performerType == "character"
}
