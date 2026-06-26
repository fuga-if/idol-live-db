package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index

/**
 * ユーザーのマーク (担当 pick / お気に入り favorite / 参加 attended / メモ memo)。
 * iOS の user_marks テーブルと同一スキーマ。端末ローカル保存 (将来 CloudKit private 同期予定)。
 */
@Entity(
    tableName = "user_marks",
    primaryKeys = ["entity_type", "entity_id", "kind"],
    indices = [Index(name = "idx_user_marks_entity", value = ["entity_type", "entity_id"])]
)
data class UserMark(
    @ColumnInfo(name = "entity_type") val entityType: String,
    @ColumnInfo(name = "entity_id") val entityId: String,
    @ColumnInfo(name = "kind") val kind: String,
    @ColumnInfo(name = "bool_value") val boolValue: Boolean,
    @ColumnInfo(name = "text_value") val textValue: String?,
    @ColumnInfo(name = "updated_at") val updatedAt: String
) {
    companion object {
        // entity types
        const val IDOL = "idol"
        const val SONG = "song"
        const val EVENT = "event"
        const val SHOW = "show"
        // kinds
        const val PICK = "pick"           // 担当
        const val FAVORITE = "favorite"   // お気に入り
        const val ATTENDED = "attended"   // 参加
        const val MEMO = "memo"
    }
}
