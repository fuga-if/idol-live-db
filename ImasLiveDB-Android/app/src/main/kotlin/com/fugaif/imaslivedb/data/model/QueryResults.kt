package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Embedded
import uniffi.imas_core.dateRangeDisplay

// MARK: - Event Query Results

// Raw Room query result for events joined with first/last show date (一覧・お気に入り・参加ライブ共通)
data class EventWithDateRange(
    val event: Event,
    val firstDate: String?,
    val lastDate: String?,
    /** 合同ライブか (参加ブランドの割り方はコア。虹色のリードバーに使う)。 */
    val isJoint: Boolean = false
) {
    /**
     * 表示用の開催期間 (曜日付き、複数日なら ` 〜 ` で繋ぐ)。組み立てはコア (dateRangeDisplay)。
     * 行が描かれたときに 1 回だけ引いて覚える (一覧の読み込みで全件ぶん FFI を跨がない)。
     */
    val dateRange: String? by lazy { dateRangeDisplay(firstDate, lastDate) }

    // 「今後 / 開催済み」の判定は共有コアの groupEventIndicesByYear が持つ (firstDate 基準)。
    // ここに lastDate 基準の isUpcoming があると二重実装になるので置かない。
}

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

/** 公演 + コアが決めた属性 (キャラライブか)。 */
data class ShowInfo(
    val show: Show,
    /** キャラクターが出演する公演 (名義の出し方が変わる)。判定はコア。 */
    val isCharacterLive: Boolean
)

/** イベント + コアが決めた属性 (合同か)。 */
data class EventInfo(
    val event: Event,
    /** 合同ライブか。割り方はコア (`split_brand_ids`)。 */
    val isJoint: Boolean
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
    @ColumnInfo(name = "brand_id") val brandId: String?,
    /** 一覧のジャケは songs.artwork_url の直参照が正本 (URL を組み立てない)。
     *  **ここに無いと画面は出しようがない** — この型にだけ無かったせいで
     *  回収率ダッシュボードの披露回数ランキングだけジャケが出ていなかった。 */
    @ColumnInfo(name = "artwork_url") val artworkUrl: String? = null
)

/**
 * 共起曲 1 件の集計行 (披露実績)。**単位は公演**で、1 公演で 2 回演奏されても 1。
 * 分母 (その曲自身の総披露公演数) は別クエリ ([SongPerfCount]) で引く。
 */
data class CoOccurrenceRow(
    @ColumnInfo(name = "song_id") val songId: String,
    @ColumnInfo(name = "together") val together: Int
)

/**
 * 歌唱者 1 件の集計行 (披露実績)。**単位はセトリ行数**で、曲詳細の「総披露 N 回」と同じ
 * 数え方 (共起行の公演数とは別物なので、画面に出すときは語を分ける)。
 */
