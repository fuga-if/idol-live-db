package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.PersonalTag
import java.time.Instant

/** 個人用タグを管理 (端末ローカルのみ、サーバーには一切送信しない)。 */
class PersonalTagRepository(private val db: AppDatabase) {

    private val dao get() = db.personalTagDao()

    suspend fun tagsFor(entityType: String, entityId: String): List<PersonalTag> =
        dao.forEntity(entityType, entityId)

    suspend fun addTag(entityType: String, entityId: String, name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        dao.insert(PersonalTag(entityType, entityId, trimmed, Instant.now().toString()))
    }

    suspend fun removeTag(entityType: String, entityId: String, name: String) {
        dao.delete(entityType, entityId, name)
    }

    /** バックアップエクスポート用の全件取得。 */
    suspend fun getAll(): List<PersonalTag> = dao.getAll()

    /**
     * バックアップからの復元 (非破壊): ローカルに無い (entityType, entityId, tagName) の組だけ追加する。
     * 既存のタグは一切上書きしない。
     */
    suspend fun restoreIfAbsent(tags: List<PersonalTag>): Int {
        val existingKeys = dao.getAll().map { Triple(it.entityType, it.entityId, it.tagName) }.toSet()
        val toInsert = tags.filter { Triple(it.entityType, it.entityId, it.tagName) !in existingKeys }
        if (toInsert.isNotEmpty()) dao.insertAll(toInsert)
        return toInsert.size
    }
}
