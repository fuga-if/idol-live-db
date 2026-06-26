package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo

// MARK: - Event Query Results

// Raw Room query result for events joined with first show date
data class EventWithDateRow(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "brand_id") val brandId: String?,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "event_type") val eventType: String,
    @ColumnInfo(name = "is_streaming") val isStreaming: Boolean,
    @ColumnInfo(name = "first_date") val firstDate: String?
) {
    fun toEventWithDate() = EventWithDate(
        event = Event(id, brandId, name, eventType, isStreaming),
        firstDate = firstDate
    )
}

data class EventWithDate(
    val event: Event,
    val firstDate: String?
)

data class EventStats(
    @ColumnInfo(name = "show_count") val showCount: Int,
    @ColumnInfo(name = "total_songs") val totalSongs: Int,
    @ColumnInfo(name = "unique_songs") val uniqueSongs: Int,
    @ColumnInfo(name = "cast_count") val castCount: Int
)

data class EventCastRow(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "idol_color") val idolColor: String?,
    @ColumnInfo(name = "idol_name") val idolName: String?,
    @ColumnInfo(name = "idol_id") val idolId: String?
)

// MARK: - Setlist Query Results

data class SetlistRow(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "position") val position: Int,
    @ColumnInfo(name = "section") val section: String?,
    @ColumnInfo(name = "notes") val notes: String?,
    @ColumnInfo(name = "unit_name") val unitName: String?,
    @ColumnInfo(name = "song_id") val songId: String,
    @ColumnInfo(name = "song_title") val songTitle: String,
    @ColumnInfo(name = "apple_music_id") val appleMusicId: String?,
    @ColumnInfo(name = "artwork_url") val artworkUrl: String?,
    @ColumnInfo(name = "preview_url") val previewUrl: String?,
    @ColumnInfo(name = "song_brand_id") val songBrandId: String?
)

data class PerformerRow(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "idol_color") val idolColor: String?,
    @ColumnInfo(name = "idol_name") val idolName: String?,
    @ColumnInfo(name = "idol_id") val idolId: String?
)

data class AllPerformerRow(
    @ColumnInfo(name = "setlist_item_id") val setlistItemId: String,
    @ColumnInfo(name = "cast_id") val castId: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "idol_color") val idolColor: String?,
    @ColumnInfo(name = "idol_name") val idolName: String?,
    @ColumnInfo(name = "idol_id") val idolId: String?
)

// MARK: - Song Query Results

data class PerformanceHistoryRow(
    @ColumnInfo(name = "show_id") val showId: String,
    @ColumnInfo(name = "event_id") val eventId: String,
    @ColumnInfo(name = "event_name") val eventName: String,
    @ColumnInfo(name = "show_name") val showName: String,
    @ColumnInfo(name = "date") val date: String,
    @ColumnInfo(name = "venue") val venue: String?,
    @ColumnInfo(name = "position") val position: Int,
    @ColumnInfo(name = "section") val section: String?
)

data class SongPlayCount(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "title") val title: String,
    @ColumnInfo(name = "play_count") val playCount: Int,
    @ColumnInfo(name = "brand_id") val brandId: String?
)

data class SongPerfCount(
    @ColumnInfo(name = "song_id") val songId: String,
    @ColumnInfo(name = "cnt") val cnt: Int
)

// MARK: - Cast Query Results

data class CastShowRow(
    @ColumnInfo(name = "show_id") val showId: String,
    @ColumnInfo(name = "event_id") val eventId: String,
    @ColumnInfo(name = "event_name") val eventName: String,
    @ColumnInfo(name = "show_name") val showName: String,
    @ColumnInfo(name = "date") val date: String,
    @ColumnInfo(name = "venue") val venue: String?
)

data class CastShowCount(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "show_count") val showCount: Int
)

data class IdolCastNameRow(
    @ColumnInfo(name = "idol_id") val idolId: String,
    @ColumnInfo(name = "name") val name: String
)

// MARK: - Stats Query Results

data class BrandSongCount(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "short_name") val shortName: String,
    @ColumnInfo(name = "color") val color: String?,
    @ColumnInfo(name = "song_count") val songCount: Int
)

data class DatabaseStats(
    val songCount: Int,
    val idolCount: Int,
    val eventCount: Int,
    val showCount: Int
)

data class YearlyShowCount(
    @ColumnInfo(name = "year") val year: String,
    @ColumnInfo(name = "show_count") val showCount: Int
)

// MARK: - Search Results

data class SearchResults(
    val songs: List<Song>,
    val idols: List<Idol>,
    val events: List<Event>
) {
    val isEmpty: Boolean get() = songs.isEmpty() && idols.isEmpty() && events.isEmpty()
}

// MARK: - Song List Row

data class SongWithArtists(
    val song: Song,
    val artistNames: String
)

// MARK: - Song Filter / Sort

data class SongSearchFilter(
    val brandId: String? = null,
    val title: String? = null,
    val idolName: String? = null,
    val idolIds: List<String>? = null,
    val songwriter: String? = null,
    val cdSeries: String? = null,
    val liveName: String? = null,
    val songType: String? = null,
    val includeRemixes: Boolean = false,
    // ライブ履歴(セトリ)にしかない、カタログメタ皆無の曲(カバー/歌枠等)を一覧から隠す。既定ON。
    val excludeLiveOnly: Boolean = true
) {
    val isEmpty: Boolean
        get() = brandId == null &&
                (title ?: "").isEmpty() &&
                (idolName ?: "").isEmpty() &&
                (idolIds ?: emptyList()).isEmpty() &&
                (songwriter ?: "").isEmpty() &&
                (cdSeries ?: "").isEmpty() &&
                (liveName ?: "").isEmpty() &&
                songType == null

    val activeFilterCount: Int
        get() {
            var count = 0
            if (brandId != null) count++
            if (!(idolName ?: "").isEmpty() || !(idolIds ?: emptyList()).isEmpty()) count++
            if (!(songwriter ?: "").isEmpty()) count++
            if (!(cdSeries ?: "").isEmpty()) count++
            if (!(liveName ?: "").isEmpty()) count++
            if (songType != null) count++
            return count
        }
}

enum class SongSortOrder {
    TITLE_KANA,
    RELEASE_DATE,
    PERFORMANCE_COUNT
}
