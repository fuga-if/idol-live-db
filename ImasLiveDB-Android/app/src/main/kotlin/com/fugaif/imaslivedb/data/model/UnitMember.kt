package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity

@Entity(
    tableName = "unit_members",
    primaryKeys = ["unit_id", "idol_id"]
)
data class UnitMember(
    @ColumnInfo(name = "unit_id")
    val unitId: String,

    @ColumnInfo(name = "idol_id")
    val idolId: String
)
