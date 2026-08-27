package com.fugaif.imaslivedb.data.repository

import androidx.sqlite.db.SimpleSQLiteQuery
import com.fugaif.imaslivedb.data.core.FuzzySearch
import com.fugaif.imaslivedb.data.core.SQLITE_BINARY_ORDER
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.core.hydrateInOrder
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.AlbumSummary
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.PerformanceHistoryRow
import com.fugaif.imaslivedb.data.model.SeriesSummary
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SoloOriginalSingerRow
import com.fugaif.imaslivedb.data.model.SongPlayCount
import com.fugaif.imaslivedb.data.model.SongSearchFilter
import com.fugaif.imaslivedb.data.model.SongSortOrder
import com.fugaif.imaslivedb.data.model.SongWithArtists
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.PerformanceHistoryEntry
import uniffi.imas_core.SongListFilter
import uniffi.imas_core.SongListSort
import uniffi.imas_core.splitCreditNames

/**
 * クリエイター絞り込みの 1 行 (曲 + その曲でその人が担った役割)。
 *
 * iOS `SongWithRoles` の移植。`artists` は iOS でも常に空で埋められていて、表示は
 * `song.singerLabel` を見るので持たない。
 */
data class SongWithRoles(
    val song: Song,
    /** ["作曲", "編曲"] のような役割ラベル。並びは 作曲 → 作詞 → 編曲。 */
    val roles: List<String>
) {
    val rolesLabel: String get() = roles.joinToString("・")
}

/**
 * SQLite の LIKE パターン中の特殊文字を潰す。SQL 側で `ESCAPE '\'` を付けて使うこと。
 * (iOS `String.likeEscaped` と対。エスケープ文字自体を最初に置き換える順序が要。)
 */
private fun String.likeEscaped(): String =
    replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")

/**
 * 楽曲の読み取り口。
 *
 * 読み取りは共有コア (imas-core) のインメモリスナップショットを第一経路とし、
 * 未ロード・利用不可のときだけ従来の Room/SQL 経路へフォールバックする
 * (iOS と同一ロジック・同一結果を返すのがスナップショット経路の目的)。
 *
 * コアの FFI 規約により一覧クエリは「表示順の song_id 列」で返るので、
 * Song 実体への引き直し (hydration) はこのリポジトリが Room で行う。
 * user_marks (参加マーク等) はスナップショットに無いため、必要な id 集合は
 * ここで解決してクエリ引数として渡す。
 *
 * ## 「スナップショット添字」で割られたタイの注意
 * コアは並びのタイ (同数・同日) をスナップショット添字で割る。添字はコアが songs を
 * ORDER BY 無しで読んだ順、すなわちローカル DB の rowid 順である。ここに 2 つ罠がある。
 *
 * 1. **iOS と同じ並びにはならない。** iOS は同梱 master.sqlite を読むが、Android の
 *    master.sqlite は Room が空で生成し CloudKit 同期が埋める (AppDatabase.buildDatabase)。
 *    Android の rowid は「同期で届いた順」で、iOS 同梱ファイルの rowid とは別データ。
 * 2. **同じ端末でも動く。** 差分同期の upsert は INSERT OR REPLACE (SyncDao.upsertSongs) で、
 *    songs は TEXT 主キーの rowid テーブル (Song) なので、更新された曲は行が消えて末尾に
 *    入り直し rowid が変わる = 添字も変わる。
 *
 * よって添字で割られたタイの前後は端末ごと・同期ごとに入れ替わり得る。UI がタイの
 * 前後関係に意味を持たせないこと。安定させたい並びが出てきたら、プラットフォーム側で
 * 並べ直すのではなくコア側の最終キーを id 等の不変値にすること
 * (打ち切り (limit) より後ろでは並べ直しても落ちた行を取り戻せないため)。
 */
