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
        /** チケット受付 (ticket_sales)。自分の申込の記録 ([APPLICATION]) だけを付ける。iOS と同じ名前。 */
        const val TICKET_SALE = "ticket_sale"
        // kinds
        const val PICK = "pick"           // 担当
        const val FAVORITE = "favorite"   // お気に入り
        const val ATTENDED = "attended"   // 参加
        const val MEMO = "memo"
        const val OWNED = "owned"         // 所持 (KAMISABI カード等の収集物)
        /** 楽曲の習熟度。text_value に序数 "1".."8" を入れる (ラベルは設定側)。 */
        const val MASTERY = "mastery"
        /** 歌詞の「ここ好き」。曲 1 行の text_value に行 ID の並び (並べ方はコアの lyricLikesToggle)。
         *  歌詞本文は入れない (JASRAC / NexTone 許諾の条件)。iOS と同じ kind 名。 */
        const val LYRIC_LIKES = "lyricLikes"
        /** チケット受付への申込の記録。text_value に保存値 ("applied"/"won"/"lost"、コアの ticketApplicationRaw)。 */
        const val APPLICATION = "application"
    }
}

/**
 * `user_marks` の (entity_id, text_value) だけの射影。
 * 参加形態 (live/stream/live_viewing) を保ったまま共有コアの
 * `uniffi.imas_core.AttendanceMarkRecord` へ詰め替えるための Room クエリ結果型
 * ([com.fugaif.imaslivedb.data.db.dao.UserMarkDao.attendedMarks])。
 */
data class AttendanceMarkProjection(
    @ColumnInfo(name = "entity_id") val entityId: String,
    @ColumnInfo(name = "text_value") val textValue: String?
)
