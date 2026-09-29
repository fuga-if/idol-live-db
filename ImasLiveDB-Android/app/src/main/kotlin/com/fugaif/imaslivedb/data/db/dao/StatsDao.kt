package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query

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

    // MARK: - Collection Dashboard (iOS AppDatabase の回収ダッシュボード関連クエリの移植)

    /** 最新公演のセトリ曲数。 */
    @Query("SELECT COUNT(*) FROM setlist_items WHERE show_id = :showId")
    suspend fun fetchSetlistCount(showId: String): Int
}
