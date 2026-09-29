package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * ライブ衣装の目録。
 *
 * **画像は持たない。** 版権物を配らない方針なので、衣装は名前と出典で見分ける。
 *
 * [unitId] / [idolId] は「誰のための衣装か」。両方 null なら公演の共通衣装、
 * [unitId] があればその編成の衣装、[idolId] があればその人のソロ衣装。
 * 「実際に誰が着たか」は [CostumeWear] 側にあり、ここは目録としての帰属だけ。
 */
@Entity(
    tableName = "costumes",
    indices = [Index(name = "idx_costumes_brand", value = ["brand_id"])]
)
data class Costume(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "brand_id")
    val brandId: String? = null,

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "name_kana")
    val nameKana: String? = null,

    @ColumnInfo(name = "unit_id")
    val unitId: String? = null,

    @ColumnInfo(name = "idol_id")
    val idolId: String? = null,

    @ColumnInfo(name = "description")
    val description: String? = null,

    /** 出典 (公式サイト・公式物販ページ等)。二次情報しか無い衣装は入れない。 */
    @ColumnInfo(name = "source_url")
    val sourceUrl: String? = null,

    @ColumnInfo(name = "sort_order")
    val sortOrder: Int = 0
)

/**
 * その公演で衣装が着られた記録。
 *
 * **粗さをそのまま持てる形にしてある。** 衣装は「公演で使われたのは確かだが
 * どの曲かまでは分からない」ことが多いので、[setlistItemId] は null を許す。
 * [idolId] が null なら「その場の全員」= 共通衣装で、入っていればその人だけ
 * (同じ曲でユニットごとに違う衣装、という記録ができる)。
 *
 * どちらの null も欠損ではなく正規の状態なので、同期で捨ててはいけない。
 */
@Entity(
    tableName = "costume_wears",
    indices = [
        Index(name = "idx_costume_wears_costume", value = ["costume_id"]),
        Index(name = "idx_costume_wears_show", value = ["show_id"]),
        Index(name = "idx_costume_wears_item", value = ["setlist_item_id"])
    ]
)
data class CostumeWear(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "costume_id")
    val costumeId: String,

    @ColumnInfo(name = "show_id")
    val showId: String,

    /** null = 公演では使われたが、どの曲かは特定していない。 */
    @ColumnInfo(name = "setlist_item_id")
    val setlistItemId: String? = null,

    /** null = その場の全員 (共通衣装)。 */
    @ColumnInfo(name = "idol_id")
    val idolId: String? = null,

    @ColumnInfo(name = "sort_order")
    val sortOrder: Int = 0
)
