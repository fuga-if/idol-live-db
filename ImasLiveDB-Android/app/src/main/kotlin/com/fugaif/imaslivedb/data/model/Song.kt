package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "songs",
    indices = [
        Index(name = "idx_songs_brand", value = ["brand_id"]),
        Index(name = "idx_songs_composer", value = ["composer"])
    ]
)
data class Song(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "title")
    val title: String,

    @ColumnInfo(name = "title_kana")
    val titleKana: String?,

    @ColumnInfo(name = "brand_id")
    val brandId: String?,

    @ColumnInfo(name = "song_type")
    val songType: String,

    @ColumnInfo(name = "release_date")
    val releaseDate: String?,

    @ColumnInfo(name = "duration_sec")
    val durationSec: Int?,

    @ColumnInfo(name = "composer")
    val composer: String?,

    @ColumnInfo(name = "lyricist")
    val lyricist: String?,

    @ColumnInfo(name = "arranger")
    val arranger: String?,

    @ColumnInfo(name = "cd_series")
    val cdSeries: String?,

    @ColumnInfo(name = "cd_title")
    val cdTitle: String?,

    @ColumnInfo(name = "artwork_url")
    val artworkUrl: String?,

    @ColumnInfo(name = "preview_url")
    val previewUrl: String?,

    @ColumnInfo(name = "apple_music_id")
    val appleMusicId: String?,

    @ColumnInfo(name = "apple_music_album_id")
    val appleMusicAlbumId: String?,

    @ColumnInfo(name = "isrc")
    val isrc: String?,

    @ColumnInfo(name = "lyrics_url")
    val lyricsUrl: String?,

    @ColumnInfo(name = "parent_song_id")
    val parentSongId: String?,

    @ColumnInfo(name = "singer_label")
    val singerLabel: String?,

    @ColumnInfo(name = "unit_name")
    val unitName: String?,

    @ColumnInfo(name = "unit_id")
    val unitId: String?,

    @ColumnInfo(name = "series_group")
    val seriesGroup: String? = null,

    /**
     * この曲がどのユニットの版のものか ([UnitVersion.id])。null = 無印。
     *
     * ユニットは 1 行のままで、版の違いは曲側が指す。ユニット単位のフラグにすると
     * リブート前後の曲を区別できない。判定は [UnitVersion.code] で行うこと。
     */
    @ColumnInfo(name = "unit_version_id")
    val unitVersionId: String? = null,

    /**
     * 合同曲 (コラボ曲) で、brand_id 以外に参加しているブランド (カンマ区切り)。
     * events の joint_brand_ids と同じ形で、参加ブランド全部の曲一覧に出すために使う。
     * **在籍の重なりでは入れない** — ML の曲に 765AS の面々が居るのも、876 の曲に
     * 秋月涼が居るのも合同ではない。
     */
    @ColumnInfo(name = "joint_brand_ids")
    val jointBrandIds: String? = null,

    /**
     * シリーズ横断の合同曲か。判断は人が持つ (原唱者のブランドから導くと在籍の重なりを
     * 合同と取り違える)。立てるなら [jointBrandIds] も入れる。
     */
    @ColumnInfo(name = "is_collab")
    val isCollab: Boolean = false
) {
    val isRemix: Boolean get() = parentSongId != null

    /** 参加ブランド ([brandId] が先頭、続いて [jointBrandIds])。 */
    val brandIds: List<String>
        get() = (listOfNotNull(brandId) + (jointBrandIds?.split(",") ?: emptyList()))
            .filter { it.isNotEmpty() }
}
