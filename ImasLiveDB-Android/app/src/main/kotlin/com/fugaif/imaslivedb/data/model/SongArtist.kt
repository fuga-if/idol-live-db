package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity

@Entity(
    tableName = "song_artists",
    primaryKeys = ["song_id", "idol_id", "role"]
)
data class SongArtist(
    @ColumnInfo(name = "song_id")
    val songId: String,

    @ColumnInfo(name = "idol_id")
    val idolId: String,

    @ColumnInfo(name = "role")
    val role: String
)
