package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.Brand

@Dao
interface BrandDao {

    @Query("SELECT * FROM brands ORDER BY sort_order")
    suspend fun fetchBrands(): List<Brand>
}
