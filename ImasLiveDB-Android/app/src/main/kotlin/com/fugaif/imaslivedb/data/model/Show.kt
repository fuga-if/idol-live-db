package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "shows",
    indices = [
        Index(name = "idx_shows_event", value = ["event_id"]),
        Index(name = "idx_shows_date", value = ["date"])
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

    @ColumnInfo(name = "venue")
    val venue: String?,

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
