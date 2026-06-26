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

    @ColumnInfo(name = "event_type")
    val eventType: String,

    @ColumnInfo(name = "is_streaming")
    val isStreaming: Boolean
)
