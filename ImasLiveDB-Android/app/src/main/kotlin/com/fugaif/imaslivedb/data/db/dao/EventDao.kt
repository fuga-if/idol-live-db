package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.AttendedEventTypeRow
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.EventStats
import com.fugaif.imaslivedb.data.model.EventWithDateRangeRow
import com.fugaif.imaslivedb.data.model.ShowCast

@Dao
interface EventDao {

    @Query("SELECT * FROM events")
    suspend fun fetchEvents(): List<Event>

    @Query("SELECT * FROM events WHERE brand_id = :brandId")
    suspend fun fetchEventsByBrand(brandId: String): List<Event>

    @Query("SELECT * FROM events WHERE id = :id LIMIT 1")
    suspend fun fetchEvent(id: String): Event?

    @Query("""
        SELECT e.id, e.brand_id, e.name, e.event_type, e.is_streaming, e.joint_brand_ids,
               MIN(s.date) AS first_date, MAX(s.date) AS last_date
        FROM events e
        LEFT JOIN shows s ON s.event_id = e.id
        GROUP BY e.id
        ORDER BY COALESCE(MIN(s.date), '') DESC
    """)
    suspend fun fetchEventsWithFirstDate(): List<EventWithDateRangeRow>

    @Query("""
        WITH event_shows AS (SELECT id FROM shows WHERE event_id = :eventId)
        SELECT
            (SELECT COUNT(*) FROM event_shows) AS show_count,
            (SELECT COUNT(*) FROM setlist_items WHERE show_id IN (SELECT id FROM event_shows)) AS total_songs,
            (SELECT COUNT(DISTINCT song_id) FROM setlist_items WHERE show_id IN (SELECT id FROM event_shows)) AS unique_songs,
            (SELECT COUNT(DISTINCT idol_id) FROM show_cast WHERE show_id IN (SELECT id FROM event_shows)) AS cast_count
    """)
    suspend fun fetchEventStats(eventId: String): EventStats

    /** イベント配下の全 show_cast 行 (show 単位の出演/主演/ゲスト判定用)。 */
    @Query("""
        SELECT sc.* FROM show_cast sc
        JOIN shows sh ON sc.show_id = sh.id
        WHERE sh.event_id = :eventId
    """)
    suspend fun fetchEventShowCast(eventId: String): List<ShowCast>

    @Query("""
        SELECT * FROM events
        WHERE name LIKE :pattern
        LIMIT 20
    """)
    suspend fun searchEvents(pattern: String): List<Event>

    /** id 指定でイベント + 開催日レンジ(初日/最終日)を取得。お気に入りライブ一覧用。 */
    @Query("""
        SELECT e.id, e.brand_id, e.name, e.event_type, e.is_streaming, e.joint_brand_ids,
               MIN(s.date) AS first_date, MAX(s.date) AS last_date
        FROM events e
        LEFT JOIN shows s ON s.event_id = e.id
        WHERE e.id IN (:ids)
        GROUP BY e.id
        ORDER BY COALESCE(MIN(s.date), '') DESC
    """)
    suspend fun fetchEventsWithDateRangeByIds(ids: List<String>): List<EventWithDateRangeRow>

    /**
     * 参加したライブ(イベント)を重複なしで返す。
     * 「イベント単位の参加マーク」と「公演(show)単位の参加マーク→所属イベント」を UNION で統合する
     * (参加を公演単位で付けるユーザーが多く、event マークだけ見るとリストが取りこぼすため)。
     */
    @Query("""
        SELECT e.id, e.brand_id, e.name, e.event_type, e.is_streaming, e.joint_brand_ids,
               MIN(s.date) AS first_date, MAX(s.date) AS last_date
        FROM events e
        LEFT JOIN shows s ON s.event_id = e.id
        WHERE e.id IN (
            SELECT entity_id FROM user_marks
            WHERE entity_type = 'event' AND kind = 'attended' AND bool_value = 1
            UNION
            SELECT sh.event_id FROM user_marks um
            JOIN shows sh ON sh.id = um.entity_id
            WHERE um.entity_type = 'show' AND um.kind = 'attended' AND um.bool_value = 1
        )
        GROUP BY e.id
        ORDER BY COALESCE(MIN(s.date), '') DESC
    """)
    suspend fun fetchAttendedEventsWithDateRange(): List<EventWithDateRangeRow>

    /** 参加したイベントを現地/配信/LVに分類するための生行 (text_value = 参加種別)。 */
    @Query("""
        SELECT event_id, text_value AS atype FROM (
            SELECT entity_id AS event_id, text_value
            FROM user_marks
            WHERE entity_type='event' AND kind='attended' AND bool_value=1
            UNION ALL
            SELECT sh.event_id AS event_id, um.text_value
            FROM user_marks um
            JOIN shows sh ON sh.id = um.entity_id
            WHERE um.entity_type='show' AND um.kind='attended' AND um.bool_value=1
        )
    """)
    suspend fun fetchAttendedEventTypeRows(): List<AttendedEventTypeRow>
}
