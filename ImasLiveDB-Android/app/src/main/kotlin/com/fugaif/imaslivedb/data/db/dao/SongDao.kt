package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.RawQuery
import androidx.sqlite.db.SupportSQLiteQuery
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song

@Dao
interface SongDao {

    @Query("SELECT * FROM songs WHERE id = :id LIMIT 1")
    suspend fun fetchSong(id: String): Song?

    @Query("SELECT * FROM songs WHERE id IN (:ids)")
    suspend fun fetchSongsByIds(ids: List<String>): List<Song>

    /**
     * スナップショット (共有コア) が返した idol id 列を Idol 実体へ引き直すための一括取得。
     * 並びはコアが返した id 列が正なので、呼び出し側 (SongRepository) で並べ直す。
     */
    @Query("SELECT * FROM idols WHERE id IN (:ids)")
    suspend fun fetchIdolsByIds(ids: List<String>): List<Idol>

    @RawQuery
    suspend fun fetchSongsRaw(query: SupportSQLiteQuery): List<Song>
}
