package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.EventCastRow
import com.fugaif.imaslivedb.data.model.EventStats
import com.fugaif.imaslivedb.data.model.EventWithDateRow

@Dao
interface EventDao {

    @Query("SELECT * FROM events")
    suspend fun fetchEvents(): List<Event>

    @Query("SELECT * FROM events WHERE brand_id = :brandId")
    suspend fun fetchEventsByBrand(brandId: String): List<Event>

    @Query("SELECT * FROM events WHERE id = :id LIMIT 1")
    suspend fun fetchEvent(id: String): Event?

    @Query("""
        SELECT e.id, e.brand_id, e.name, e.event_type, e.is_streaming,
               MIN(s.date) AS first_date
        FROM events e
        LEFT JOIN shows s ON s.event_id = e.id
        GROUP BY e.id
        ORDER BY COALESCE(MIN(s.date), '') DESC
    """)
    suspend fun fetchEventsWithFirstDate(): List<EventWithDateRow>

    @Query("""
        SELECT e.id, e.brand_id, e.name, e.event_type, e.is_streaming,
               MIN(s.date) AS first_date
        FROM events e
        LEFT JOIN shows s ON s.event_id = e.id
        WHERE e.brand_id = :brandId
        GROUP BY e.id
        ORDER BY COALESCE(MIN(s.date), '') DESC
    """)
    suspend fun fetchEventsWithFirstDateByBrand(brandId: String): List<EventWithDateRow>

    @Query("""
        WITH event_shows AS (SELECT id FROM shows WHERE event_id = :eventId)
        SELECT
            (SELECT COUNT(*) FROM event_shows) AS show_count,
            (SELECT COUNT(*) FROM setlist_items WHERE show_id IN (SELECT id FROM event_shows)) AS total_songs,
            (SELECT COUNT(DISTINCT song_id) FROM setlist_items WHERE show_id IN (SELECT id FROM event_shows)) AS unique_songs,
            (SELECT COUNT(DISTINCT idol_id) FROM show_cast WHERE show_id IN (SELECT id FROM event_shows)) AS cast_count
    """)
    suspend fun fetchEventStats(eventId: String): EventStats

    @Query("""
        SELECT DISTINCT i.id AS id, i.name AS name, i.color AS idol_color, i.name AS idol_name, i.id AS idol_id
        FROM show_cast sc
        JOIN shows sh ON sc.show_id = sh.id
        JOIN idols i ON sc.idol_id = i.id
        WHERE sh.event_id = :eventId
        ORDER BY i.sort_order
    """)
    suspend fun fetchEventCastMembers(eventId: String): List<EventCastRow>

    @Query("""
        SELECT * FROM events
        WHERE name LIKE :pattern
        LIMIT 20
    """)
    suspend fun searchEvents(pattern: String): List<Event>
}
