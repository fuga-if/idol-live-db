package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "brands")
data class Brand(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "short_name")
    val shortName: String,

    @ColumnInfo(name = "color")
    val color: String?,

    @ColumnInfo(name = "sort_order")
    val sortOrder: Int
)

/**
 * 判子の中に出す短い略称 (3〜4 字。iOS `Brand.iconText`)。
 * 公式ロゴは版権上使えないので、ブランドの色の輪に「765」「ミリ」等を載せる。
 */
val Brand.iconText: String
    get() = when (id) {
        "765as" -> "765"
        "961" -> "961"
        "876" -> "876"
        "cg" -> "デレ"
        "ml" -> "ミリ"
        "sidem" -> "SideM"
        "sc" -> "シャニ"
        "gakuen" -> "学マス"
        "valv" -> "ヴィ"
        "other" -> "他"
        else -> shortName.take(2)
    }
