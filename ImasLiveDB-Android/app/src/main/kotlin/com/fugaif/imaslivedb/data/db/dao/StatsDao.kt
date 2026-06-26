package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
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
}
