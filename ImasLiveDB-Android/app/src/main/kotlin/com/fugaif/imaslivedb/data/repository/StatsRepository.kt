package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.BrandCollectionProgress
import com.fugaif.imaslivedb.data.model.BrandSongCount
import com.fugaif.imaslivedb.data.model.CollectionDashboard
import com.fugaif.imaslivedb.data.model.DatabaseStats
import com.fugaif.imaslivedb.data.model.FavoriteRankingEntry
import com.fugaif.imaslivedb.data.model.UncollectedSong
import com.fugaif.imaslivedb.data.model.UpcomingCatchChance
import com.fugaif.imaslivedb.data.model.YearlyShowCount

class StatsRepository(private val db: AppDatabase, private val communityApi: CommunityApi) {

    suspend fun fetchBrands(): List<Brand> {
        return db.brandDao().fetchBrands()
    }

    suspend fun fetchBrandSongCounts(): List<BrandSongCount> {
        return db.brandDao().fetchBrandSongCounts()
    }

    suspend fun fetchDatabaseStats(): DatabaseStats {
        return DatabaseStats(
            songCount = db.statsDao().fetchSongCount(),
            idolCount = db.statsDao().fetchIdolCount(),
            eventCount = db.statsDao().fetchEventCount(),
            showCount = db.statsDao().fetchShowCount()
        )
    }

    suspend fun fetchYearlyShowCounts(): List<YearlyShowCount> {
        return db.statsDao().fetchYearlyShowCounts()
    }

    suspend fun fetchMetaValue(key: String): String? {
        return db.metaDao().fetchMetaValue(key)
    }

    // MARK: - 最新の動き

    suspend fun fetchLatestShowSongCount(showId: String): Int = db.statsDao().fetchSetlistCount(showId)

    // MARK: - Collection Dashboard (iOS StatsView.loadDashboard の移植)

    /**
     * 回収ダッシュボードの重い集計をまとめて実行する。
     * collectedIds / pickIdolIds は呼び出し側 (UserMarkRepository) から取得して渡す。
     */
    suspend fun fetchCollectionDashboard(collectedIds: Set<String>, pickIdolIds: Set<String>): CollectionDashboard {
        val statsDao = db.statsDao()
        val branded = statsDao.fetchBrandedSongIds().toSet()
        val brandProgress = fetchBrandCollectionProgress(collectedIds)
        val pickSongIds = if (pickIdolIds.isEmpty()) emptySet() else statsDao.fetchSongIdsWithAnyArtist(pickIdolIds.toList()).toSet()

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

    /** ブランドごとの現地回収進捗 (回収済み曲数 / そのブランド全曲数)。 */
    private suspend fun fetchBrandCollectionProgress(collectedIds: Set<String>): List<BrandCollectionProgress> {
        val statsDao = db.statsDao()
        val brandTotals = statsDao.fetchBrandTotals()
        val collectedByBrand = mutableMapOf<String, Int>()
        if (collectedIds.isNotEmpty()) {
            statsDao.fetchBrandIdsForSongs(collectedIds.toList()).forEach { bid ->
                collectedByBrand[bid] = (collectedByBrand[bid] ?: 0) + 1
            }
        }
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

    /** 未回収曲一覧。candidateIds のうち collectedIds に無い曲を、披露回数つきで返す (披露回数の多い順)。 */
    private suspend fun fetchUncollectedSongs(candidateIds: Set<String>, collectedIds: Set<String>): List<UncollectedSong> {
        val targetIds = candidateIds - collectedIds
        if (targetIds.isEmpty()) return emptyList()
        val songs = db.songDao().fetchSongsByIds(targetIds.toList())
        val playCounts = db.statsDao().fetchLifetimePlayCounts(targetIds.toList())
            .associate { it.songId to it.cnt }
        return songs
            .map { UncollectedSong(song = it, playCount = playCounts[it.id] ?: 0) }
            .sortedWith(compareByDescending<UncollectedSong> { it.playCount }.thenByDescending { it.song.titleKana ?: "" })
    }

    /** 「この公演で未回収が聴けるかも」候補。今日以降の公演のうち、親ブランドが過去に未回収曲を披露した数が多い順。 */
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
