package com.fugaif.imaslivedb.data.repository

import androidx.sqlite.db.SimpleSQLiteQuery
import com.fugaif.imaslivedb.data.core.FuzzySearch
import com.fugaif.imaslivedb.data.core.SQLITE_BINARY_ORDER
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.core.hydrateInOrder
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.AlbumSummary
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.IdolSongSection
import com.fugaif.imaslivedb.data.model.PerformanceHistoryRow
import com.fugaif.imaslivedb.data.model.SeriesSummary
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SoloOriginalSingerRow
import com.fugaif.imaslivedb.data.model.SongPlayCount
import com.fugaif.imaslivedb.data.model.SongSearchFilter
import com.fugaif.imaslivedb.data.model.SongSortOrder
import com.fugaif.imaslivedb.data.model.SongWithArtists
import com.fugaif.imaslivedb.data.model.UserMark
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.IntroQuizPlayability
import uniffi.imas_core.KamisabiCompletion
import uniffi.imas_core.PerformanceHistoryEntry
import uniffi.imas_core.PickedSongRecord
import uniffi.imas_core.SongListFilter
import uniffi.imas_core.SongListSort
import uniffi.imas_core.introQuizPlayableIndices
import uniffi.imas_core.masterySongFilter
import uniffi.imas_core.ShowWithEventNameRecord

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
 * 楽曲の読み取り口。
 *
 * 読み取りは共有コア (imas-core) のインメモリスナップショットが答える (SQL の代わりの経路は
 * 持たない。iOS と同一ロジック・同一結果を返すため)。コアに対応する API が無いもの
 * (作家名での絞り込み・イントロドンの候補) だけ Room で引く。
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
    private val snapshots: SnapshotStoreProvider
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

        // 回収数系ソートの入力: 参加マーク (user_marks) はスナップショットに無いので
        // ここで解決して渡す。バッジ (fetchSongCollectedCounts) と違い参加種別・イベント
        // kind を絞らずに全 attended を渡すのはコア側規約 (iOS attendedSongCountMap の忠実な再現)。
        val needsAttended =
            sortOrder == SongSortOrder.COLLECTED_COUNT || sortOrder == SongSortOrder.COLLECTED_RATE
        val attendedShowIds =
            if (needsAttended) db.userMarkDao().idsFor("show", "attended") else emptyList()
        val attendedEventIds =
            if (needsAttended) db.userMarkDao().idsFor("event", "attended") else emptyList()
        val ids = snapshots.query { store ->
            store.songList(
                filter.toSnapshotFilter(),
                sortOrder.toSnapshotSort(),
                ascending,
                attendedShowIds,
                attendedEventIds
            )
        }
        // タグ絞り込みは通過フィルタ (並びはコアの表示順が正)。
        val visibleIds = if (tagFilterSongIds != null) ids.filter { it in tagFilterSongIds } else ids
        return fetchSongsPreservingOrder(visibleIds).withArtists()
    }

    /**
     * 習熟度の分母になる曲 (50 音順)。どの曲を数えるか (リミックス・別版・other ブランド・
     * ライブ履歴にしか無い曲を数えない) はコアの masterySongFilter が決める。
     */
    suspend fun fetchMasterySongs(): List<Song> {
        val ids = snapshots.query { store ->
            store.songList(masterySongFilter(), SongListSort.TITLE_KANA, null, emptyList(), emptyList())
        }
        return fetchSongsPreservingOrder(ids)
    }

    /**
     * 回収済みの曲 (一覧の回収バッジと同じ集合)。参加の条件 (設定「配信も回収に含める」) と
     * リアルライブに絞るのは [fetchSongCollectedCounts] と同じくコア。
     */
    suspend fun fetchCollectedSongIds(): Set<String> = fetchSongCollectedCounts().keys

    /** song_id → 現地回収回数 (行アイコン/回収済みフィルタ用の bulk 取得)。 */
    suspend fun fetchSongCollectedCounts(): Map<String, Int> {
        // バッジは「参加した show + 参加イベント配下の show」をリアルライブ
        // (event.kind=live/festival) 限定で数える — 集計はコア側 (songCollectedCountMap
        // 内の attended_real_live_shows)、参加マークの解決はプラットフォーム側という分担。
        //
        // show 側の「現地のみ / 配信も含める」の条件選びは CollectionAttendance (= コアの
        // collectionAttendedShows) に一本化してある。以前はここが SongDao.fetchAttendedLiveShowIds
        // という別 SQL (常に現地のみ固定で、設定「配信参加も回収に含める」を無視していた) を
        // 使っていて、セトリ側の回収表示と条件が食い違う元だった。
        // event 側は種別条件を掛けない (SQL 時代の fetchSongCollectedCountsQuery と同じ母集合)。
        val attendedShowIds = CollectionAttendance.showIds(db, CollectionPreferences.includeStream)
        val attendedEventIds = db.userMarkDao().idsFor(UserMark.EVENT, UserMark.ATTENDED)
        return snapshots.query { store ->
            store.songCollectedCountMap(attendedShowIds, attendedEventIds, true)
                .mapValues { (_, count) -> count.toInt() }
        }
    }

    /** 指定アイドルのいずれかが歌唱者にいる song_id 集合 (担当マーク由来の「担当」表示/絞り込み用)。 */
    suspend fun fetchSongIdsWithAnyArtist(idolIds: Collection<String>): Set<String> {
        if (idolIds.isEmpty()) return emptySet()
        return snapshots.query { store ->
            // 専用 API は無いが、songList の idol_ids 絞り込み (role='original' 限定) で引ける。
            // 他の条件は持たないので、リミックス・other ブランド・ライブ履歴のみの曲も
            // 落とさないようフラグを全開にする。
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
        }
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
        return fetchIdolsPreservingOrder(snapshots.query { it.songArtistIds(songId, role) })
    }

    suspend fun fetchSongPerformanceHistory(songId: String): List<PerformanceHistoryRow> =
        snapshots.query { store -> store.songPerformanceHistory(songId).map { it.toRow() } }

    /**
     * 披露回数ランキング (iOS CoreStatsRepository.songPlayCountRanking と同一経路)。
     *
     * 集計・並び・件数打ち切りはすべてコアの責務。射影 (SongPlayCountRecord) が
     * title/brand_id を持つため Room への引き直しはしない。
     *
     * 同数タイの並びは iOS と一致しない — クラス KDoc の「スナップショット添字」の注意どおり、
     * 両プラットフォームとも添字を最終キーにするが、その添字の元になる rowid が別データだから。
     * 移送前の Kotlin 実装 (songPerformanceCountMap を取って `thenBy { song_id }` で整列) は
     * タイが安定していたので、そこは失っている。
     * 順位の値そのものは変わらないので許容するが、同数が limit の境目にまたがると
     * 20 位に載る曲自体が入れ替わる (実データでは 36 回タイの いっぱいいっぱい /
     * M@STERPIECE / GOIN'!!! がちょうど limit=20 の境界にいる)。
     */
    suspend fun fetchSongPlayCountRanking(limit: Int = 20): List<SongPlayCount> =
        snapshots.query { store ->
            store.songPlayCountRanking(limit.coerceAtLeast(0).toUInt()).map {
                SongPlayCount(
                    id = it.id,
                    title = it.title,
                    playCount = it.playCount.toInt(),
                    brandId = it.brandId,
                    artworkUrl = it.artworkUrl
                )
            }
        }

    // ---- 絞り込み一覧 (FilteredSongs) の母集団 ----
    //
    // iOS の `fetchSongs(criterion:)` を分解したもの。ブランド / 曲タイプは通常の一覧クエリ
    // (fetchSongs(filter:)) に合流するので、ここには専用クエリを持つ 3 種 + クリエイターだけ置く。

    /** CDシリーズ (完全一致) の楽曲。並びは release_date, title_kana。 */
    suspend fun fetchSongsByCdSeries(series: String): List<SongWithArtists> =
        fetchSongsPreservingOrder(snapshots.query { it.songsByCdSeries(series) }).withArtists()

    /** シリーズ (series_group 完全一致) の楽曲。 */
    suspend fun fetchSongsBySeriesGroup(name: String): List<SongWithArtists> =
        fetchSongsPreservingOrder(snapshots.query { it.songsBySeriesGroup(name) }).withArtists()

    /** リリース年 ("YYYY" 前方一致) の楽曲。 */
    suspend fun fetchSongsByReleaseYear(year: String): List<SongWithArtists> =
        fetchSongsPreservingOrder(snapshots.query { it.songsByReleaseYear(year) }).withArtists()

    /**
     * この名前の作家の曲と、その人の役割 (作曲 → 作詞 → 編曲)。当たり方 (連名の割り方・所属の括弧や
     * 空白の揺れを畳んだ鍵での一致) はコアの songsByCreator が決める。実体は Room で id から引く。
     */
    suspend fun fetchSongsByCreator(name: String): List<SongWithRoles> {
        val records = snapshots.query { store -> store.songsByCreator(name) }
        val rolesById = records.associate { it.song.id to it.roles }
        return fetchSongsPreservingOrder(records.map { it.song.id })
            .map { song -> SongWithRoles(song = song, roles = rolesById[song.id].orEmpty()) }
    }

    /** CD シリーズの一覧 (フィルタシートのピッカー候補)。並びはコアの cdSeriesList が正。 */
    suspend fun fetchCdSeriesList(): List<String> =
        snapshots.query { store -> store.cdSeriesList() }

    /**
     * 上位シリーズ (series_group) の一覧。フィルタシートのピッカー候補。
     *
     * コアの seriesSummaries は MIN(release_date) 降順で返るので、cd_series 一覧と同じく
     * SQL の `ORDER BY` (BINARY 照合 = UTF-8 バイト列昇順) に並べ直す。
     */
    suspend fun fetchSeriesGroupList(): List<String> =
        snapshots.query { store ->
            store.seriesSummaries(emptyList(), null)
                .map { it.name }
                .sortedWith(SQLITE_BINARY_ORDER)
        }

    /**
     * CD シリーズ単位の集計 (曲一覧の「アルバム」表示)。集計はコアの責務。
     */
    suspend fun fetchAlbumSummaries(brandIds: Set<String>, query: String?): List<AlbumSummary> =
        snapshots.query { store ->
            store.albumSummaries(brandIds.toList(), query?.takeIf { it.isNotBlank() }).map {
                AlbumSummary(
                    cdSeries = it.cdSeries,
                    artworkUrl = it.artworkUrl,
                    songCount = it.songCount.toInt(),
                    earliestDate = it.earliestDate,
                    latestDate = it.latestDate,
                    brandIds = it.brandIds,
                    yearDisplay = it.yearDisplay
                )
            }
        }

    /** 上位シリーズ (series_group) 単位の集計 (曲一覧の「シリーズ」表示)。 */
    suspend fun fetchSeriesSummaries(brandIds: Set<String>, query: String?): List<SeriesSummary> =
        snapshots.query { store ->
            store.seriesSummaries(brandIds.toList(), query?.takeIf { it.isNotBlank() }).map {
                SeriesSummary(
                    name = it.name,
                    songCount = it.songCount.toInt(),
                    cdCount = it.cdCount.toInt(),
                    earliestDate = it.earliestDate,
                    latestDate = it.latestDate,
                    artworkUrl = it.artworkUrl,
                    brandIds = it.brandIds,
                    yearDisplay = it.yearDisplay
                )
            }
        }

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
        val ids = snapshots.query { store ->
            store.songList(filter.toSnapshotFilter(), SongListSort.TITLE_KANA, null, emptyList(), emptyList())
        }
        return if (tagFilterSongIds != null) ids.count { it in tagFilterSongIds } else ids.size
    }

    /** ライブ名の一覧 (曲の絞り込みの候補)。並びはコアの eventNames が正。 */
    suspend fun fetchEventNames(): List<String> =
        snapshots.query { store -> store.eventNames() }

    /**
     * ユニットの持ち曲一覧 (iOS CoreUnitRepository.unitSongs と同一経路)。
     *
     * コアは release_date 昇順 (NULL 先頭 = SQLite ASC)、同日はスナップショット添字順の
     * song_id 列を返す。同日タイの前後はクラス KDoc の注意どおり端末ごと・同期ごとに動き得る
     * (同日は未規定)。
     */
    suspend fun fetchUnitSongs(unitId: String): List<Song> =
        fetchSongsPreservingOrder(snapshots.query { it.unitSongIds(unitId) })

    /**
     * この曲を現地で回収した公演 (新しい順・同じ公演は 1 行)。参加マークは一覧の回収バッジと
     * 同じく回収に数える形態だけに絞って渡し (collectionAttendedShows)、リアルライブに
     * 絞るのと並べるのはコア (songCollectedShows)。
     */
    suspend fun fetchCollectedShows(songId: String): List<ShowWithEventNameRecord> {
        val includeStream = CollectionPreferences.includeStream
        val attendedShowIds = CollectionAttendance.showIds(db, includeStream)
        val attendedEventIds = CollectionAttendance.eventIds(db, includeStream)
        return snapshots.query { store -> store.songCollectedShows(songId, attendedShowIds, attendedEventIds) }
    }

    /**
     * 関連楽曲 (同じシリーズ/ユニット/原唱アイドルでつながる曲)。重み付け (シリーズ=3,
     * ユニット=2, 原唱共有=1) と並び (スコア降順 → リリース日降順、同点はコアの規則) は
     * コアの relatedSongs が持つ (iOS と同じ)。実体は Room で id から引く。
     */
    suspend fun fetchRelatedSongs(song: Song, limit: Int = 8): List<Song> =
        fetchSongsPreservingOrder(
            snapshots.query { store -> store.relatedSongs(song.id, limit.coerceAtLeast(0).toUInt()).map { it.id } }
        )

    suspend fun fetchIdolSongs(idolId: String, role: String? = null): List<Song> {
        // idolSongRecords は一覧射影 (IdolSongRecord) を返すが、この口の戻り値は Song 実体
        // なので id 列だけ使って Room で引き直す。並び (release_date DESC) と重複
        // (role=null 時に両ロール保持曲が 2 行) はコアの返した id 列がそのまま正。
        return fetchSongsPreservingOrder(
            snapshots.query { store -> store.idolSongRecords(idolId, role).map { it.songId } }
        )
    }

    /**
     * アイドルの原曲を「ソロ曲/ユニット曲/全体曲/カバー/その他」に節分けしたもの
     * (0 件の節は含まない)。アイドル詳細「楽曲（原曲）」用。節分け・見出し・節内の並びは
     * 共有コアが決める (idolOriginalSongSections。親曲持ちの派生曲の除外、カバーの独立節化も
     * コア側の規則)。節をまたいで 1 回だけ Room で実体化し (Song::id で分配)、節の数だけ
     * クエリを往復させない。
     */
    suspend fun fetchIdolOriginalSongSections(idolId: String): List<IdolSongSection> {
        val sections = snapshots.query { store -> store.idolOriginalSongSections(idolId) }
        val allIds = sections.flatMap { section -> section.songs.map { it.songId } }
        val songsById = fetchSongsPreservingOrder(allIds).associateBy { it.id }
        return sections.map { section ->
            IdolSongSection(
                heading = section.heading,
                shortHeading = section.shortHeading,
                songs = section.songs.mapNotNull { songsById[it.songId] }
            )
        }
    }

    /** ソロ曲クイズ用: ソロ曲と原唱アイドルの対応行 (song_id, idol_id)。 */
    suspend fun fetchSoloOriginalSingers(): List<SoloOriginalSingerRow> =
        snapshots.query { store ->
            // ソロ曲集合 → 原唱者マップの 2 段引き。songList (song_type='solo', リミックス除外) と
            // songPerformerIdolIdsMap (role='original' のみ) の組。ブランド・ライブ履歴のみの曲は
            // 絞らないのでフラグを全開にする。
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
        }

    /**
     * KAMISABI (音楽カードゲーム) の所持コンプ。**分母の規則はコア一本**
     * (`domain::kamisabi_cards::completion`) — KAMISABI はブランドごとの別商品
     * (ML 50 / SideM 50 / シャニ 50) なので、`brandId` を渡すとその商品の分母、
     * `null` なら全商品の合算になる。ここでは規則を持たず、コアの返り値をそのまま返す。
     */
    suspend fun fetchKamisabiCompletion(brandId: String?, ownedSongIds: List<String>): KamisabiCompletion =
        snapshots.query { store -> store.kamisabiCompletion(brandId, ownedSongIds) }

    /**
     * 編集で曲を 1 つ選ぶピッカーの母集団。絞り込みは一切しない (派生曲・その他ブランドも
     * 含む。編集ではどの曲でも選べる必要がある)。並びは title のバイト列順 (コアの
     * `allSongsForPicker`。iOS の SongPickerView と同じ)。
     */
    suspend fun fetchSongsForPicker(): List<PickedSongRecord> =
        snapshots.query { store -> store.allSongsForPicker() }

    /**
     * イントロドン出題プール (並びは無作為)。[brandIds] が空なら全ブランド。
     *
     * 出題できるかの規則はコア (`introQuizPlayableIndices`) が持つ (iOS と同じ規則)。
     * Android には Apple Music のフル再生の手段が無いので、常に「契約なし」
     * (= preview_url が唯一の音源) として渡す。
     */
    suspend fun fetchIntroDonSongs(brandIds: Set<String> = emptySet()): List<Song> {
        var sql = "SELECT * FROM songs"
        if (brandIds.isNotEmpty()) sql += " WHERE brand_id IN (${brandIds.joinToString(",") { "?" }})"
        val candidates = db.songDao().fetchSongsRaw(SimpleSQLiteQuery(sql, brandIds.toTypedArray()))
        val playable = introQuizPlayableIndices(
            candidates.map { IntroQuizPlayability(it.appleMusicId, it.previewUrl, it.parentSongId) },
            hasAppleMusicSubscription = false
        )
        return playable.map { candidates[it.toInt()] }.shuffled()
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
        excludeLiveOnly = excludeLiveOnly,
        kamisabiOnly = kamisabiOnly
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
            excludeLiveOnly: Boolean = false,
            kamisabiOnly: Boolean = false
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
            excludeLiveOnly = excludeLiveOnly,
            kamisabiOnly = kamisabiOnly
        )
    }
}