class SongRepository(
    private val db: AppDatabase,
    // null = スナップショット経路なし (テスト等)。その場合は常に SQL 経路。
    private val snapshots: SnapshotStoreProvider? = null
) {

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

        fetchSongsViaSnapshot(filter, sortOrder, ascending, tagFilterSongIds)?.let { return it }

        // ---- 以下フォールバック (従来の SQL 経路) ----

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

        if (filter.brandIds.isNotEmpty()) {
            conditions.add("s.brand_id IN (${filter.brandIds.joinToString(",") { "?" }})")
            args.addAll(filter.brandIds)
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
        if (!filter.seriesGroup.isNullOrEmpty()) {
            // シリーズはピッカーで既存値から選ぶので完全一致 (部分一致にすると
            // "BRILLI@NT WING" が "BRILLI@NT WING SP" まで拾ってしまう)。コア側も同じ規約。
            conditions.add("s.series_group = ?")
            args.add(filter.seriesGroup)
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
                // 並び替えの母集合はバッジ用 (現地参加 + リアルライブ限定) ではなく、
                // iOS attendedSongCountMap と同じ「参加種別・イベント kind 無制限」。
                // スナップショット経路 (songList へ全 attended id を渡す) と揃えないと、
                // 配信参加マークを持つユーザーだけフォールバック時に順位が変わる。
                val countMap = db.songDao().fetchAttendedSongCounts().associate { it.songId to it.cnt }
                results = if (asc) results.sortedBy { countMap[it.song.id] ?: 0 }
                else results.sortedByDescending { countMap[it.song.id] ?: 0 }
            }
            SongSortOrder.COLLECTED_RATE -> {
                // COLLECTED_COUNT と同じ理由で無制限の attended 回数を使う (分母は全披露回数)。
                val attendedMap = db.songDao().fetchAttendedSongCounts().associate { it.songId to it.cnt }
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

    /**
     * fetchSongs のスナップショット経路。絞り込み + 整列はコアが行い、表示順の song_id
     * 列だけが返るので、Room で Song 実体へ引き直す。使えないときは null (SQL へ)。
     */
    private suspend fun fetchSongsViaSnapshot(
        filter: SongSearchFilter,
        sortOrder: SongSortOrder,
        ascending: Boolean?,
        tagFilterSongIds: Set<String>?
    ): List<SongWithArtists>? {
        val provider = snapshots ?: return null
        // 回収数系ソートの入力: 参加マーク (user_marks) はスナップショットに無いので
        // ここで解決して渡す。バッジ (fetchSongCollectedCounts) と違い参加種別・イベント
        // kind を絞らずに全 attended を渡すのはコア側規約 (iOS attendedSongCountMap の
        // 忠実な再現。SQL フォールバック側も fetchAttendedSongCounts で同じ母集合に揃えてある)。
        val needsAttended =
            sortOrder == SongSortOrder.COLLECTED_COUNT || sortOrder == SongSortOrder.COLLECTED_RATE
        val attendedShowIds =
            if (needsAttended) db.userMarkDao().idsFor("show", "attended") else emptyList()
        val attendedEventIds =
            if (needsAttended) db.userMarkDao().idsFor("event", "attended") else emptyList()
        val ids = provider.query { store ->
            store.songList(
                filter.toSnapshotFilter(),
                sortOrder.toSnapshotSort(),
                ascending,
                attendedShowIds,
                attendedEventIds
            )
        } ?: return null
        // タグ絞り込みは SQL 時代の `s.id IN (...)` と同じく通過フィルタ (並びはコアの表示順が正)。
        val visibleIds = if (tagFilterSongIds != null) ids.filter { it in tagFilterSongIds } else ids
        return fetchSongsPreservingOrder(visibleIds).map { song ->
            SongWithArtists(song = song, artistNames = song.singerLabel ?: "")
        }
    }

    /** song_id → 現地回収回数 (行アイコン/回収済みフィルタ用の bulk 取得)。 */
    suspend fun fetchSongCollectedCounts(): Map<String, Int> {
        if (snapshots != null) {
            // バッジは「現地参加 (text_value NULL/'live') の show + 参加イベント配下の show」を
            // リアルライブ (event.kind=live/festival) 限定で数える — SQL 版と同一条件。
            // 参加マークの解決はプラットフォーム側、集計はコア側という分担。
            val attendedShowIds = db.songDao().fetchAttendedLiveShowIds()
            val attendedEventIds = db.userMarkDao().idsFor("event", "attended")
            snapshots.query { store ->
                store.songCollectedCountMap(attendedShowIds, attendedEventIds, true)
                    .mapValues { (_, count) -> count.toInt() }
            }?.let { return it }
        }
        return db.songDao().fetchSongCollectedCounts().associate { it.songId to it.cnt }
    }

    /** 指定アイドルのいずれかが歌唱者にいる song_id 集合 (担当マーク由来の「担当」表示/絞り込み用)。 */
    suspend fun fetchSongIdsWithAnyArtist(idolIds: Collection<String>): Set<String> {
        if (idolIds.isEmpty()) return emptySet()
        snapshots?.query { store ->
            // 専用 API は無いが、songList の idol_ids 絞り込み (role='original' 限定) が
            // SQL の `SELECT DISTINCT song_id FROM song_artists WHERE role='original' ...` と
            // 同値になる。SQL 版は他の条件を一切持たないので、リミックス・other ブランド・
            // ライブ履歴のみの曲も落とさないようフラグを全開にする。
            store.songList(
                snapshotSongFilter(
                    idolIds = idolIds.toList(),
                    includeRemixes = true,
                    includeOtherBrand = true,
                    excludeLiveOnly = false
                ),
                SongListSort.TITLE_KANA,
                null,
                emptyList(),
                emptyList()
            ).toSet()
        }?.let { return it }
        return db.songDao().fetchSongIdsWithAnyArtist(idolIds.toList()).toSet()
    }

    // Song 実体の単発/一括取得はスナップショットの hydration 先 (プラットフォーム側の
    // 実体化はローカル store で行う規約) なので、Room 直のまま残す。
    suspend fun fetchSong(id: String): Song? {
        return db.songDao().fetchSong(id)
    }

    /**
     * あいまい一致で拾った song_id (「もしかして」の素)。並びはコアが返した順
     * (部分一致 → 編集距離が小さい順) が正で、呼び出し側で並べ直さないこと。
     *
     * SQL の `LIKE '%語%'` は打ち間違い・かな入力・音引きの揺れで 0 件になる。そこを
     * コア (imas-core `domain/fuzzy_search.rs`) の編集距離で補う。曲名だけでなく
     * `songs.title_kana` の読みも綴りとして渡すので「おねがいしんでれら」で
     * 「お願い！シンデレラ」が当たる。
     *
     * 実体ではなく id を返すのは、呼び出し側 (曲一覧 / 横断検索) が自分の絞り込みと
     * 上限で引き直す必要があるため。あいまい一致は綴りしか見ないので、ブランドや
     * 曲種の条件はここでは効かない。
     *
     * @param shownIds 既に画面に出ている曲。ここから重複を出さない。
     */
    suspend fun fuzzySongIds(
        needle: String,
        shownIds: Set<String>,
        limit: Int = FuzzySearch.LIMIT
    ): List<String> {
        if (needle.isBlank() || limit <= 0) return emptyList()
        // スナップショットには綴りだけを返す API が無いので Room 直で引く
        // (全件読まずに済むよう 2 列だけの射影)。
        val spellings = db.searchDao().fetchSongSpellings()
        if (spellings.isEmpty()) return emptyList()
        val shownIndices = spellings.indices.filterTo(HashSet()) { spellings[it].id in shownIds }
        // 全曲ぶんの編集距離は 3,000 曲で 20ms 前後。呼び出し元が Main なのでここで外へ出す。
        val extras = withContext(Dispatchers.Default) {
            FuzzySearch.extraIndices(spellings.map { it.spellings }, needle, shownIndices, limit)
        }
        return extras.map { spellings[it].id }
    }

    /** タグ詳細画面の曲ランキング表示用。N+1を避けてIN句で一括取得する。 */
    suspend fun fetchSongsByIds(ids: List<String>): List<Song> {
        if (ids.isEmpty()) return emptyList()
        return db.songDao().fetchSongsByIds(ids)
    }

    suspend fun fetchSongArtists(songId: String, role: String? = null): List<Idol> {
        // コアは idol id 列 (sort_order 順) を返す。role=null の重複 (original と performer の
        // 両ロール保持) も SQL の JOIN と同じく行ごとに残る。
        snapshots?.query { it.songArtistIds(songId, role) }
            ?.let { return fetchIdolsPreservingOrder(it) }
        return if (role != null) {
            db.songDao().fetchSongArtistsByRole(songId, role)
        } else {
            db.songDao().fetchSongArtists(songId)
        }
    }

    suspend fun fetchSongPerformanceHistory(songId: String): List<PerformanceHistoryRow> {
        snapshots?.query { store ->
            store.songPerformanceHistory(songId).map { it.toRow() }
        }?.let { return it }
        return db.songDao().fetchSongPerformanceHistory(songId)
    }

    /**
     * 披露回数ランキング (iOS CoreStatsRepository.songPlayCountRanking と同一経路)。
     *
     * 集計・並び・件数打ち切りはすべてコアの責務。射影 (SongPlayCountRecord) が
     * title/brand_id を持つため Room への引き直しはしない。
     *
     * 同数タイの並びは iOS と一致しない — クラス KDoc の「スナップショット添字」の注意どおり、
     * 両プラットフォームとも添字を最終キーにするが、その添字の元になる rowid が別データだから。
     * 移送前の Kotlin 実装 (songPerformanceCountMap を取って `thenBy { song_id }` で整列) と
     * SQL フォールバック (GROUP BY が主キー索引を走るため実測ではタイが song_id 昇順) は
     * どちらもタイが安定していたので、そこは失っている。
     * 順位の値そのものは変わらないので許容するが、同数が limit の境目にまたがると
     * 20 位に載る曲自体が入れ替わる (実データでは 36 回タイの いっぱいいっぱい /
     * M@STERPIECE / GOIN'!!! がちょうど limit=20 の境界にいる)。
     */
    suspend fun fetchSongPlayCountRanking(limit: Int = 20): List<SongPlayCount> {
        snapshots?.query { store ->
            store.songPlayCountRanking(limit.coerceAtLeast(0).toUInt()).map {
                SongPlayCount(
                    id = it.id,
                    title = it.title,
                    playCount = it.playCount.toInt(),
                    brandId = it.brandId
                )
            }
        }?.let { return it }
        return db.songDao().fetchSongPlayCountRanking(limit)
    }

    // ---- 絞り込み一覧 (FilteredSongs) の母集団 ----
    //
    // iOS の `fetchSongs(criterion:)` を分解したもの。ブランド / 曲タイプは通常の一覧クエリ
    // (fetchSongs(filter:)) に合流するので、ここには専用クエリを持つ 3 種 + クリエイターだけ置く。

    /** CDシリーズ (完全一致) の楽曲。並びは release_date, title_kana。 */
    suspend fun fetchSongsByCdSeries(series: String): List<SongWithArtists> {
        snapshots?.query { it.songsByCdSeries(series) }
            ?.let { return fetchSongsPreservingOrder(it).withArtists() }
        return db.songDao().fetchSongsByCdSeries(series).withArtists()
    }

    /** シリーズ (series_group 完全一致) の楽曲。 */
    suspend fun fetchSongsBySeriesGroup(name: String): List<SongWithArtists> {
        snapshots?.query { it.songsBySeriesGroup(name) }
            ?.let { return fetchSongsPreservingOrder(it).withArtists() }
        return db.songDao().fetchSongsBySeriesGroupOrdered(name).withArtists()
    }

    /** リリース年 ("YYYY" 前方一致) の楽曲。 */
    suspend fun fetchSongsByReleaseYear(year: String): List<SongWithArtists> {
        snapshots?.query { it.songsByReleaseYear(year) }
            ?.let { return fetchSongsPreservingOrder(it).withArtists() }
        return db.songDao().fetchSongsByReleaseYear("${year.likeEscaped()}%").withArtists()
    }

    /**
     * クリエイター名 (作詞・作曲・編曲 横断) で引いた楽曲と、その曲での役割。
     *
     * **コアに対応 API が無い唯一の絞り込み**なので、スナップショットの有無にかかわらず Room 経路。
     *
     * 2 段構えなのは 3 欄が「/」「、」等で複数名を詰めた自由文字列だから。SQL の部分一致だけだと
     * 「山田」で「山田太郎」の曲まで当たるので、候補を絞ったあとに欄を人ごとへ割って
     * **完全一致した欄だけ**を役割として採り、1 つも一致しない曲は落とす
     * (iOS songsWithCreatorRoles と同じ)。欄の割り方はコア (splitCreditNames) が唯一の正 —
     * ここで区切り文字を書き直すと、曲詳細のクレジット表示と同じ人が二通りに分かれる。
     */
    suspend fun fetchSongsByCreator(name: String): List<SongWithRoles> {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return emptyList()
        val candidates = db.songDao().fetchSongsByCreator("%${trimmed.likeEscaped()}%")
        return candidates.mapNotNull { song ->
            // 並びは iOS の rolesLabel と同じ 作曲 → 作詞 → 編曲。
            val roles = listOf("作曲" to song.composer, "作詞" to song.lyricist, "編曲" to song.arranger)
                .mapNotNull { (label, field) ->
                    label.takeIf { field != null && trimmed in splitCreditNames(field) }
                }
            if (roles.isEmpty()) null else SongWithRoles(song = song, roles = roles)
        }
    }

    suspend fun fetchCdSeriesList(): List<String> {
        snapshots?.query { store ->
            // albumSummaries は MIN(release_date) 降順で返るので、SQL 時代の
            // `ORDER BY cd_series` (BINARY 照合 = UTF-8 バイト列昇順) に並べ直す。
            // String.compareTo (UTF-16 コード単位) とはサロゲート域で順序が食い違うため、
            // バイト列比較で SQL と厳密に一致させる。
            store.albumSummaries(emptyList(), null)
                .map { it.cdSeries }
                .sortedWith(SQLITE_BINARY_ORDER)
        }?.let { return it }
        return db.songDao().fetchCdSeriesList()
    }

    /**
     * 上位シリーズ (series_group) の一覧。フィルタシートのピッカー候補。
     *
     * コアの seriesSummaries は MIN(release_date) 降順で返るので、cd_series 一覧と同じく
     * SQL の `ORDER BY` (BINARY 照合 = UTF-8 バイト列昇順) に並べ直す。
     */
    suspend fun fetchSeriesGroupList(): List<String> {
        snapshots?.query { store ->
            store.seriesSummaries(emptyList(), null)
                .map { it.name }
                .sortedWith(SQLITE_BINARY_ORDER)
        }?.let { return it }
        // SongDao に series_group の DISTINCT 口が無いので、フォールバックでは
        // 生クエリで曲を引いてから Kotlin 側で畳む (コアが使えない時だけ通る道)。
        return db.songDao()
            .fetchSongsRaw(
                SimpleSQLiteQuery("SELECT * FROM songs WHERE series_group IS NOT NULL AND series_group <> ''")
            )
            .mapNotNull { it.seriesGroup }
            .distinct()
            .sortedWith(SQLITE_BINARY_ORDER)
    }

    /**
     * CD シリーズ単位の集計 (曲一覧の「アルバム」表示)。
     * 集計はコアの責務なので、スナップショットが無い時は空 (グリッド自体を出さない)。
     */
    suspend fun fetchAlbumSummaries(brandIds: Set<String>, query: String?): List<AlbumSummary> =
        snapshots?.query { store ->
            store.albumSummaries(brandIds.toList(), query?.takeIf { it.isNotBlank() }).map {
                AlbumSummary(
                    cdSeries = it.cdSeries,
                    artworkUrl = it.artworkUrl,
                    songCount = it.songCount.toInt(),
                    earliestDate = it.earliestDate,
                    latestDate = it.latestDate,
                    brandIds = it.brandIds
                )
            }
        } ?: emptyList()

    /** 上位シリーズ (series_group) 単位の集計 (曲一覧の「シリーズ」表示)。 */
    suspend fun fetchSeriesSummaries(brandIds: Set<String>, query: String?): List<SeriesSummary> =
        snapshots?.query { store ->
            store.seriesSummaries(brandIds.toList(), query?.takeIf { it.isNotBlank() }).map {
                SeriesSummary(
                    name = it.name,
                    songCount = it.songCount.toInt(),
                    cdCount = it.cdCount.toInt(),
                    earliestDate = it.earliestDate,
                    latestDate = it.latestDate,
                    artworkUrl = it.artworkUrl,
                    brandIds = it.brandIds
                )
            }
        } ?: emptyList()

    /**
     * 同じ絞り込みで何件当たるかだけを返す (検索スコープ切替バーの件数)。
     *
     * 実体化 (hydration) を通さないのが要点。表示しない件数のために Room から Song を
     * 引き直すと、打鍵のたびに表示中スコープと同じコストを 2 回余計に払うことになる。
     * コアが返すのは表示順の id 列なので、その長さを数えれば済む。
     */
    suspend fun countSongs(
        filter: SongSearchFilter = SongSearchFilter(),
        tagFilterSongIds: Set<String>? = null
    ): Int {
        if (tagFilterSongIds != null && tagFilterSongIds.isEmpty()) return 0
        val provider = snapshots
        if (provider != null) {
            val ids = provider.query { store ->
                store.songList(filter.toSnapshotFilter(), SongListSort.TITLE_KANA, null, emptyList(), emptyList())
            }
            if (ids != null) {
                return if (tagFilterSongIds != null) ids.count { it in tagFilterSongIds } else ids.size
            }
        }
        // コアが使えない環境では素直に引いて数える (件数バーは出るが 1 回ぶん重い)。
        return fetchSongs(filter, SongSortOrder.TITLE_KANA, null, tagFilterSongIds).size
    }

    // イベント名一覧はイベントスライス (Phase 2 対象外)。スナップショット API が
    // 生えるまで SQL 経路のまま。
    suspend fun fetchEventNames(): List<String> {
        return db.songDao().fetchEventNames()
    }

    /**
     * ユニットの持ち曲一覧 (iOS CoreUnitRepository.unitSongs と同一経路)。
     *
     * コアは release_date 昇順 (NULL 先頭 = SQLite ASC)、同日はスナップショット添字順の
     * song_id 列を返す。同日タイの前後はクラス KDoc の注意どおり端末ごと・同期ごとに動き得る
     * (SQL の `ORDER BY release_date` も同日は未規定だったので、どちらの経路でも未規定のまま)。
     */
    suspend fun fetchUnitSongs(unitId: String): List<Song> {
        snapshots?.query { it.unitSongIds(unitId) }
            ?.let { return fetchSongsPreservingOrder(it) }
        return db.songDao().fetchUnitSongs(unitId)
    }

    suspend fun fetchCollectedShows(songId: String): List<PerformanceHistoryRow> {
        if (snapshots != null) {
            // 回収済み判定 (user_marks) はプラットフォームが正。全披露履歴をコアから取り、
            // 参加 show / 参加イベント配下の公演だけ残す (SQL 版の WHERE と同値)。
            // バッジと違い参加種別 (text_value) を絞らないのも SQL 版の忠実な再現。
            val attendedShows = db.userMarkDao().idsFor("show", "attended").toSet()
            val attendedEvents = db.userMarkDao().idsFor("event", "attended").toSet()
            snapshots.query { store ->
                store.songPerformanceHistory(songId)
                    .filter { it.showId in attendedShows || it.eventId in attendedEvents }
                    .map { it.toRow() }
            }?.let { return it }
        }
        return db.songDao().fetchCollectedShows(songId)
    }

    /**
     * 関連楽曲 (同じシリーズ/ユニット/原唱アイドルでつながる曲)。iOS fetchRelatedSongs と同じ重み付け
     * (シリーズ=3, ユニット=2, 原唱共有=1) で足し合わせ、スコア降順→リリース日降順で並べる。
     *
     * 複合クエリで専用のスナップショット API がまだ無く、部分的に移すと FFI の
     * 「1 ユーザー操作 = 1 呼び出し」規約に反する分割呼び出しになるため、
     * 専用 API がコアに生えるまで SQL 経路のまま。
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
        // idolSongRecords は一覧射影 (IdolSongRecord) を返すが、この口の戻り値は Song 実体
        // なので id 列だけ使って Room で引き直す。並び (release_date DESC) と重複
        // (role=null 時に両ロール保持曲が 2 行) はコアの返した id 列がそのまま正。
        snapshots?.query { store -> store.idolSongRecords(idolId, role).map { it.songId } }
            ?.let { return fetchSongsPreservingOrder(it) }
        return if (role != null) {
            db.songDao().fetchIdolSongsByRole(idolId, role)
        } else {
            db.songDao().fetchIdolSongs(idolId)
        }
    }

    /** ソロ曲クイズ用: ソロ曲と原唱アイドルの対応行 (song_id, idol_id)。 */
    suspend fun fetchSoloOriginalSingers(): List<SoloOriginalSingerRow> {
        snapshots?.query { store ->
            // ソロ曲集合 → 原唱者マップの 2 段引き。songList (song_type='solo', リミックス除外) と
            // songPerformerIdolIdsMap (role='original' のみ) の組で SQL の JOIN と同値。
            // SQL 版はブランド・ライブ履歴のみ曲を絞らないのでフラグを全開にする。
            val soloIds = store.songList(
                snapshotSongFilter(
                    songType = "solo",
                    includeRemixes = false,
                    includeOtherBrand = true,
                    excludeLiveOnly = false
                ),
                SongListSort.TITLE_KANA,
                null,
                emptyList(),
                emptyList()
            )
            val singersBySong = store.songPerformerIdolIdsMap(soloIds)
            soloIds.flatMap { songId ->
                (singersBySong[songId] ?: emptyList()).map { SoloOriginalSingerRow(songId, it) }
            }
        }?.let { return it }
        return db.songDao().fetchSoloOriginalSingers()
    }

    /**
     * イントロドン出題プール。Android には Apple Music フル再生の手段が無いため、
     * iOS の `apple_music_id` 条件ではなく実際に再生できる `preview_url` の有無で絞り込む。
     * (Android 固有条件 + RANDOM() のためスナップショット化しない)
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

    // ---- スナップショット経路のヘルパ ----

    /**
     * コアが返した表示順の song_id 列を Song 実体へ引き直す。
     * 並びと重複は id 列が正 (Room の IN 句は順序を保証しないため並べ直す)。
     * SQLite のバインド変数上限 (999) を跨がないよう分割して引く。
     */
    private suspend fun fetchSongsPreservingOrder(ids: List<String>): List<Song> =
        hydrateInOrder(ids, Song::id) { db.songDao().fetchSongsByIds(it) }

    /**
     * 一覧行が要る歌唱者名を曲から埋める (iOS songsWithArtists と同じ)。
     * song_artists は引かない — 一覧で N+1 になる上、行に出すのは `singerLabel` だけだから。
     */
    private fun List<Song>.withArtists(): List<SongWithArtists> =
        map { SongWithArtists(song = it, artistNames = it.singerLabel ?: "") }

    /** fetchSongsPreservingOrder の Idol 版 (歌唱者一覧の hydration)。 */
    private suspend fun fetchIdolsPreservingOrder(ids: List<String>): List<Idol> =
        hydrateInOrder(ids, Idol::id) { db.songDao().fetchIdolsByIds(it) }

    private fun SongSearchFilter.toSnapshotFilter(): SongListFilter = snapshotSongFilter(
        brandIds = brandIds.toList(),
        title = title,
        idolName = idolName,
        idolIds = idolIds ?: emptyList(),
        songwriter = songwriter,
        cdSeries = cdSeries,
        seriesGroup = seriesGroup,
        liveName = liveName,
        songType = songType,
        includeRemixes = includeRemixes,
        includeOtherBrand = includeOtherBrand,
        excludeLiveOnly = excludeLiveOnly
    )

    private fun SongSortOrder.toSnapshotSort(): SongListSort = when (this) {
        SongSortOrder.TITLE_KANA -> SongListSort.TITLE_KANA
        SongSortOrder.RELEASE_DATE -> SongListSort.RELEASE_DATE
        SongSortOrder.PERFORMANCE_COUNT -> SongListSort.PERFORMANCE_COUNT
        SongSortOrder.COLLECTED_COUNT -> SongListSort.COLLECTED_COUNT
        SongSortOrder.COLLECTED_RATE -> SongListSort.COLLECTED_RATE
    }

    private fun PerformanceHistoryEntry.toRow(): PerformanceHistoryRow = PerformanceHistoryRow(
        showId = showId,
        eventId = eventId,
        eventName = eventName,
        showName = showName,
        date = date,
        venue = venue,
        position = position.toInt(),
        section = section
    )

    companion object {
        /**
         * uniffi の Record にはデフォルト引数が生成されないため、Kotlin 側の既定値を
         * ここで一元化する (SQL 版の「条件なし」に対応する値)。
         */
        private fun snapshotSongFilter(
            brandIds: List<String> = emptyList(),
            title: String? = null,
            idolName: String? = null,
            idolIds: List<String> = emptyList(),
            songwriter: String? = null,
            cdSeries: String? = null,
            seriesGroup: String? = null,
            liveName: String? = null,
            songType: String? = null,
            includeRemixes: Boolean = false,
            includeOtherBrand: Boolean = true,
            excludeLiveOnly: Boolean = false
        ): SongListFilter = SongListFilter(
            brandIds = brandIds,
            title = title,
            idolName = idolName,
            idolIds = idolIds,
            songwriter = songwriter,
            cdSeries = cdSeries,
            seriesGroup = seriesGroup,
            liveName = liveName,
            songType = songType,
            includeRemixes = includeRemixes,
            includeOtherBrand = includeOtherBrand,
            excludeLiveOnly = excludeLiveOnly
        )
    }
}
