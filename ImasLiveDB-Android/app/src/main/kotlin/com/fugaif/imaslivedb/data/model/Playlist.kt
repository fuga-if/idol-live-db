package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * プレイリスト 1 つ。**端末ローカル唯一データ** (iOS `Playlist` と同型)。
 *
 * 中身の曲は [PlaylistItem] に id と並びだけで持つ。並べ替え・足し方の規則は
 * 共有コア (`domain/play_queue.rs`)。クラウドにもサーバにも無いので、
 * expenses と同じく破壊的な移行はしない。
 */
@Entity(tableName = "playlists")
data class Playlist(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,
    @ColumnInfo(name = "name")
    val name: String,
    @ColumnInfo(name = "created_at")
    val createdAt: String,
    @ColumnInfo(name = "updated_at")
    val updatedAt: String,
    /** 公開した「みんなのプレイリスト」の id。公開していなければ null。 */
    @ColumnInfo(name = "published_id")
    val publishedId: String? = null
)

/**
 * プレイリストの中身 1 行。複合主キー (playlist_id, song_id) で同じ曲を 2 回入れない。
 * 並びは [position] (0 始まり)。
 */
@Entity(
    tableName = "playlist_items",
    primaryKeys = ["playlist_id", "song_id"],
    indices = [Index(name = "idx_playlist_items_playlist", value = ["playlist_id"])]
)
data class PlaylistItem(
    @ColumnInfo(name = "playlist_id")
    val playlistId: String,
    @ColumnInfo(name = "song_id")
    val songId: String,
    @ColumnInfo(name = "position")
    val position: Int
)

/** 一覧に出す 1 行 (プレイリストと曲数・先頭の曲)。iOS `PlaylistSummary` と同型。 */
data class PlaylistSummary(
    val playlist: Playlist,
    val songCount: Int,
    /** 先頭の曲 (ジャケに使う)。無ければ null。 */
    val firstSongId: String?
) {
    val id: String get() = playlist.id
}
