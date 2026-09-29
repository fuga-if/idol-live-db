package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.ImasUnit

@Dao
interface UnitDao {

    /** タグが似ているユニット表示用。N+1を避けてIN句で一括取得する (IdolDao.fetchIdolsByIds と同型)。 */
    @Query("SELECT * FROM units WHERE id IN (:ids)")
    suspend fun fetchUnitsByIds(ids: List<String>): List<ImasUnit>
}
