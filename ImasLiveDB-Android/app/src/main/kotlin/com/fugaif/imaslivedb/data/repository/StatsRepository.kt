package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.BrandCollectionProgress
import com.fugaif.imaslivedb.data.model.BrandSongCount
import com.fugaif.imaslivedb.data.model.BrandTotalRow
import com.fugaif.imaslivedb.data.model.CollectionDashboard
import com.fugaif.imaslivedb.data.model.DatabaseStats
import com.fugaif.imaslivedb.data.model.FavoriteRankingEntry
import com.fugaif.imaslivedb.data.model.UncollectedSong
import com.fugaif.imaslivedb.data.model.UpcomingCatchChance
import com.fugaif.imaslivedb.data.model.YearlyShowCount
import uniffi.imas_core.SongListFilter
import uniffi.imas_core.SongListSort

/**
 * 統計・回収ダッシュボードの読み取り口。
 *
 * カタログ側の集計 (ブランド別曲数・年別公演数・回収母集合) は共有コア (imas-core) の
 * スナップショットを第一経路にし、未ロード・利用不可のときだけ Room へ委譲する。
 * 参加マーク (user_marks) はスナップショットに含まれないので、解決済みの id 集合を
 * 呼び出し側 (UserMarkRepository) から受け取り、コアへは引数で渡す。
 */
