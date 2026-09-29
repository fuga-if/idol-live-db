package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query

@Dao
interface MetaDao {

    @Query("SELECT value FROM meta WHERE key = :key LIMIT 1")
    suspend fun fetchMetaValue(key: String): String?
}
