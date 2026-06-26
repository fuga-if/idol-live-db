package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.Show

@Dao
interface ShowDao {

    @Query("SELECT * FROM shows WHERE event_id = :eventId ORDER BY sort_order")
    suspend fun fetchShows(eventId: String): List<Show>

    @Query("SELECT * FROM shows WHERE id = :id LIMIT 1")
    suspend fun fetchShow(id: String): Show?

    @Query("SELECT * FROM shows ORDER BY date DESC LIMIT 1")
    suspend fun fetchLatestShow(): Show?

    @Query("SELECT COUNT(*) FROM shows")
    suspend fun fetchShowCount(): Int
}