class StatsRepository(
    private val db: AppDatabase,
    private val communityApi: CommunityApi,
    // null = スナップショット経路なし (テスト等)。その場合は常に SQL 経路。
    private val snapshots: SnapshotStoreProvider? = null
) {

    suspend fun fetchBrands(): List<Brand> {
        snapshots?.query { store -> store.brandRecords().map { it.toBrand() } }?.let { return it }
        return db.brandDao().fetchBrands()
    }

    suspend fun fetchBrandSongCounts(): List<BrandSongCount> {
        snapshots?.query { store ->
            store.brandSongCounts().map {
                BrandSongCount(id = it.id, shortName = it.shortName, color = it.color, songCount = it.songCount.toInt())
            }
        }?.let { return it }
        return db.brandDao().fetchBrandSongCounts()
    }

    /**
     * DB 統計 (行数)。コアは件数だけを返す API を持たず (SnapshotStats はロード時の戻り値で
     * 後から引けない)、Room 経路のまま。
     */
    suspend fun fetchDatabaseStats(): DatabaseStats {
        return DatabaseStats(
            songCount = db.statsDao().fetchSongCount(),
            idolCount = db.statsDao().fetchIdolCount(),
            eventCount = db.statsDao().fetchEventCount(),
            showCount = db.statsDao().fetchShowCount()
        )
    }

    suspend fun fetchYearlyShowCounts(): List<YearlyShowCount> {
        snapshots?.query { store ->
            store.yearlyShowCounts().map { YearlyShowCount(year = it.year, showCount = it.showCount.toInt()) }
        }?.let { return it }
        return db.statsDao().fetchYearlyShowCounts()
    }

    /**
     * meta の値 (schema_version / data_version)。設定画面が「いまローカル DB がどの版か」を
     * 見せる診断値なので、同期完了から reload 完了までひと世代古い値を返し得る
     * スナップショットではなく Room を直接読む (コアに metaValue はある)。
     */
    suspend fun fetchMetaValue(key: String): String? {
        return db.metaDao().fetchMetaValue(key)
    }

    // MARK: - 最新の動き

    /**
     * 「最新の動き」に出す最新公演のセトリ曲数。**Room 経路のまま残す。**
     *
     * コアの showSetlist は songs と解決できた項目だけを返す (song_id が孤児の
     * setlist_items を読み飛ばす) ので、その size は元 SQL の
     * `COUNT(*) FROM setlist_items WHERE show_id = ?` と母集合が一致しない。
     * 孤児行がある公演で曲数が静かに少なく出るため、件数だけはコアに寄せない。
     */
    suspend fun fetchLatestShowSongCount(showId: String): Int {
        return db.statsDao().fetchSetlistCount(showId)
    }

    // MARK: - Collection Dashboard (iOS StatsView.loadDashboard の移植)

    /**
     * 回収ダッシュボードの重い集計をまとめて実行する。
     * collectedIds / pickIdolIds は呼び出し側 (UserMarkRepository) から取得して渡す。
     */
    suspend fun fetchCollectionDashboard(collectedIds: Set<String>, pickIdolIds: Set<String>): CollectionDashboard {
        val branded = fetchBrandedSongIds()
        val brandProgress = fetchBrandCollectionProgress(collectedIds)
        val pickSongIds = fetchSongIdsWithAnyArtist(pickIdolIds)

        val pickUncollected = fetchUncollectedSongs(pickSongIds, collectedIds)
        val allUncollected = fetchUncollectedSongs(branded, collectedIds)

        val allUncollectedIds = allUncollected.map { it.song.id }.toSet()
        val chances = fetchUpcomingCatchChances(allUncollectedIds, today())

        val pickCollectedCount = pickSongIds.intersect(collectedIds).size
        return CollectionDashboard(
            overallCollected = branded.intersect(collectedIds).size,
            overallTotal = branded.size,
            brandProgress = brandProgress,
            pickUncollected = pickUncollected,
            allUncollected = allUncollected,
            myPickCollected = pickCollectedCount,
            myPickTotal = pickSongIds.size,
            catchChances = chances
        )
    }

    /** 回収率の母集合 (brand_id が設定されている曲)。 */
    private suspend fun fetchBrandedSongIds(): Set<String> {
        snapshots?.query { store -> store.brandedSongIds().toSet() }?.let { return it }
        return db.statsDao().fetchBrandedSongIds().toSet()
    }

    /** 担当アイドルのいずれかが原唱者 (role='original') の曲 id 集合。 */
    private suspend fun fetchSongIdsWithAnyArtist(idolIds: Set<String>): Set<String> {
        if (idolIds.isEmpty()) return emptySet()
        snapshots?.query { store ->
            // 専用 API は無いが、songList の idol_ids 絞り込み (role='original' 限定) が
            // SQL の `SELECT DISTINCT song_id FROM song_artists WHERE role='original' ...` と
            // 同値になる。SQL 版は他の条件を持たないので、リミックス・other ブランド・
            // ライブ履歴のみの曲を落とさないようフラグを全開にする
            // (uniffi の Record にデフォルト引数は生成されないので全項目を明示する)。
            store.songList(
                SongListFilter(
                    brandIds = emptyList(),
                    title = null,
                    idolName = null,
                    idolIds = idolIds.toList(),
                    songwriter = null,
                    cdSeries = null,
                    seriesGroup = null,
                    liveName = null,
                    songType = null,
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
        return db.statsDao().fetchSongIdsWithAnyArtist(idolIds.toList()).toSet()
    }

    /** ブランドごとの現地回収進捗 (回収済み曲数 / そのブランド全曲数)。 */
    private suspend fun fetchBrandCollectionProgress(collectedIds: Set<String>): List<BrandCollectionProgress> {
        val brandTotals = fetchBrandTotals()
        val collectedByBrand = collectedCountByBrand(collectedIds)
        return brandTotals.map { row ->
            BrandCollectionProgress(
                brandId = row.id,
                shortName = row.shortName,
                color = row.color,
                collected = collectedByBrand[row.id] ?: 0,
                total = row.total
            )
        }
    }

    /**
     * ブランド別の曲総数 (回収進捗の分母)。SQL では fetchBrandTotals と fetchBrandSongCounts が
     * 同一クエリなので、コア側は brandSongCounts が両方を担う (並びも sort_order で同じ)。
     */
    private suspend fun fetchBrandTotals(): List<BrandTotalRow> {
        snapshots?.query { store ->
            store.brandSongCounts().map {
                BrandTotalRow(id = it.id, shortName = it.shortName, color = it.color, total = it.songCount.toInt())
            }
        }?.let { return it }
        return db.statsDao().fetchBrandTotals()
    }

    /** 回収済み曲をブランド別に数える。曲 → brand_id の解決だけをコア/SQL に任せる。 */
    private suspend fun collectedCountByBrand(collectedIds: Set<String>): Map<String, Int> {
        if (collectedIds.isEmpty()) return emptyMap()
        val ids = collectedIds.toList()
        val brandIds = snapshots?.query { store -> store.songRecordsByIds(ids).mapNotNull { it.brandId } }
            ?: db.statsDao().fetchBrandIdsForSongs(ids)
        return brandIds.groupingBy { it }.eachCount()
    }

    /** 未回収曲一覧。candidateIds のうち collectedIds に無い曲を、披露回数つきで返す (披露回数の多い順)。 */
    private suspend fun fetchUncollectedSongs(candidateIds: Set<String>, collectedIds: Set<String>): List<UncollectedSong> {
        val targetIds = candidateIds - collectedIds
        if (targetIds.isEmpty()) return emptyList()
        val songs = db.songDao().fetchSongsByIds(targetIds.toList())
        // 披露回数はリアルライブ (event.kind live/festival) 限定。コアの songPerformanceCountMap は
        // kind を絞らない全公演の集計で母集合が違うため、ここは SQL 経路のまま。
        val playCounts = db.statsDao().fetchLifetimePlayCounts(targetIds.toList())
            .associate { it.songId to it.cnt }
        return songs
            .map { UncollectedSong(song = it, playCount = playCounts[it.id] ?: 0) }
            .sortedWith(compareByDescending<UncollectedSong> { it.playCount }.thenByDescending { it.song.titleKana ?: "" })
    }

    /**
     * 「この公演で未回収が聴けるかも」候補。今日以降の公演のうち、親ブランドが過去に未回収曲を披露した数が多い順。
     *
     * 未来公演の抽出も「未回収曲を披露したブランド」の逆引きも kind (live/festival) と
     * 日付で絞った集計で、対応するコア API が無いため SQL 経路のまま。
     */
    private suspend fun fetchUpcomingCatchChances(uncollectedIds: Set<String>, today: String, limit: Int = 8): List<UpcomingCatchChance> {
        if (uncollectedIds.isEmpty()) return emptyList()
        val statsDao = db.statsDao()
        val uncollectedByBrand = mutableMapOf<String, Int>()
        statsDao.fetchBrandSongHits(uncollectedIds.toList()).forEach { row ->
            val bid = row.brandId ?: return@forEach
            uncollectedByBrand[bid] = (uncollectedByBrand[bid] ?: 0) + 1
        }
        if (uncollectedByBrand.isEmpty()) return emptyList()

        return statsDao.fetchUpcomingRealLiveShows(today)
            .mapNotNull { row ->
                val likely = uncollectedByBrand[row.brandId] ?: return@mapNotNull null
                if (likely <= 0) return@mapNotNull null
                UpcomingCatchChance(
                    show = row.toShow(),
                    eventName = row.eventName,
                    brandId = row.brandId,
                    brandColor = row.brandColor,
                    likelyCount = likely
                )
            }
            .sortedWith(compareByDescending<UpcomingCatchChance> { it.likelyCount }.thenByDescending { it.show.date })
            .take(limit)
    }

    /** "yyyy-MM-dd" 形式の今日 (Asia/Tokyo)。公演日 (TEXT) との文字列比較に使う。 */
    private fun today(): String = JstDay.today()

    // MARK: - コミュニティの熱量 (お気に入りランキング)

    suspend fun fetchFavoritesRanking(brandId: String?, limit: Int = 20): List<FavoriteRankingEntry> {
        val dtos = communityApi.favoritesRanking()
        // 曲メタの引き当ては hydration (Room が正)。ランキング自体は端末外データなのでコア対象外。
        val songs = db.songDao().fetchSongsByIds(dtos.map { it.songId }).associateBy { it.id }
        return dtos
            .map { dto ->
                val song = songs[dto.songId]
                FavoriteRankingEntry(
                    songId = dto.songId,
                    count = dto.count,
                    title = song?.title ?: dto.songId,
                    brandId = song?.brandId,
                    artworkUrl = song?.artworkUrl
                )
            }
            .filter { brandId == null || it.brandId == brandId }
            .take(limit)
    }
}
