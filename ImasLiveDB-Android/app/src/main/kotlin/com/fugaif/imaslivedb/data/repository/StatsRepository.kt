package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.BrandSongCount
import com.fugaif.imaslivedb.data.model.DatabaseStats
import com.fugaif.imaslivedb.data.model.YearlyShowCount

class StatsRepository(private val db: AppDatabase) {

    suspend fun fetchBrands(): List<Brand> {
        return db.brandDao().fetchBrands()
    }

    suspend fun fetchBrandSongCounts(): List<BrandSongCount> {
        return db.brandDao().fetchBrandSongCounts()
    }

    suspend fun fetchDatabaseStats(): DatabaseStats {
        return DatabaseStats(
            songCount = db.statsDao().fetchSongCount(),
            idolCount = db.statsDao().fetchIdolCount(),
            eventCount = db.statsDao().fetchEventCount(),
            showCount = db.statsDao().fetchShowCount()
        )
    }

    suspend fun fetchYearlyShowCounts(): List<YearlyShowCount> {
        return db.statsDao().fetchYearlyShowCounts()
    }

    suspend fun fetchMetaValue(key: String): String? {
        return db.metaDao().fetchMetaValue(key)
    }
}
