package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.Meta

@Dao
interface MetaDao {

    @Query("SELECT value FROM meta WHERE key = :key LIMIT 1")
    suspend fun fetchMetaValue(key: String): String?

    @Query("SELECT * FROM meta WHERE key = :key LIMIT 1")
    suspend fun fetchMeta(key: String): Meta?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertMeta(meta: Meta)
}