data class SingerTallyRow(
    @ColumnInfo(name = "idol_id") val idolId: String,
    @ColumnInfo(name = "times") val times: Int,
    @ColumnInfo(name = "total") val total: Int
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

/**
 * アイドル詳細「楽曲（原曲）」の 1 節 (ソロ曲/ユニット曲/全体曲/カバー/その他)。
 * 節分け・見出し・並びは共有コア (idol_original_song_sections) が決める
 * (親曲を持つ派生曲の除外、カバーの独立節化も含む)。iOS IdolSongSection の移植。
 * Room の直接クエリ結果ではなく FFI の射影を Song に実体化して組み立てるので、
 * [IdolPerformedSong] と違って Room アノテーションは付けない。
 */
data class IdolSongSection(
    val heading: String,
    /** 小タブに出す短い見出し (「ソロ」等)。件数と組み合わせて「ソロ 12」のように使う。 */
    val shortHeading: String,
    val songs: List<Song>
)

data class CastShowCount(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "name") val name: String,
    @ColumnInfo(name = "show_count") val showCount: Int
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

/** お気に入りランキング行。API のコミュニティ集計 (song_id, count) にローカルカタログの曲メタを結合。 */
data class FavoriteRankingEntry(
    val songId: String,
    val count: Int,
    val title: String,
    val brandId: String?,
    val artworkUrl: String?
)

/**
 * あいまい検索へ渡す綴り (曲名 + 読み) の軽い射影。
 *
 * 候補を絞るのに要るのは綴りだけなので、Song 実体を全件読まない。
 * 当たった曲だけを後から実体化する。
 */
data class SongSpelling(
    val id: String,
    val title: String,
    @ColumnInfo(name = "title_kana") val titleKana: String?
) {
    /** コアへ渡す綴り列。読みが無い曲は曲名だけ。 */
    val spellings: List<String>
        get() = listOfNotNull(title.takeIf { it.isNotBlank() }, titleKana?.takeIf { it.isNotBlank() })
}

// MARK: - Song List Row

data class SongWithArtists(
    val song: Song,
    val artistNames: String
)

// MARK: - Song Filter / Sort

data class SongSearchFilter(
    // 空 = 全ブランド。複数選択は OR (コア/SQL とも IN 句) で、iOS SongSearchFilter.brandIds と同義。
    // 単一選択だった頃の呼び出し口は setOfNotNull(brandId) で移せる。
    val brandIds: Set<String> = emptySet(),
    val title: String? = null,
    val idolName: String? = null,
    val idolIds: List<String>? = null,
    val songwriter: String? = null,
    val cdSeries: String? = null,
    // 上位シリーズ (series_group: LTF / BRILLI@NT WING 等) の完全一致。cd_series の部分一致とは別軸。
    val seriesGroup: String? = null,
    val liveName: String? = null,
    val songType: String? = null,
    val includeRemixes: Boolean = false,
    // ライブ履歴(セトリ)にしかない、カタログメタ皆無の曲(カバー/歌枠等)を一覧から隠す。既定ON。
    val excludeLiveOnly: Boolean = true,
    // brand_id='other' (歌枠カバー等の非ブランド曲) を含めるか。ブランド未選択(全件)時のみ効く。
    // 既定 true (他画面からの検索/絞り込みでは既存挙動を維持)。曲一覧ブラウズだけ false にして既定で隠す。
    val includeOtherBrand: Boolean = true,
    // KAMISABI (音楽カードゲーム) 収録曲だけに絞る。既定 OFF。
    val kamisabiOnly: Boolean = false
) {
    val isEmpty: Boolean
        get() = brandIds.isEmpty() &&
                (title ?: "").isEmpty() &&
                (idolName ?: "").isEmpty() &&
                (idolIds ?: emptyList()).isEmpty() &&
                (songwriter ?: "").isEmpty() &&
                (cdSeries ?: "").isEmpty() &&
                (seriesGroup ?: "").isEmpty() &&
                (liveName ?: "").isEmpty() &&
                songType == null

    val activeFilterCount: Int
        get() {
            var count = 0
            // ブランドは何個選ばれていても「ブランドで絞っている」1 条件として数える
            // (バッジの数字は条件の本数であって選択肢の数ではない)。
            if (brandIds.isNotEmpty()) count++
            if (!(idolName ?: "").isEmpty() || !(idolIds ?: emptyList()).isEmpty()) count++
            if (!(songwriter ?: "").isEmpty()) count++
            if (!(cdSeries ?: "").isEmpty()) count++
            if (!(seriesGroup ?: "").isEmpty()) count++
            if (!(liveName ?: "").isEmpty()) count++
            if (songType != null) count++
            if (kamisabiOnly) count++
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
 * 楽曲一覧の「マイマーク」軸での絞り込み。ONにした条件すべてに該当する曲 (AND) のみ表示する。
 * iOS の SongMyMarkFilter 相当。
 *
 * メモ絞り込みは Android にメモ**編集**の導線が無いままだが、user_marks の memo 行自体は
 * iOS からの引き継ぎ (バックアップ復元) で入ってくるので、読む側だけ先に配線してある。
 */
data class SongMyMarkFilter(
    val requireMyPick: Boolean = false,
    val requireFavorite: Boolean = false,
    val requireNote: Boolean = false
) {
    val isActive: Boolean get() = requireMyPick || requireFavorite || requireNote
    val activeCount: Int
        get() {
            var c = 0
            if (requireMyPick) c++
            if (requireFavorite) c++
            if (requireNote) c++
            return c
        }
}

// MARK: - Album / Series Summary

/**
 * CD シリーズ (cd_series) 単位の集計 1 件。曲一覧の「アルバム」表示のカード 1 枚ぶん。
 * iOS `AlbumSummary` と同じ形 (集計本体はコアの albumSummaries)。
 */
data class AlbumSummary(
    val cdSeries: String,
    val artworkUrl: String?,
    val songCount: Int,
    val earliestDate: String?,
    val latestDate: String?,
    /** 含まれる曲のブランド id (重複なし)。1 枚に複数ブランドが混ざることがある。 */
    val brandIds: List<String>,
    /** カードの副題に出す発売年 (`2019` / `2019 – 2021`)。幅の出し方はコア。 */
    val yearDisplay: String? = null
)

/**
 * 上位シリーズ (series_group) 単位の集計 1 件。曲一覧の「シリーズ」表示のカード 1 枚ぶん。
 * iOS `SeriesSummary` と同じ形 (集計本体はコアの seriesSummaries)。
 */
data class SeriesSummary(
    val name: String,
    val songCount: Int,
    /** グループ内の cd_series 異なり数 (= 枚数)。 */
    val cdCount: Int,
    val earliestDate: String?,
    val latestDate: String?,
    val artworkUrl: String?,
    val brandIds: List<String>,
    /** カードの副題に出す年の幅 (`2019` / `2019 – 2021`)。幅の出し方はコア。 */
    val yearDisplay: String? = null
)
