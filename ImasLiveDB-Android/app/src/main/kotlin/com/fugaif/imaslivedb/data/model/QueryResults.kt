package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Embedded

// MARK: - Event Query Results

// Raw Room query result for events joined with first/last show date (一覧・お気に入り・参加ライブ共通)
data class EventWithDateRangeRow(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "brand_id") val brandId: String?,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "event_type") val eventType: String,
    @ColumnInfo(name = "is_streaming") val isStreaming: Boolean,
    @ColumnInfo(name = "first_date") val firstDate: String?,
    @ColumnInfo(name = "last_date") val lastDate: String?,
    @ColumnInfo(name = "joint_brand_ids") val jointBrandIds: String?
) {
    fun toEventWithDateRange() = EventWithDateRange(
        event = Event(
            id = id, brandId = brandId, name = name, eventType = eventType,
            isStreaming = isStreaming, jointBrandIds = jointBrandIds
        ),
        firstDate = firstDate,
        lastDate = lastDate
    )
}

data class EventWithDateRange(
    val event: Event,
    val firstDate: String?,
    val lastDate: String?
) {
    /** 表示用の開催日。複数日なら "first〜last"、単日なら first のみ。 */
    val dateRange: String?
        get() {
            val first = firstDate?.takeIf { it.isNotEmpty() } ?: return null
            val last = lastDate?.takeIf { it.isNotEmpty() && it != first }
            return if (last != null) "$first〜$last" else first
        }

    // 「今後 / 開催済み」の判定は共有コアの groupEventIndicesByYear が持つ (firstDate 基準)。
    // ここに lastDate 基準の isUpcoming があると二重実装になるので置かない。
}

/** 参加マークの行 (event_id + 参加種別 text_value)。live/stream/live_viewing 分類用。 */
data class AttendedEventTypeRow(
    @ColumnInfo(name = "event_id") val eventId: String,
    @ColumnInfo(name = "atype") val atype: String?
)

data class EventStats(
    @ColumnInfo(name = "show_count") val showCount: Int,
    @ColumnInfo(name = "total_songs") val totalSongs: Int,
    @ColumnInfo(name = "unique_songs") val uniqueSongs: Int,
    @ColumnInfo(name = "cast_count") val castCount: Int
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

/** 公演 + 所属イベント名 (オープン編集のセトリピッカー用)。 */
data class ShowWithEventName(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "event_id") val eventId: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "date") val date: String,
    @ColumnInfo(name = "venue") val venue: String?,
    @ColumnInfo(name = "venue_city") val venueCity: String?,
    @ColumnInfo(name = "start_time") val startTime: String?,
    @ColumnInfo(name = "sort_order") val sortOrder: Int,
    @ColumnInfo(name = "performer_type") val performerType: String?,
    @ColumnInfo(name = "event_name") val eventName: String
) {
    fun toShow() = Show(
        id = id, eventId = eventId, name = name, date = date, venue = venue,
        venueCity = venueCity, startTime = startTime, sortOrder = sortOrder, performerType = performerType
    )
}

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

/** ソロ曲 (song_type='solo') とその原唱アイドルの対応行。ソロ曲クイズの出題母集団構築に使う。 */
data class SoloOriginalSingerRow(
    @ColumnInfo(name = "song_id") val songId: String,
    @ColumnInfo(name = "idol_id") val idolId: String
)

// MARK: - Cast Query Results

data class CastShowRow(
    @ColumnInfo(name = "show_id") val showId: String,
    @ColumnInfo(name = "event_id") val eventId: String,
    @ColumnInfo(name = "event_name") val eventName: String,
    @ColumnInfo(name = "show_name") val showName: String,
    @ColumnInfo(name = "date") val date: String,
    @ColumnInfo(name = "venue") val venue: String?,
    @ColumnInfo(name = "cast_role") val castRole: String = "member"
) {
    val isLead: Boolean get() = castRole == "lead"
    val isGuest: Boolean get() = castRole == "guest"
}

/** アイドルのライブ歌唱曲 (曲 + 披露回数)。iOS IdolPerformedSong の移植。 */
data class IdolPerformedSong(
    @Embedded val song: Song,
    @ColumnInfo(name = "perform_count") val performCount: Int
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

// MARK: - Collection Dashboard Query Types (iOS Database/QueryTypes.swift の移植)

/** ブランドごとの曲総数の生行 (回収進捗の分母)。 */
data class BrandTotalRow(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "short_name") val shortName: String,
    @ColumnInfo(name = "color") val color: String?,
    @ColumnInfo(name = "total") val total: Int
)

