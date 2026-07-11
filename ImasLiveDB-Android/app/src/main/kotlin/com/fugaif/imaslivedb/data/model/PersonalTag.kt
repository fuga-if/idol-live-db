package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity

/**
 * 個人用タグ。コミュニティタグ (community_tags, サーバー共有) とは別に、
 * 端末ローカルのみに保存される自由入力タグ。サーバーには一切送信しない。
 */
@Entity(
    tableName = "personal_tags",
    primaryKeys = ["entity_type", "entity_id", "tag_name"]
)
data class PersonalTag(
    @ColumnInfo(name = "entity_type") val entityType: String,
    @ColumnInfo(name = "entity_id") val entityId: String,
    @ColumnInfo(name = "tag_name") val tagName: String,
    @ColumnInfo(name = "created_at") val createdAt: String
) {
    companion object {
        // entity types (UserMark と同じ命名)
        const val IDOL = "idol"
        const val SONG = "song"
        const val EVENT = "event"
        const val SHOW = "show"
    }
}
