package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import uniffi.imas_core.CardLink
import uniffi.imas_core.CardNameFont
import uniffi.imas_core.ProducerCard
import uniffi.imas_core.cardLinksFromJson
import uniffi.imas_core.cardLinksToJson
import uniffi.imas_core.cardNameFontFromKey
import uniffi.imas_core.cardNameFontKey
import uniffi.imas_core.cardNameFonts
import uniffi.imas_core.decodeProducerCard

/**
 * 自分の P名刺のうち、自分で書いた中身 (名前・ひとこと・P歴・リンク・外した項目・名前の書体・自分の QR)。
 * 名刺の写真は表に持たず端末のファイル (`ProducerCardFiles`)。
 * **端末ローカル唯一データ** (収支と同じ扱い、破壊的な移行はしない)。iOS `MyProducerCard` と同型。
 *
 * 担当・記録の数・次の現場・参加公演はアプリの記録から交換のたびに作り直すので持たない
 * (持つと記録とずれる)。名刺の組み立て・QR の中身・リンクの正規化はコア (`domain/producer_card.rs`)。
 */
@Entity(tableName = "my_producer_card")
data class MyProducerCard(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,
    @ColumnInfo(name = "name")
    val name: String,
    @ColumnInfo(name = "message", defaultValue = "")
    val message: String,
    /** P 歴の始まり (西暦)。 */
    @ColumnInfo(name = "since_year")
    val sinceYear: Int?,
    /** リンクの保存の形 (`cardLinksToJson`)。 */
    @ColumnInfo(name = "links_json", defaultValue = "[]")
    val linksJson: String,
    /** 名刺から外した項目 ([ProducerCardField.key] をカンマで)。 */
    @ColumnInfo(name = "hidden_fields", defaultValue = "")
    val hiddenFields: String,
    @ColumnInfo(name = "updated_at")
    val updatedAt: String,
    /** 名前の書体の保存のキー (`cardNameFontKey`)。空は既定の書体。 */
    @ColumnInfo(name = "name_font", defaultValue = "")
    val nameFont: String = "",
    /** 自分の QR の URL (正規化済み、`normalizeCardQrUrl`)。 */
    @ColumnInfo(name = "qr_url")
    val qrUrl: String? = null
) {
    val links: List<CardLink> get() = cardLinksFromJson(linksJson)

    /** 名前の書体 (保存のキーが空・知らないものなら既定)。 */
    val font: CardNameFont get() = cardNameFontFromKey(nameFont) ?: cardNameFonts().first().font

    fun withFont(font: CardNameFont): MyProducerCard = copy(nameFont = cardNameFontKey(font))

    val hidden: Set<ProducerCardField>
        get() = hiddenFields.split(",").mapNotNull { ProducerCardField.fromKey(it) }.toSet()

    fun shows(field: ProducerCardField): Boolean = field !in hidden

    fun withLinks(links: List<CardLink>): MyProducerCard = copy(linksJson = cardLinksToJson(links))

    fun withHidden(hidden: Set<ProducerCardField>): MyProducerCard =
        copy(hiddenFields = ProducerCardField.entries.filter { it in hidden }.joinToString(",") { it.key })

    companion object {
        /** 自分の名刺は 1 枚だけ。 */
        const val SINGLETON_ID = "me"

        fun empty(): MyProducerCard = MyProducerCard(
            id = SINGLETON_ID, name = "", message = "", sinceYear = null,
            linksJson = "[]", hiddenFields = "", updatedAt = ""
        )
    }
}

/** 名刺に載せる項目のうち、1 つずつ外せるもの。[key] は保存のキー (iOS と同じ値。変えない)。 */
enum class ProducerCardField(val key: String, val label: String) {
    OSHI("oshi", "担当"),
    MESSAGE("message", "ひとこと"),
    SINCE("since", "P歴"),
    LINKS("links", "リンク"),
    SHOW_COUNT("show_count", "参加公演数"),
    SONG_COUNT("song_count", "回収曲数"),
    NEXT("next", "次の現場"),
    ATTENDED("attended", "参加した公演の一覧");

    companion object {
        fun fromKey(key: String): ProducerCardField? = entries.firstOrNull { it.key == key }
    }
}

/**
 * 受け取った P名刺 1 枚。**端末ローカル唯一データ**。iOS `ReceivedProducerCard` と同型。
 *
 * 名刺の中身は `#` の後ろ ([payload]) のまま持ち、表示のたびにコアで読み解く
 * (読み解き方が変わっても保存した名刺は壊れない)。紙の名刺もコアの `producerCardPayload` で
 * 同じ形にして入れる。写真・受け取った担当の画像は端末のファイル (`ProducerCardFiles`)。
 */
@Entity(
    tableName = "received_producer_cards",
    // 同じ相手を 2 回読んだときの突き合わせが全表走査にならないように。
    indices = [Index(name = "idx_received_producer_cards_payload", value = ["payload"])]
)
data class ReceivedProducerCard(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,
    @ColumnInfo(name = "payload")
    val payload: String,
    /** [Source.key]。 */
    @ColumnInfo(name = "source", defaultValue = "app")
    val source: String,
    /** 受け取った公演。 */
    @ColumnInfo(name = "show_id")
    val showId: String?,
    /** 受け取った公演の日付 (`YYYY-MM-DD`)。束ねるときに使う。 */
    @ColumnInfo(name = "show_date")
    val showDate: String?,
    @ColumnInfo(name = "memo")
    val memo: String?,
    /** 受け取った日時 (ISO 8601)。 */
    @ColumnInfo(name = "received_at")
    val receivedAt: String,
    @ColumnInfo(name = "updated_at")
    val updatedAt: String
) {
    enum class Source(val key: String) {
        /** アプリの QR・名刺ファイル・近くの端末から。 */
        APP("app"),

        /** 紙の名刺を撮って取り込んだもの。 */
        PAPER("paper");

        companion object {
            fun fromKey(key: String): Source = entries.firstOrNull { it.key == key } ?: APP
        }
    }

    val sourceValue: Source get() = Source.fromKey(source)

    /** 名刺の中身。読み解けなければ null (画面は名前の無い名刺として出さずに飛ばす)。 */
    val card: ProducerCard? get() = decodeProducerCard(payload)

    companion object {
        fun make(
            payload: String,
            source: Source,
            showId: String?,
            showDate: String?,
            memo: String? = null,
            now: Instant = Instant.now()
        ): ReceivedProducerCard {
            // iOS (ISO8601DateFormatter) と同じ秒までの形にそろえる。
            val stamp = now.truncatedTo(ChronoUnit.SECONDS).toString()
            return ReceivedProducerCard(
                id = UUID.randomUUID().toString(), payload = payload, source = source.key,
                showId = showId, showDate = showDate, memo = memo?.takeIf { it.isNotEmpty() },
                receivedAt = stamp, updatedAt = stamp
            )
        }
    }
}

/** 名刺に出す公演 1 件 (受け取った公演・共通点・次の現場)。iOS `ProducerCardShowInfo` と同型。 */
data class ProducerCardShowInfo(
    val id: String,
    val eventId: String,
    val date: String,
    /** `showDisplayTitle` で組んだ表記。 */
    val label: String,
    val venue: String?
)
