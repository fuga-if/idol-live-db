package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "setlist_items",
    indices = [
        Index(name = "idx_setlist_items_show", value = ["show_id"]),
        Index(name = "idx_setlist_items_song", value = ["song_id"])
    ]
)
data class SetlistItem(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "show_id")
    val showId: String,

    @ColumnInfo(name = "song_id")
    val songId: String,

    @ColumnInfo(name = "position")
    val position: Int,

    @ColumnInfo(name = "section")
    val section: String?,

    @ColumnInfo(name = "notes")
    val notes: String?,

    @ColumnInfo(name = "unit_name")
    val unitName: String?
)
