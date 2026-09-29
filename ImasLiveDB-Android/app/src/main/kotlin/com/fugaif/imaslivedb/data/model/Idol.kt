package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import com.fugaif.imaslivedb.data.core.VoiceActorDirectory
import uniffi.imas_core.idolShortName

@Entity(tableName = "idols")
data class Idol(
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

    @ColumnInfo(name = "family_name")
    val familyName: String? = null,

    @ColumnInfo(name = "given_name")
    val givenName: String? = null,

    @ColumnInfo(name = "nickname")
    val nickname: String? = null,

    @ColumnInfo(name = "color")
    val color: String?,

    @ColumnInfo(name = "sort_order")
    val sortOrder: Int,

    @ColumnInfo(name = "birthday")
    val birthday: String?,

    @ColumnInfo(name = "blood_type")
    val bloodType: String?,

    @ColumnInfo(name = "height")
    val height: Double?,

    @ColumnInfo(name = "weight")
    val weight: Double?,

    @ColumnInfo(name = "birth_place")
    val birthPlace: String?,

    @ColumnInfo(name = "age")
    val age: Int?,

    @ColumnInfo(name = "bust")
    val bust: Double?,

    @ColumnInfo(name = "waist")
    val waist: Double?,

    @ColumnInfo(name = "hip")
    val hip: Double?,

    @ColumnInfo(name = "constellation")
    val constellation: String?,

    @ColumnInfo(name = "hobbies")
    val hobbies: String?,

    @ColumnInfo(name = "talents")
    val talents: String?,

    @ColumnInfo(name = "description")
    val description: String?,

    @ColumnInfo(name = "gender")
    val gender: String?,

    @ColumnInfo(name = "handedness")
    val handedness: String?,

    /** 実装(初登場)日 ISO8601 (YYYY-MM-DD)。 */
    @ColumnInfo(name = "debut_date")
    val debutDate: String? = null,

    /** ブランド内サブカテゴリ属性 (cute/cool/passion 等)。 */
    @ColumnInfo(name = "attribute")
    val attribute: String? = null,

    /** 外部ゲスト演者フラグ。true ならアイドル一覧・検索・統計から除外対象。 */
    @ColumnInfo(name = "is_external")
    val isExternal: Boolean = false,

    /** 別名 (ステージ名・通称・略称) のカンマ区切り。 */
    @ColumnInfo(name = "aliases")
    val aliases: String? = null,

    /** 担当声優のカンマ区切り。先頭が現役、以降は過去 CV (古い順)。 */
    @ColumnInfo(name = "voice_actors")
    val voiceActors: String? = null
) {
    /**
     * 表示用の短縮名 (アバターのモノグラム等)。優先順位: nickname > given_name > name。
     *
     * **規則の正は共有コア** (imas-core: domain/snapshot.rs の idol_short_name)。
     * iOS の `Idol.shortName` と同じ 1 本を呼ぶ。
     */
    val shortName: String
        get() = idolShortName(name, givenName, nickname)

    /**
     * 現任の声優名。居なければ・まだ読めなければ null。
     *
     * 声優は `idol_voice_actors` の期間つき履歴が正で、現任の選び方はコア
     * ([VoiceActorDirectory] 経由の `idolCastNames`。iOS と同じ)。[voiceActors] 列は
     * seed に無い派生列で reseed のたびに NULL になるので、表示にも検索にも使わない。
     */
    val currentVoiceActor: String?
        get() = VoiceActorDirectory.current(id)
}
