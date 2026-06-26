package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song

@Dao
interface SearchDao {

    @Query("""
        SELECT * FROM songs
        WHERE title LIKE :pattern OR title_kana LIKE :pattern
        LIMIT 20
    """)
    suspend fun searchSongs(pattern: String): List<Song>

    @Query("""
        SELECT * FROM idols
        WHERE name LIKE :pattern OR name_kana LIKE :pattern
        LIMIT 20
    """)
    suspend fun searchIdols(pattern: String): List<Idol>

    @Query("""
        SELECT * FROM events
        WHERE name LIKE :pattern
        LIMIT 20
    """)
    suspend fun searchEvents(pattern: String): List<Event>
}
