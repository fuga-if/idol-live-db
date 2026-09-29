package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.SongVideo

@Dao
interface CommunityDao {
    @Query("SELECT * FROM song_videos WHERE song_id = :songId ORDER BY created_at DESC")
    suspend fun videosForSong(songId: String): List<SongVideo>
}
