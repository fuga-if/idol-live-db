package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity

@Entity(
    tableName = "idol_brands",
    primaryKeys = ["idol_id", "brand_id"]
)
data class IdolBrand(
    @ColumnInfo(name = "idol_id")
    val idolId: String,

    @ColumnInfo(name = "brand_id")
    val brandId: String,

    @ColumnInfo(name = "is_primary")
    val isPrimary: Boolean
)
