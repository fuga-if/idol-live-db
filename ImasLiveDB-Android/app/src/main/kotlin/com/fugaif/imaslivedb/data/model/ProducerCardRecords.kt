package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import uniffi.imas_core.CardLink
import uniffi.imas_core.CardDesign
import uniffi.imas_core.ProducerCard
import uniffi.imas_core.ProfileSheet
import uniffi.imas_core.cardLinksFromJson
import uniffi.imas_core.cardOshiChoiceFromJson
import uniffi.imas_core.cardOshiChoiceToJson
import uniffi.imas_core.cardLinksToJson
import uniffi.imas_core.cardDesignFromKey
import uniffi.imas_core.cardDesignKey
import uniffi.imas_core.cardDesigns
import uniffi.imas_core.decodeProducerCard
import uniffi.imas_core.profileSheetDefault
import uniffi.imas_core.profileSheetFromJson
import uniffi.imas_core.profileSheetToJson

/**
 * 自分の P名刺のうち、自分で書いた中身 (名前・ひとこと・P歴・リンク・外した項目・名刺のデザイン・自分の QR・
 * P名刺の画像の選択と好きな曲)。
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
    /**
     * 名刺から外した項目 ([ProducerCardField.key] をカンマで)。既定で外す項目 ([ProducerCardField.OPT_IN]) だけは逆で、
     * 書いてあれば**載せる** (足す前の行も既定どおり外れるように)。
     */
    @ColumnInfo(name = "hidden_fields", defaultValue = "")
    val hiddenFields: String,
    @ColumnInfo(name = "updated_at")
    val updatedAt: String,
    /**
     * 名刺のデザインの保存のキー (`cardDesignKey`)。空は既定のデザイン。書体を選んでいた頃の
     * 書体のキーが残っていることもある (`cardDesignFromKey` が近いデザインに読み替える)。
     */
    @ColumnInfo(name = "design", defaultValue = "")
    val design: String = "",
    /** 自分の QR の URL (正規化済み、`normalizeCardQrUrl`)。 */
    @ColumnInfo(name = "qr_url")
    val qrUrl: String? = null,
    /**
     * P名刺の画像 (SNS に貼る履歴書の様式) の選択と、P名刺の好きな曲 (コアの保存の形 `profileSheetToJson`)。
     * 空はまだ選んでいない。名刺の中身 (QR) には入らない。
     */
    @ColumnInfo(name = "profile_json", defaultValue = "")
    val profileJson: String = "",
    /**
     * 名刺に載せる担当の選択 (コアの保存の形 `cardOshiChoiceToJson`)。null はまだ選んでいない
     * (足す前の行もこれ。コアの自動の選び方で載る)。
     */
    @ColumnInfo(name = "card_oshi_json")
    val cardOshiJson: String? = null
) {
    val links: List<CardLink> get() = cardLinksFromJson(linksJson)

    /** 名刺のデザイン (保存のキーが空・知らないものなら既定)。 */
    val cardDesign: CardDesign get() = cardDesignFromKey(design) ?: cardDesigns().first().design

    fun withCardDesign(cardDesign: CardDesign): MyProducerCard = copy(design = cardDesignKey(cardDesign))

    val hidden: Set<ProducerCardField>
        get() {
            val stored = hiddenFields.split(",").mapNotNull { ProducerCardField.fromKey(it) }.toSet()
            return (stored - ProducerCardField.OPT_IN) + (ProducerCardField.OPT_IN - stored)
        }

    fun shows(field: ProducerCardField): Boolean = field !in hidden

    /**
     * 名刺に載せる担当の選択 (アプリの担当の id、載せる順)。null はまだ選んでいない。
     * 選び方 (既定・上限・担当から外れた人を抜く) はコアの `producerCardOshiPickedIds`。
     */
    val cardOshiChoice: List<String>? get() = cardOshiJson?.let { cardOshiChoiceFromJson(it) }

    fun withCardOshiChoice(choice: List<String>?): MyProducerCard =
        copy(cardOshiJson = choice?.takeIf { it.isNotEmpty() }?.let { cardOshiChoiceToJson(it) })

    /** P名刺の画像の選択と好きな曲 (まだ選んでいなければ既定の中身。壊れた保存も既定に戻す、規則はコア)。 */
    val profile: ProfileSheet
        get() = if (profileJson.isEmpty()) profileSheetDefault() else profileSheetFromJson(profileJson)

    fun withProfile(sheet: ProfileSheet): MyProducerCard = copy(profileJson = profileSheetToJson(sheet))

    fun withLinks(links: List<CardLink>): MyProducerCard = copy(linksJson = cardLinksToJson(links))

    fun withHidden(hidden: Set<ProducerCardField>): MyProducerCard {
        val stored = (hidden - ProducerCardField.OPT_IN) + (ProducerCardField.OPT_IN - hidden)
        return copy(hiddenFields = ProducerCardField.entries.filter { it in stored }.joinToString(",") { it.key })
    }

    /**
     * P名刺の編集で直した行を、保存する時点の行 ([latest]) に重ねる。P名刺の画像の選択 (大きさ・載せる項目) は
     * 画像の画面でその場で保存するので今の行のまま (開いた時の古い選択で戻さない)、好きな曲だけは編集のものにする。
     */
    fun applyingEdit(latest: MyProducerCard?): MyProducerCard {
        if (latest == null) return this
        return withProfile(latest.profile.copy(songs = profile.songs))
    }

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
    ATTENDED("attended", "参加した公演の一覧"),

    /** 表の判子の下のブランドの略称 (既定で外す。コアの `ProducerCard.showBrandLabels`)。 */
    BRAND_LABELS("brand_labels", "ブランド名");

    companion object {
        /** 既定で外す項目。保存の文字列には「載せる」と決めたときだけ書く。 */
        val OPT_IN: Set<ProducerCardField> = setOf(BRAND_LABELS)

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
    val venue: String?,
    /** ライブのブランド (P名刺の画像の担当ブランドに使う)。 */
    val brandId: String? = null
)
