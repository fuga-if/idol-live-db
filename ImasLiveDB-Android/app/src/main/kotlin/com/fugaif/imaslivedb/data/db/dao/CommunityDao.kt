package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.SongCall
import com.fugaif.imaslivedb.data.model.SongVideo

@Dao
interface CommunityDao {
    @Query("SELECT * FROM song_calls WHERE song_id = :songId ORDER BY created_at DESC")
    suspend fun callsForSong(songId: String): List<SongCall>

    @Query("SELECT * FROM song_videos WHERE song_id = :songId ORDER BY created_at DESC")
    suspend fun videosForSong(songId: String): List<SongVideo>

    /** コーレス投稿/編集 (POST /edits 成功後) の楽観的ローカル反映。iOS upsertSongCalls の移植。 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertCalls(calls: List<SongCall>)
}
