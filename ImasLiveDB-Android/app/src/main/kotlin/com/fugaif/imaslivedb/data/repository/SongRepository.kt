package com.fugaif.imaslivedb.data.repository

import androidx.sqlite.db.SimpleSQLiteQuery
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.PerformanceHistoryRow
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SoloOriginalSingerRow
import com.fugaif.imaslivedb.data.model.SongPlayCount
import com.fugaif.imaslivedb.data.model.SongSearchFilter
import com.fugaif.imaslivedb.data.model.SongSortOrder
import com.fugaif.imaslivedb.data.model.SongWithArtists

class SongRepository(private val db: AppDatabase) {

    suspend fun fetchSongs(
        filter: SongSearchFilter = SongSearchFilter(),
        sortOrder: SongSortOrder = SongSortOrder.TITLE_KANA,
        // nil = sortOrder のデフォルト方向 (iOS SongListView と同じ tri-state)。
        ascending: Boolean? = null,
        // タグ絞り込み(TagFilterSheet)の結果song_id集合。Worker D1 (コミュニティタグ)は端末外データなので
        // ローカルSQLに直接JOINできず、呼び出し側(SongListViewModel)が解決した集合をここでIN句に渡す。
        // 非nullかつ空集合 = 該当曲なし(クエリを投げず即空リストで返す)。
        tagFilterSongIds: Set<String>? = null
    ): List<SongWithArtists> {
        if (tagFilterSongIds != null && tagFilterSongIds.isEmpty()) return emptyList()

        val conditions = mutableListOf<String>()
        val args = mutableListOf<Any>()

        if (tagFilterSongIds != null) {
            val placeholders = tagFilterSongIds.joinToString(",") { "?" }
            conditions.add("s.id IN ($placeholders)")
            args.addAll(tagFilterSongIds)
        }

        // Exclude remixes by default
        if (!filter.includeRemixes) {
            conditions.add("s.parent_song_id IS NULL")
        }

        if (filter.brandId != null) {
            conditions.add("s.brand_id = ?")
            args.add(filter.brandId)
        } else if (!filter.includeOtherBrand) {
            // ブランド未選択(全件)のときは既定で other (歌枠カバー等) を隠す。
            conditions.add("s.brand_id IS NOT 'other'")
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
            // 持ち曲 (role='original') だけに絞る。role を見ないと 'performer'
            // (そのアイドルがライブで一度歌っただけの曲) まで拾ってしまい、
            // 「このアイドルの曲」を見たいのに他人の持ち曲がずらりと並ぶ。
            sql += " JOIN song_artists sa ON s.id = sa.song_id AND sa.role = 'original'"
            sql += " JOIN idols i ON sa.idol_id = i.id"
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

        val asc = ascending ?: sortOrder.defaultAscending
        val dir = if (asc) "ASC" else "DESC"
        when (sortOrder) {
            SongSortOrder.TITLE_KANA -> sql += " ORDER BY s.title_kana $dir, s.title $dir"
            SongSortOrder.RELEASE_DATE -> sql += " ORDER BY s.release_date $dir, s.title_kana"
            SongSortOrder.PERFORMANCE_COUNT, SongSortOrder.COLLECTED_COUNT, SongSortOrder.COLLECTED_RATE ->
                { /* sorted in memory below */ }
        }

        val songs = db.songDao().fetchSongsRaw(SimpleSQLiteQuery(sql, args.toTypedArray()))

        var results = songs.map { song ->
            SongWithArtists(song = song, artistNames = song.singerLabel ?: "")
        }

        when (sortOrder) {
            SongSortOrder.TITLE_KANA, SongSortOrder.RELEASE_DATE -> {}
            SongSortOrder.PERFORMANCE_COUNT -> {
                val countMap = db.songDao().fetchSongPerfCounts().associate { it.songId to it.cnt }
                results = if (asc) results.sortedBy { countMap[it.song.id] ?: 0 }
                else results.sortedByDescending { countMap[it.song.id] ?: 0 }
            }
            SongSortOrder.COLLECTED_COUNT -> {
                val countMap = db.songDao().fetchSongCollectedCounts().associate { it.songId to it.cnt }
                results = if (asc) results.sortedBy { countMap[it.song.id] ?: 0 }
                else results.sortedByDescending { countMap[it.song.id] ?: 0 }
            }
            SongSortOrder.COLLECTED_RATE -> {
                val attendedMap = db.songDao().fetchSongCollectedCounts().associate { it.songId to it.cnt }
                val totalMap = db.songDao().fetchSongPerfCounts().associate { it.songId to it.cnt }
                fun rate(id: String): Double {
                    val total = totalMap[id] ?: 0
                    return if (total > 0) (attendedMap[id] ?: 0).toDouble() / total else 0.0
                }
                results = if (asc) {
                    results.sortedWith(compareBy({ rate(it.song.id) }, { attendedMap[it.song.id] ?: 0 }))
                } else {
                    results.sortedWith(
                        compareByDescending<SongWithArtists> { rate(it.song.id) }
                            .thenByDescending { attendedMap[it.song.id] ?: 0 }
                    )
                }
            }
        }

        return results
    }

    /** song_id → 現地回収回数 (行アイコン/回収済みフィルタ用の bulk 取得)。 */
    suspend fun fetchSongCollectedCounts(): Map<String, Int> =
        db.songDao().fetchSongCollectedCounts().associate { it.songId to it.cnt }

    /** 指定アイドルのいずれかが歌唱者にいる song_id 集合 (担当マーク由来の「担当」表示/絞り込み用)。 */
    suspend fun fetchSongIdsWithAnyArtist(idolIds: Collection<String>): Set<String> {
        if (idolIds.isEmpty()) return emptySet()
        return db.songDao().fetchSongIdsWithAnyArtist(idolIds.toList()).toSet()
    }

    suspend fun fetchSong(id: String): Song? {
        return db.songDao().fetchSong(id)
    }

    /** タグ詳細画面の曲ランキング表示用。N+1を避けてIN句で一括取得する。 */
    suspend fun fetchSongsByIds(ids: List<String>): List<Song> {
        if (ids.isEmpty()) return emptyList()
        return db.songDao().fetchSongsByIds(ids)
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

    suspend fun fetchCollectedShows(songId: String): List<PerformanceHistoryRow> {
        return db.songDao().fetchCollectedShows(songId)
    }

    /**
     * 関連楽曲 (同じシリーズ/ユニット/原唱アイドルでつながる曲)。iOS fetchRelatedSongs と同じ重み付け
     * (シリーズ=3, ユニット=2, 原唱共有=1) で足し合わせ、スコア降順→リリース日降順で並べる。
     */
    suspend fun fetchRelatedSongs(song: Song, limit: Int = 8): List<Song> {
        val dao = db.songDao()
        val ordered = mutableListOf<String>()
        val byId = mutableMapOf<String, Pair<Song, Int>>()
        fun add(songs: List<Song>, weight: Int) {
            for (s in songs) {
                if (s.id == song.id) continue
                if (byId[s.id] == null) ordered.add(s.id)
                val (existing, score) = byId[s.id] ?: (s to 0)
                byId[s.id] = existing to (score + weight)
            }
        }

        val seriesGroup = dao.fetchSeriesGroup(song.id)
        if (!seriesGroup.isNullOrEmpty()) {
            add(dao.fetchSongsBySeriesGroup(seriesGroup), weight = 3)
        }
        if (!song.unitId.isNullOrEmpty()) {
            add(dao.fetchUnitSongs(song.unitId), weight = 2)
        }
        add(dao.fetchSongsSharingOriginalArtist(song.id), weight = 1)

        return ordered.mapNotNull { byId[it] }
            .sortedWith(compareByDescending<Pair<Song, Int>> { it.second }.thenByDescending { it.first.releaseDate ?: "" })
            .take(limit)
            .map { it.first }
    }

    suspend fun fetchIdolSongs(idolId: String, role: String? = null): List<Song> {
        return if (role != null) {
            db.songDao().fetchIdolSongsByRole(idolId, role)
        } else {
            db.songDao().fetchIdolSongs(idolId)
        }
    }

    /** ソロ曲クイズ用: ソロ曲と原唱アイドルの対応行 (song_id, idol_id)。 */
    suspend fun fetchSoloOriginalSingers(): List<SoloOriginalSingerRow> {
        return db.songDao().fetchSoloOriginalSingers()
    }

    /**
     * イントロドン出題プール。Android には Apple Music フル再生の手段が無いため、
     * iOS の `apple_music_id` 条件ではなく実際に再生できる `preview_url` の有無で絞り込む。
     */
    suspend fun fetchIntroDonSongs(brandIds: Set<String> = emptySet()): List<Song> {
        var sql = "SELECT * FROM songs WHERE preview_url IS NOT NULL AND preview_url != '' AND parent_song_id IS NULL"
        val args = mutableListOf<Any>()
        if (brandIds.isNotEmpty()) {
            sql += " AND brand_id IN (${brandIds.joinToString(",") { "?" }})"
            args.addAll(brandIds)
        }
        sql += " ORDER BY RANDOM()"
        return db.songDao().fetchSongsRaw(SimpleSQLiteQuery(sql, args.toTypedArray()))
    }
}
