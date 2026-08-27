package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
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

/**
 * ユニットのバージョンと、その版が有効だった期間。
 *
 * リブート企画 (Project“ReLight”AXE8) のように、ロゴ・キャッチコピー・曲調が変わっても
 * **ユニット自体は同一**という場合がある。[ImasUnit] を 2 行に割ると、メンバーも過去曲も
 * 分断されてしまう。会場の改名を VenueName に内包させたのと同じ形で、版を内包させる。
 *
 * 曲がどの版のものかは [Song.unitVersionId] が持つ (null = 無印)。
 * ユニット単位のフラグでは曲の新旧を区別できないので、版は曲側から指す。
 */
@Entity(
    tableName = "unit_versions",
    indices = [Index(name = "idx_unit_versions_unit", value = ["unit_id"])]
)
data class UnitVersion(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "unit_id")
    val unitId: String,

    /**
     * 版の識別子 ('AXE8' 等)。**版の判定はこれで行う**。
     *
     * 表示名 ([name]) の文字列一致に頼ると、表記揺れや改称で判定が壊れる。
     * 無印の版は null。
     */
    @ColumnInfo(name = "code")
    val code: String? = null,

    /** 表示名 ('Project“ReLight”AXE8' / 'オリジナル')。 */
    @ColumnInfo(name = "name")
    val name: String,

    /** その版のキャッチコピー。 */
    @ColumnInfo(name = "catchphrase")
    val catchphrase: String? = null,

    @ColumnInfo(name = "logo_url")
    val logoUrl: String? = null,

    /** null = 結成時から。 */
    @ColumnInfo(name = "valid_from")
    val validFrom: String? = null,

    /** null = 現行の版。 */
    @ColumnInfo(name = "valid_to")
    val validTo: String? = null,

    @ColumnInfo(name = "sort_order")
    val sortOrder: Int = 0
) {
    /**
     * 指定日 (YYYY-MM-DD) にこの版が有効だったか。
     * 境界は  (切り替え日当日は新しい版を採る)。
     */
    fun isValidOn(date: String): Boolean {
        if (validFrom != null && date < validFrom) return false
        if (validTo != null && date >= validTo) return false
        return true
    }
}
