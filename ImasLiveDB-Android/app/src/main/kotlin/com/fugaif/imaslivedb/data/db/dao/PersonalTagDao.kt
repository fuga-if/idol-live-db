package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.PersonalTag

@Dao
interface PersonalTagDao {

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(tag: PersonalTag)

    @Query("DELETE FROM personal_tags WHERE entity_type = :entityType AND entity_id = :entityId AND tag_name = :tagName")
    suspend fun delete(entityType: String, entityId: String, tagName: String)

    @Query("SELECT * FROM personal_tags WHERE entity_type = :entityType AND entity_id = :entityId ORDER BY created_at")
    suspend fun forEntity(entityType: String, entityId: String): List<PersonalTag>

    /** バックアップエクスポート用の全件取得。 */
    @Query("SELECT * FROM personal_tags")
    suspend fun getAll(): List<PersonalTag>

    /** バックアップ復元用。既存の (entity_type, entity_id, tag_name) は無視し、新規のみ追加する。 */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(tags: List<PersonalTag>)
}
