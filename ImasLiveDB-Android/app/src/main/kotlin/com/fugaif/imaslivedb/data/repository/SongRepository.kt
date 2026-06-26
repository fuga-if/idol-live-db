package com.fugaif.imaslivedb.data.repository

import androidx.sqlite.db.SimpleSQLiteQuery
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.PerformanceHistoryRow
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongPlayCount
import com.fugaif.imaslivedb.data.model.SongSearchFilter
import com.fugaif.imaslivedb.data.model.SongSortOrder
import com.fugaif.imaslivedb.data.model.SongWithArtists

class SongRepository(private val db: AppDatabase) {

    suspend fun fetchSongs(
        filter: SongSearchFilter = SongSearchFilter(),
        sortOrder: SongSortOrder = SongSortOrder.TITLE_KANA
    ): List<SongWithArtists> {
        val conditions = mutableListOf<String>()
        val args = mutableListOf<Any>()

        // Exclude remixes by default
        if (!filter.includeRemixes) {
            conditions.add("s.parent_song_id IS NULL")
        }

        if (filter.brandId != null) {
            conditions.add("s.brand_id = ?")
            args.add(filter.brandId)
        }
        if (!filter.title.isNullOrEmpty()) {
            conditions.add("(s.title LIKE ? OR s.title_kana LIKE ?)")
            args.add("%${filter.title}%")
            args.add("%${filter.title}%")
        }
        if (!filter.songwriter.isNullOrEmpty()) {
            conditions.add("(s.composer LIKE ? OR s.lyricist LIKE ? OR s.arranger LIKE ?)")
            args.add("%${filter.songwriter}%")
            args.add("%${filter.songwriter}%")
            args.add("%${filter.songwriter}%")
        }
        if (!filter.cdSeries.isNullOrEmpty()) {
            conditions.add("s.cd_series LIKE ?")
            args.add("%${filter.cdSeries}%")
        }
        if (filter.songType != null) {
            conditions.add("s.song_type = ?")
            args.add(filter.songType)
        }
        if (filter.excludeLiveOnly) {
            // ライブ履歴のみのファントム曲を除外。カタログメタ(配信ID/原唱者/リリース日/CD/作家)を
            // 1つでも持てば正規曲として出す。何も無い曲(セトリ追加で生まれただけ)だけ隠す。
            conditions.add(
                """(
                    (s.apple_music_id IS NOT NULL AND s.apple_music_id <> '')
                    OR (s.release_date IS NOT NULL AND s.release_date <> '')
                    OR (s.cd_title IS NOT NULL AND s.cd_title <> '')
                    OR (s.cd_series IS NOT NULL AND s.cd_series <> '')
                    OR (s.composer IS NOT NULL AND s.composer <> '')
                    OR (s.lyricist IS NOT NULL AND s.lyricist <> '')
                    OR (s.arranger IS NOT NULL AND s.arranger <> '')
                    OR EXISTS (SELECT 1 FROM song_artists sa WHERE sa.song_id = s.id)
                )""".trimIndent()
            )
        }

        val hasIdolIds = !filter.idolIds.isNullOrEmpty()
        val hasIdolName = !filter.idolName.isNullOrEmpty()
        val needsArtistJoin = hasIdolIds || hasIdolName
        val needsLiveJoin = !filter.liveName.isNullOrEmpty()

        var sql = "SELECT DISTINCT s.* FROM songs s"
        if (needsArtistJoin) {
            sql += " JOIN song_artists sa ON s.id = sa.song_id JOIN idols i ON sa.idol_id = i.id"
            if (hasIdolIds) {
                val placeholders = filter.idolIds!!.joinToString(",") { "?" }
                conditions.add("sa.idol_id IN ($placeholders)")
                args.addAll(filter.idolIds)
            } else if (hasIdolName) {
                conditions.add("(i.name LIKE ? OR i.name_kana LIKE ?)")
                args.add("%${filter.idolName}%")
                args.add("%${filter.idolName}%")
            }
        }
        if (needsLiveJoin) {
            sql += " JOIN setlist_items si ON s.id = si.song_id JOIN shows sh ON si.show_id = sh.id JOIN events ev ON sh.event_id = ev.id"
            conditions.add("ev.name LIKE ?")
            args.add("%${filter.liveName}%")
        }

        if (conditions.isNotEmpty()) {
            sql += " WHERE " + conditions.joinToString(" AND ")
        }

        when (sortOrder) {
            SongSortOrder.TITLE_KANA -> sql += " ORDER BY s.title_kana, s.title"
            SongSortOrder.RELEASE_DATE -> sql += " ORDER BY s.release_date DESC, s.title_kana"
            SongSortOrder.PERFORMANCE_COUNT -> { /* sorted in memory below */ }
        }

        val songs = db.songDao().fetchSongsRaw(SimpleSQLiteQuery(sql, args.toTypedArray()))

        var results = songs.map { song ->
            SongWithArtists(song = song, artistNames = song.singerLabel ?: "")
        }

        if (sortOrder == SongSortOrder.PERFORMANCE_COUNT) {
            val counts = db.songDao().fetchSongPerfCounts()
            val countMap = counts.associate { it.songId to it.cnt }
            results = results.sortedByDescending { countMap[it.song.id] ?: 0 }
        }

        return results
    }

    suspend fun fetchSong(id: String): Song? {
        return db.songDao().fetchSong(id)
    }

    suspend fun fetchSongArtists(songId: String, role: String? = null): List<Idol> {
        return if (role != null) {
            db.songDao().fetchSongArtistsByRole(songId, role)
        } else {
            db.songDao().fetchSongArtists(songId)
        }
    }

    suspend fun fetchSongPerformanceHistory(songId: String): List<PerformanceHistoryRow> {
        return db.songDao().fetchSongPerformanceHistory(songId)
    }

    suspend fun fetchSongPlayCountRanking(limit: Int = 20): List<SongPlayCount> {
        return db.songDao().fetchSongPlayCountRanking(limit)
    }

    suspend fun fetchCdSeriesList(): List<String> {
        return db.songDao().fetchCdSeriesList()
    }

    suspend fun fetchEventNames(): List<String> {
        return db.songDao().fetchEventNames()
    }

    suspend fun fetchUnitSongs(unitId: String): List<Song> {
        return db.songDao().fetchUnitSongs(unitId)
    }

    suspend fun fetchIdolSongs(idolId: String, role: String? = null): List<Song> {
        return if (role != null) {
            db.songDao().fetchIdolSongsByRole(idolId, role)
        } else {
            db.songDao().fetchIdolSongs(idolId)
        }
    }
}
