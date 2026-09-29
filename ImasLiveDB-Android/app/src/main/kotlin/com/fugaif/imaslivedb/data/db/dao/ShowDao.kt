package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.Show

@Dao
interface ShowDao {

    /**
     * 公演実体の一括取得。スナップショット経路が返す「表示順の show_id 列」を
     * Room の [Show] へ引き直す (hydration) ために使う。並びは呼び出し側が id 列で戻す。
     */
    @Query("SELECT * FROM shows WHERE id IN (:ids)")
    suspend fun fetchShowsByIds(ids: List<String>): List<Show>

    @Query("SELECT COUNT(*) FROM shows")
    suspend fun fetchShowCount(): Int
}
