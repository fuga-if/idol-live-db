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
}