/** 未回収候補ごとに過去披露した brand_id との対応 (この公演で聴けるかも判定用)。 */
data class BrandSongHitRow(
    @ColumnInfo(name = "brand_id") val brandId: String?,
    @ColumnInfo(name = "song_id") val songId: String
)

/** 今日以降のリアルライブ公演 (親イベント名・ブランド色つき)。 */
data class UpcomingShowRow(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "event_id") val eventId: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "date") val date: String,
    @ColumnInfo(name = "venue") val venue: String?,
    @ColumnInfo(name = "venue_city") val venueCity: String?,
    @ColumnInfo(name = "start_time") val startTime: String?,
    @ColumnInfo(name = "sort_order") val sortOrder: Int,
    @ColumnInfo(name = "performer_type") val performerType: String?,
    @ColumnInfo(name = "event_name") val eventName: String,
    @ColumnInfo(name = "brand_id") val brandId: String?,
    @ColumnInfo(name = "brand_color") val brandColor: String?
) {
    fun toShow() = Show(
        id = id, eventId = eventId, name = name, date = date, venue = venue,
        venueCity = venueCity, startTime = startTime, sortOrder = sortOrder, performerType = performerType
    )
}

/** ブランド別の現地回収進捗 (回収済み曲数 / そのブランドの全曲数)。 */
data class BrandCollectionProgress(
    val brandId: String,
    val shortName: String,
    val color: String?,
    val collected: Int,
    val total: Int
) {
    /** 0.0–1.0。total=0 のときは 0。 */
    val fraction: Double get() = if (total > 0) collected.toDouble() / total else 0.0
}

/** 未回収曲 + その曲の生涯披露回数 (= よく演る/レアの目安)。 */
data class UncollectedSong(val song: Song, val playCount: Int) {
    /** 披露頻度のラベル。閾値はざっくり: 10+ 定番 / 3+ ときどき / 1+ レア / 0 未披露。 */
    val frequencyLabel: String get() = when {
        playCount >= 10 -> "定番"
        playCount >= 3 -> "ときどき"
        playCount >= 1 -> "レア"
        else -> "未披露"
    }
}

/** 未来公演ごとの「未回収が聴けるかも」スコア。 */
data class UpcomingCatchChance(
    val show: Show,
    val eventName: String,
    val brandId: String?,
    val brandColor: String?,
    /** 過去の同系統セトリに登場した「自分の未回収曲」の異なり数。 */
    val likelyCount: Int
)

/** 回収ダッシュボードの重い集計をまとめたリポジトリ戻り値。 */
data class CollectionDashboard(
    val overallCollected: Int,
    val overallTotal: Int,
    val brandProgress: List<BrandCollectionProgress>,
    val pickUncollected: List<UncollectedSong>,
    val allUncollected: List<UncollectedSong>,
    val myPickCollected: Int,
    val myPickTotal: Int,
    val catchChances: List<UpcomingCatchChance>
)

/** お気に入りランキング行。API のコミュニティ集計 (song_id, count) にローカルカタログの曲メタを結合。 */
data class FavoriteRankingEntry(
    val songId: String,
    val count: Int,
    val title: String,
    val brandId: String?,
    val artworkUrl: String?
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
    val excludeLiveOnly: Boolean = true,
    // brand_id='other' (歌枠カバー等の非ブランド曲) を含めるか。ブランド未選択(全件)時のみ効く。
    // 既定 true (他画面からの検索/絞り込みでは既存挙動を維持)。曲一覧ブラウズだけ false にして既定で隠す。
    val includeOtherBrand: Boolean = true
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
    PERFORMANCE_COUNT,
    COLLECTED_COUNT,
    COLLECTED_RATE;

    /** この sort のデフォルト方向。五十音順は昇順、回数/日付/率系は降順(多い/新しい順)。 */
    val defaultAscending: Boolean get() = this == TITLE_KANA
}

/** 楽曲一覧の「現地回収」軸での絞り込み。 */
enum class SongCollectFilter {
    ALL, COLLECTED, UNCOLLECTED
}

/**
 * 楽曲一覧の「マイマーク」軸での絞り込み。担当/お気に入りどれか/両方に該当する曲のみ表示する。
 * iOS の SongMyMarkFilter 相当 (メモは Android にメモ編集 UI が無いため対象外)。
 */
data class SongMyMarkFilter(
    val requireMyPick: Boolean = false,
    val requireFavorite: Boolean = false
) {
    val isActive: Boolean get() = requireMyPick || requireFavorite
    val activeCount: Int
        get() {
            var c = 0
            if (requireMyPick) c++
            if (requireFavorite) c++
            return c
        }
}
