package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.ImasUnit

@Dao
interface UnitDao {

    @Query("SELECT * FROM units WHERE id = :id LIMIT 1")
    suspend fun fetchUnit(id: String): ImasUnit?

    @Query("SELECT * FROM units WHERE brand_id = :brandId ORDER BY name")
    suspend fun fetchUnitsByBrand(brandId: String): List<ImasUnit>

    @Query("SELECT * FROM units ORDER BY name")
    suspend fun fetchAllUnits(): List<ImasUnit>

    /** タグが似ているユニット表示用。N+1を避けてIN句で一括取得する (IdolDao.fetchIdolsByIds と同型)。 */
    @Query("SELECT * FROM units WHERE id IN (:ids)")
    suspend fun fetchUnitsByIds(ids: List<String>): List<ImasUnit>

    /** ユニット一覧画面用。「曲ありユニットのみ」表示のため、楽曲が1曲でも紐づくユニットに絞る。 */
    @Query("""
        SELECT DISTINCT u.* FROM units u
        JOIN songs s ON s.unit_id = u.id
        ORDER BY u.name
    """)
    suspend fun fetchUnitsWithSongs(): List<ImasUnit>
}
