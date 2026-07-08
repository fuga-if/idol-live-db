package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.BrandSongHitRow
import com.fugaif.imaslivedb.data.model.BrandTotalRow
import com.fugaif.imaslivedb.data.model.SongPerfCount
import com.fugaif.imaslivedb.data.model.UpcomingShowRow
import com.fugaif.imaslivedb.data.model.YearlyShowCount

@Dao
interface StatsDao {

    @Query("SELECT COUNT(*) FROM songs")
    suspend fun fetchSongCount(): Int

    @Query("SELECT COUNT(*) FROM idols")
    suspend fun fetchIdolCount(): Int

    @Query("SELECT COUNT(*) FROM events")
    suspend fun fetchEventCount(): Int

    @Query("SELECT COUNT(*) FROM shows")
    suspend fun fetchShowCount(): Int

    @Query("""
        SELECT strftime('%Y', date) AS year, COUNT(*) AS show_count
        FROM shows
        GROUP BY year
        ORDER BY year
    """)
    suspend fun fetchYearlyShowCounts(): List<YearlyShowCount>

    // MARK: - Collection Dashboard (iOS AppDatabase の回収ダッシュボード関連クエリの移植)

    /** brand_id が設定されている曲 ID (回収率集計の分母母集合)。 */
    @Query("SELECT id FROM songs WHERE brand_id IS NOT NULL")
    suspend fun fetchBrandedSongIds(): List<String>

    /**
     * ユーザが参加した「リアルライブ」のセトリに含まれる全 song_id (回収済み)。
     * 回収はリアルライブ(live/festival)のみ・参加種別は現地のみ (iOS の配信含む設定は未移植、既定値で固定)。
     */
    @Query("""
        SELECT DISTINCT si.song_id
        FROM setlist_items si
        JOIN shows sh ON si.show_id = sh.id
        JOIN events e ON e.id = sh.event_id
        WHERE e.kind IN ('live','festival')
        AND (
            sh.id IN (
                SELECT entity_id FROM user_marks
                WHERE entity_type='show' AND kind='attended' AND bool_value=1
                  AND (text_value IS NULL OR text_value='live')
            )
            OR sh.event_id IN (
                SELECT entity_id FROM user_marks
                WHERE entity_type='event' AND kind='attended' AND bool_value=1
            )
        )
    """)
    suspend fun fetchAutoCollectedSongIds(): List<String>

    /** 指定 idol_id 群のうち、いずれかが原唱者 (role='original') として紐付いてる song_id 集合。 */
    @Query("SELECT DISTINCT song_id FROM song_artists WHERE role='original' AND idol_id IN (:idolIds)")
    suspend fun fetchSongIdsWithAnyArtist(idolIds: List<String>): List<String>

    /** ブランドごとの曲総数 (回収進捗の分母)。 */
    @Query("""
        SELECT b.id AS id, b.short_name AS short_name, b.color AS color, COUNT(s.id) AS total
        FROM brands b LEFT JOIN songs s ON b.id = s.brand_id
        GROUP BY b.id ORDER BY b.sort_order
    """)
    suspend fun fetchBrandTotals(): List<BrandTotalRow>

    /** 指定 song_id 群の brand_id (回収済み曲をブランド別に集計するため)。 */
    @Query("SELECT brand_id FROM songs WHERE id IN (:ids) AND brand_id IS NOT NULL")
    suspend fun fetchBrandIdsForSongs(ids: List<String>): List<String>

    /** 指定 song_id 群の生涯リアルライブ披露回数。 */
    @Query("""
        SELECT si.song_id AS song_id, COUNT(*) AS cnt
        FROM setlist_items si
        JOIN shows sh ON si.show_id = sh.id
        JOIN events e ON e.id = sh.event_id
        WHERE e.kind IN ('live','festival') AND si.song_id IN (:songIds)
        GROUP BY si.song_id
    """)
    suspend fun fetchLifetimePlayCounts(songIds: List<String>): List<SongPerfCount>

    /** 未回収曲ごとに、過去リアルライブで披露された brand_id との対応 (この公演で聴けるかも判定用)。 */
    @Query("""
        SELECT DISTINCT e.brand_id AS brand_id, si.song_id AS song_id
        FROM setlist_items si
        JOIN shows sh ON si.show_id = sh.id
        JOIN events e ON e.id = sh.event_id
        WHERE e.kind IN ('live','festival') AND e.brand_id IS NOT NULL AND si.song_id IN (:songIds)
    """)
    suspend fun fetchBrandSongHits(songIds: List<String>): List<BrandSongHitRow>

    /** 今日以降のリアルライブ公演 (親イベント名・ブランド色つき)。 */
    @Query("""
        SELECT s.id, s.event_id, s.name, s.date, s.venue, s.venue_city,
               s.start_time, s.sort_order, s.performer_type,
               e.name AS event_name, e.brand_id AS brand_id, b.color AS brand_color
        FROM shows s
        JOIN events e ON s.event_id = e.id
        LEFT JOIN brands b ON e.brand_id = b.id
        WHERE s.date >= :today AND e.kind IN ('live','festival')
        ORDER BY s.date ASC, s.sort_order ASC
    """)
    suspend fun fetchUpcomingRealLiveShows(today: String): List<UpcomingShowRow>

    /** 最新公演のセトリ曲数。 */
    @Query("SELECT COUNT(*) FROM setlist_items WHERE show_id = :showId")
    suspend fun fetchSetlistCount(showId: String): Int
}
