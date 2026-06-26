package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/** コーレス (構造化コミュニティ・CloudKit Public DB)。iOS の SongCall と同一。 */
@Entity(
    tableName = "song_calls",
    indices = [Index(name = "idx_song_calls_song", value = ["song_id"])]
)
data class SongCall(
    @PrimaryKey @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "song_id") val songId: String,
    @ColumnInfo(name = "call_text") val callText: String,
    @ColumnInfo(name = "source_url") val sourceUrl: String?,
    @ColumnInfo(name = "created_at") val createdAt: String?,
    @ColumnInfo(name = "author_display_name") val authorDisplayName: String?
)
