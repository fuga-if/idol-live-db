package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.UserMark

@Dao
interface UserMarkDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(mark: UserMark)

    @Query("DELETE FROM user_marks WHERE entity_type = :type AND entity_id = :id AND kind = :kind")
    suspend fun delete(type: String, id: String, kind: String)

    @Query("SELECT COALESCE((SELECT bool_value FROM user_marks WHERE entity_type = :type AND entity_id = :id AND kind = :kind LIMIT 1), 0)")
    suspend fun isOn(type: String, id: String, kind: String): Boolean

    /** 指定種別 (kind) で ON のエンティティID一覧。 */
    @Query("SELECT entity_id FROM user_marks WHERE entity_type = :type AND kind = :kind AND bool_value = 1 ORDER BY updated_at DESC")
    suspend fun idsFor(type: String, kind: String): List<String>

    @Query("SELECT text_value FROM user_marks WHERE entity_type = :type AND entity_id = :id AND kind = 'memo' LIMIT 1")
    suspend fun memo(type: String, id: String): String?
}
