package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

// Named ImasUnit to avoid conflict with kotlin.Unit
@Entity(tableName = "units")
data class ImasUnit(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "brand_id")
    val brandId: String,

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "is_permanent")
    val isPermanent: Boolean,

    @ColumnInfo(name = "name_alt")
    val nameAlt: String?
) {
    val displayName: String
        get() = if (nameAlt != null) "$name / $nameAlt" else name
}
