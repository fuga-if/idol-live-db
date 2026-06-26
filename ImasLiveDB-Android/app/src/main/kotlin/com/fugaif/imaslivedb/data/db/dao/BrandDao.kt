package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.BrandSongCount

@Dao
interface BrandDao {

    @Query("SELECT * FROM brands ORDER BY sort_order")
    suspend fun fetchBrands(): List<Brand>

    @Query("""
        SELECT b.id, b.short_name, b.color, COUNT(s.id) AS song_count
        FROM brands b LEFT JOIN songs s ON b.id = s.brand_id
        GROUP BY b.id ORDER BY b.sort_order
    """)
    suspend fun fetchBrandSongCounts(): List<BrandSongCount>
}
