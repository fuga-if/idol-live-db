package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity

@Entity(
    tableName = "show_cast",
    primaryKeys = ["show_id", "idol_id"]
)
data class ShowCast(
    @ColumnInfo(name = "show_id")
    val showId: String,

    @ColumnInfo(name = "idol_id")
    val idolId: String,

    @ColumnInfo(name = "cast_role")
    val castRole: String?
)
