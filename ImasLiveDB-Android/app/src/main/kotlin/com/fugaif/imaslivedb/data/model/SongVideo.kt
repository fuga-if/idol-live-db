package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/** 参考動画 (構造化コミュニティ・CloudKit Public DB)。iOS の SongVideo と同一。 */
@Entity(
    tableName = "song_videos",
    indices = [Index(name = "idx_song_videos_song", value = ["song_id"])]
)
data class SongVideo(
    @PrimaryKey @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "song_id") val songId: String,
    @ColumnInfo(name = "youtube_url") val youtubeUrl: String,
    @ColumnInfo(name = "video_title") val videoTitle: String?,
    @ColumnInfo(name = "note") val note: String?,
    @ColumnInfo(name = "created_at") val createdAt: String?,
    @ColumnInfo(name = "author_display_name") val authorDisplayName: String?
)
