package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.SongCall
import com.fugaif.imaslivedb.data.model.SongVideo

@Dao
interface CommunityDao {
    @Query("SELECT * FROM song_calls WHERE song_id = :songId ORDER BY created_at DESC")
    suspend fun callsForSong(songId: String): List<SongCall>

    @Query("SELECT * FROM song_videos WHERE song_id = :songId ORDER BY created_at DESC")
    suspend fun videosForSong(songId: String): List<SongVideo>
}
