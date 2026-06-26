package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.RawQuery
import androidx.sqlite.db.SupportSQLiteQuery
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.PerformanceHistoryRow
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongPerfCount
import com.fugaif.imaslivedb.data.model.SongPlayCount

@Dao
interface SongDao {

    @Query("SELECT * FROM songs WHERE id = :id LIMIT 1")
    suspend fun fetchSong(id: String): Song?

    @RawQuery
    suspend fun fetchSongsRaw(query: SupportSQLiteQuery): List<Song>

    @Query("""
        SELECT i.* FROM idols i
        JOIN song_artists sa ON i.id = sa.idol_id
        WHERE sa.song_id = :songId
        ORDER BY i.sort_order
    """)
    suspend fun fetchSongArtists(songId: String): List<Idol>

    @Query("""
        SELECT i.* FROM idols i
        JOIN song_artists sa ON i.id = sa.idol_id
        WHERE sa.song_id = :songId AND sa.role = :role
        ORDER BY i.sort_order
    """)
    suspend fun fetchSongArtistsByRole(songId: String, role: String): List<Idol>

    @Query("""
        SELECT sh.id AS show_id, e.id AS event_id,
               e.name AS event_name, sh.name AS show_name, sh.date, sh.venue,
               si.position, si.section
        FROM setlist_items si
        JOIN shows sh ON si.show_id = sh.id
        JOIN events e ON sh.event_id = e.id
        WHERE si.song_id = :songId
        ORDER BY sh.date DESC
    """)
    suspend fun fetchSongPerformanceHistory(songId: String): List<PerformanceHistoryRow>

    @Query("""
        SELECT s.id, s.title, COUNT(si.id) AS play_count, s.brand_id
        FROM songs s
        JOIN setlist_items si ON s.id = si.song_id
        GROUP BY s.id
        ORDER BY play_count DESC
        LIMIT :limit
    """)
    suspend fun fetchSongPlayCountRanking(limit: Int = 20): List<SongPlayCount>

    @Query("SELECT song_id, COUNT(*) as cnt FROM setlist_items GROUP BY song_id")
    suspend fun fetchSongPerfCounts(): List<SongPerfCount>

    @Query("""
        SELECT DISTINCT cd_series FROM songs
        WHERE cd_series IS NOT NULL AND cd_series != ''
        ORDER BY cd_series
    """)
    suspend fun fetchCdSeriesList(): List<String>

    @Query("SELECT name FROM events ORDER BY name")
    suspend fun fetchEventNames(): List<String>

    @Query("SELECT * FROM songs WHERE unit_id = :unitId ORDER BY release_date")
    suspend fun fetchUnitSongs(unitId: String): List<Song>

    @Query("""
        SELECT s.* FROM songs s
        JOIN song_artists sa ON s.id = sa.song_id
        WHERE sa.idol_id = :idolId
        ORDER BY s.release_date DESC
    """)
    suspend fun fetchIdolSongs(idolId: String): List<Song>

    @Query("""
        SELECT s.* FROM songs s
        JOIN song_artists sa ON s.id = sa.song_id
        WHERE sa.idol_id = :idolId AND sa.role = :role
        ORDER BY s.release_date DESC
    """)
    suspend fun fetchIdolSongsByRole(idolId: String, role: String): List<Song>

    @Query("""
        SELECT * FROM songs
        WHERE (title LIKE :pattern OR title_kana LIKE :pattern)
        LIMIT 20
    """)
    suspend fun searchSongs(pattern: String): List<Song>
}
