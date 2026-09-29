package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * ライブ会場 (施設)。iOS `Venue` の 1:1 移植。
 *
 * `shows.venue` は自由文字列で、同じ会場が最大14通りに割れていた
 * (幕張メッセ = `千葉・幕張メッセイベントホール` / `幕張イベントホール` / `幕張メッセ` …)。
 * 名前が変わる会場もある (武蔵野の森総合スポーツプラザ → 京王アリーナTOKYO) ため、
 * 名前ではなく **ID で同一性を持たせて** 履歴が分断されないようにする。
 */
@Entity(tableName = "venues")
data class Venue(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    /** 現行名。過去公演の表示には [VenueName] の当時名を使う。 */
    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "name_kana")
    val nameKana: String? = null,

    @ColumnInfo(name = "prefecture")
    val prefecture: String? = null,

    @ColumnInfo(name = "city")
    val city: String? = null,

    /** 検索用の別名 (改行区切り)。旧名・通称を入れる。 */
    @ColumnInfo(name = "aliases")
    val aliases: String? = null,

    /**
     * 施設の代表キャパ (最大構成)。構成で変わる場合は [VenueHall.capacity] が優先。
     * 出典が取れていない会場は null のまま (推測値を入れない)。
     */
    @ColumnInfo(name = "capacity")
    val capacity: Int? = null,

    @ColumnInfo(name = "sort_order")
    val sortOrder: Int = 0
) {
    /** 検索対象になる別名の配列。 */
    val aliasList: List<String>
        get() = aliases?.split("\n")?.filter { it.isNotBlank() } ?: emptyList()

    /** 「東京・日本武道館」のような地域つき表示。都道府県が無ければ名前だけ。 */
    val displayNameWithArea: String
        get() = if (prefecture.isNullOrEmpty()) name else "$prefecture・$name"

    /** 「14,500人」。キャパ未登録なら null。 */
    val capacityLabel: String?
        get() = capacity?.let { "%,d人".format(it) }
}

/**
 * 会場の名前と、その名前が有効だった期間。
 *
 * 表示は「公演日時点の名前」にする。2021年の公演は「武蔵野の森総合スポーツプラザ」、
 * 2026年の公演は「京王アリーナTOKYO」と出す。チケットや当時の記憶と一致させるため。
 */
@Entity(
    tableName = "venue_names",
    indices = [Index(name = "idx_venue_names_venue", value = ["venue_id"])]
)
data class VenueName(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "venue_id")
    val venueId: String,

    @ColumnInfo(name = "name")
    val name: String,

    /** null = 開業時から。 */
    @ColumnInfo(name = "valid_from")
    val validFrom: String? = null,

    /** null = 現在も使われている名前。 */
    @ColumnInfo(name = "valid_to")
    val validTo: String? = null
) {
    /**
     * 指定日 (YYYY-MM-DD) にこの名前が有効だったか。
     * 境界は `validFrom <= date < validTo` (改名日当日は新しい名前を採る)。
     */
    fun isValidOn(date: String): Boolean {
        if (validFrom != null && date < validFrom) return false
        if (validTo != null && date >= validTo) return false
        return true
    }
}

/**
 * 会場のホール / 構成。
 *
 * キャパは構成で変わる (さいたまスーパーアリーナ: スタジアムモード37,000 /
 * アリーナモード22,500) ため、施設ではなくこちら側で持てるようにする。
 */
@Entity(
    tableName = "venue_halls",
    indices = [Index(name = "idx_venue_halls_venue", value = ["venue_id"])]
)
data class VenueHall(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "venue_id")
    val venueId: String,

    @ColumnInfo(name = "name")
    val name: String,

    /** 出典が取れていないホールは null のまま。 */
    @ColumnInfo(name = "capacity")
    val capacity: Int? = null
)

/**
 * 会場マスタ一式をメモリに載せた解決器 (iOS `VenueDirectory` 相当)。
 *
 * 244施設 + 名前245件 + ホール39件と小さいので一括で読み、公演ごとの引き直し (N+1) を避ける。
 * 「公演日時点の名前」「その構成でのキャパ」の解決はここに集約する。
 */
class VenueDirectory(
    val venues: List<Venue>,
    names: List<VenueName>,
    halls: List<VenueHall>
) {
    private val byId = venues.associateBy { it.id }
    private val namesByVenue = names.groupBy { it.venueId }
    private val hallsByVenue = halls.groupBy { it.venueId }

    companion object {
        val EMPTY = VenueDirectory(emptyList(), emptyList(), emptyList())
    }

    fun venue(id: String?): Venue? = id?.let { byId[it] }

    fun halls(venueId: String): List<VenueHall> = hallsByVenue[venueId] ?: emptyList()

    /**
     * 公演日時点の会場名。改名前の公演には当時の名前を返す。
     * 有効期間の抜けがあっても表示が空にならないよう、該当が無ければ最新の名前に落とす。
     */
    fun nameOn(venueId: String, date: String): String? {
        val candidates = namesByVenue[venueId] ?: return byId[venueId]?.name
        return candidates.firstOrNull { it.isValidOn(date) }?.name
            ?: candidates.maxByOrNull { it.validFrom ?: "" }?.name
            ?: byId[venueId]?.name
    }

    /**
     * 公演の会場表示名。会場が未解決 (配信のみ等) なら生文字列にフォールバックする。
     * ホールがあれば「幕張メッセ 幕張イベントホール」のように併記する。
     */
    fun displayName(show: Show): String? {
        val venueId = show.venueId ?: return show.venue
        val base = nameOn(venueId, show.date) ?: return show.venue
        val hall = show.hall
        return if (hall.isNullOrEmpty()) base else "$base $hall"
    }

    /**
     * 公演のキャパ。ホール指定があればホール側を優先する
     * (さいたまスーパーアリーナはスタジアム37,000 / アリーナ22,500 と倍近く違う)。
     */
    fun capacity(show: Show): Int? {
        val venueId = show.venueId ?: return null
        show.hall?.let { hall ->
            halls(venueId).firstOrNull { it.name == hall }?.capacity?.let { return it }
        }
        return byId[venueId]?.capacity
    }
}
