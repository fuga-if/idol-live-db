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
    val unitId: String?
) {
    val isRemix: Boolean get() = parentSongId != null
}
