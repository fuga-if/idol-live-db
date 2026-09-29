package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.AttendanceMarkProjection
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

    /** ON になっているマークの text_value (参加形態 = live / stream / live_viewing 等)。 */
    @Query("""
        SELECT text_value FROM user_marks
        WHERE entity_type = :type AND entity_id = :id AND kind = :kind AND bool_value = 1 LIMIT 1
    """)
    suspend fun textValue(type: String, id: String, kind: String): String?

    /** 1 件のマーク (bool_value を問わない)。読んでよいかの判定は呼び出し側 (コアの規則)。 */
    @Query("SELECT * FROM user_marks WHERE entity_type = :type AND entity_id = :id AND kind = :kind LIMIT 1")
    suspend fun mark(type: String, id: String, kind: String): UserMark?

    /**
     * ある kind のマークを全部返す (bool_value を問わない)。習熟度のように
     * **一覧の全行が読む値**は、行ごとに引くと件数ぶんクエリが走るので 1 回で読む。
     */
    @Query("SELECT * FROM user_marks WHERE entity_type = :type AND kind = :kind")
    suspend fun marksOf(type: String, kind: String): List<UserMark>

    /** 指定 ID 群のうち ON になっているものだけを返す (公演単位の参加判定用)。 */
    @Query("""
        SELECT entity_id FROM user_marks
        WHERE entity_type = :type AND kind = :kind AND bool_value = 1 AND entity_id IN (:ids)
    """)
    suspend fun onIdsIn(type: String, kind: String, ids: List<String>): List<String>

    /**
     * ON になっているマークを (entity_id, text_value) の射影で取り出す。[textValue] は
     * 種別 1 件しか返さないため、参加形態 (live/stream/live_viewing) を保ったまま
     * 複数件まとめて引きたい経路 (回収の判定を共有コアへ渡す入力) はこちらを使う。
     */
    @Query("""
        SELECT entity_id, text_value FROM user_marks
        WHERE entity_type = :type AND kind = :kind AND bool_value = 1
    """)
    suspend fun attendedMarks(type: String, kind: String): List<AttendanceMarkProjection>

    /** バックアップ全件エクスポート用。 */
    @Query("SELECT * FROM user_marks")
    suspend fun getAll(): List<UserMark>

    /** バックアップ復元用。既存の (entity_type, entity_id, kind) は無視し、新規のみ追加する。 */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(marks: List<UserMark>)
}
