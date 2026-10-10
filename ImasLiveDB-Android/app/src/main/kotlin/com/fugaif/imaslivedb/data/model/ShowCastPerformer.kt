package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity

/**
 * その公演でアイドルを演じた人 (声優以外が演じたときだけ行がある。舞台の俳優など)。
 *
 * 表の形はコアのマスタ DDL (`master_schema.sql`) と同じ。CloudKit では配らず、同梱の seed の
 * 初回投入とアプリ更新時の入れ直し (SeedImporter) で入る。読むのはコアのスナップショット
 * (公演の歌唱者の演者名) で、アプリ側から直接は読まない。演者の決め方はコアの `show_performer`。
 */
@Entity(
    tableName = "show_cast_performers",
    primaryKeys = ["show_id", "idol_id"]
)
data class ShowCastPerformer(
    @ColumnInfo(name = "show_id")
    val showId: String,

    @ColumnInfo(name = "idol_id")
    val idolId: String,

    @ColumnInfo(name = "performer_name")
    val performerName: String
)
