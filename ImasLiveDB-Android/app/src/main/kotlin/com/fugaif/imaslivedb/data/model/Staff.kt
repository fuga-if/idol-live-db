package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/** MIGRATION_4_5 が作る idx_staff_brand / idx_staff_birthday と indices を一致させること
 *  (Room はマイグレーション後の実スキーマとエンティティ由来の期待スキーマを突き合わせるため、
 *  ずれると "Migration didn't properly handle" で起動時クラッシュする)。 */
@Entity(
    tableName = "staff",
    indices = [
        Index(value = ["brand_id"], name = "idx_staff_brand"),
        Index(value = ["birthday"], name = "idx_staff_birthday"),
    ]
)
data class Staff(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "brand_id")
    val brandId: String,

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "name_kana")
    val nameKana: String?,

    @ColumnInfo(name = "name_romaji")
    val nameRomaji: String?,

    @ColumnInfo(name = "role")
    val role: String?,

    @ColumnInfo(name = "birthday")
    val birthday: String?,

    @ColumnInfo(name = "sort_order", defaultValue = "0")
    val sortOrder: Int = 0
)
