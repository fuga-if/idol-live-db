package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/** アニバーサリーの種別。raw は DB 格納値。 */
enum class AnniversaryKind(val raw: String) {
    SERVICE_START("service_start"),   // アーケード/モバイルサービス開始
    APP_START("app_start"),           // スマートフォンアプリ配信開始
    ANIME_START("anime_start"),       // TVアニメ放映開始
    MOVIE_RELEASE("movie_release"),   // 劇場版公開
    CD_DEBUT("cd_debut");             // CDデビュー

    companion object {
        fun from(raw: String): AnniversaryKind =
            entries.firstOrNull { it.raw == raw } ?: SERVICE_START
    }
}

@Entity(tableName = "anniversaries")
data class Anniversary(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "brand_id")
    val brandId: String,

    @ColumnInfo(name = "label")
    val label: String,

    /** YYYY-MM-DD 形式。起点年はこの先頭4文字。 */
    @ColumnInfo(name = "date")
    val date: String,

    @ColumnInfo(name = "kind")
    val kind: String,

    @ColumnInfo(name = "sort_order")
    val sortOrder: Int = 0
) {
    /**
     * 指定年における周年数。起点年 > year なら null (未来記念日)。
     * 例: date="2017-06-29", year=2026 → 9
     */
    fun anniversaryYears(year: Int): Int? {
        val startYear = date.take(4).toIntOrNull() ?: return null
        val years = year - startYear
        return if (years < 0) null else years
    }
}
