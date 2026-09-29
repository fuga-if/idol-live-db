package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * アイドルの声優の履歴 (交代があれば複数行。期間は valid_from / valid_to)。
 *
 * 表の形はコアのマスタ DDL (`master_schema.sql`) と同じ。CloudKit では配らず、同梱の seed の
 * 初回投入とアプリ更新時の入れ直し (SeedImporter) で入る。読むのはコアのスナップショット
 * (CV の表示・CV 名での検索) で、アプリ側から直接は読まない。
 */
@Entity(
    tableName = "idol_voice_actors",
    indices = [Index(name = "idx_idol_voice_actors_idol", value = ["idol_id"])]
)
data class IdolVoiceActor(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,
    @ColumnInfo(name = "idol_id")
    val idolId: String,
    @ColumnInfo(name = "name")
    val name: String,
    @ColumnInfo(name = "valid_from")
    val validFrom: String? = null,
    @ColumnInfo(name = "valid_to")
    val validTo: String? = null
)
