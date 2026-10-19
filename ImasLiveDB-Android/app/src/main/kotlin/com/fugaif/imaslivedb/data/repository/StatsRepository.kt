package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.BrandSongCount
import com.fugaif.imaslivedb.data.model.DatabaseStats
import com.fugaif.imaslivedb.data.model.YearlyShowCount
import uniffi.imas_core.CollectionDashboardRecord
import uniffi.imas_core.CommunityRankingKind

/**
 * 統計・回収ダッシュボードの読み取り口。
 *
 * カタログ側の集計 (ブランド別曲数・年別公演数・回収ダッシュボード) は共有コア (imas-core) の
 * スナップショットが答える (SQL の代わりの経路は持たない)。
 * 参加マーク (user_marks) はスナップショットに含まれないので、解決済みの id 集合を
 * 呼び出し側 (UserMarkRepository) から受け取り、コアへは引数で渡す。
 */
class StatsRepository(
    private val db: AppDatabase,
    private val communityApi: CommunityApi,
    private val snapshots: SnapshotStoreProvider
) {

    suspend fun fetchBrands(): List<Brand> =
        snapshots.query { store -> store.brandRecords().map { it.toBrand() } }

    suspend fun fetchBrandSongCounts(): List<BrandSongCount> =
        snapshots.query { store ->
            store.brandSongCounts().map {
                BrandSongCount(id = it.id, shortName = it.shortName, color = it.color, songCount = it.songCount.toInt())
            }
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

    suspend fun fetchYearlyShowCounts(): List<YearlyShowCount> =
        snapshots.query { store ->
            store.yearlyShowCounts().map { YearlyShowCount(year = it.year, showCount = it.showCount.toInt()) }
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

    // MARK: - Collection Dashboard

    /**
     * 回収ダッシュボード (全体・ブランド別の回収率、担当/全体の未回収曲と披露頻度、
     * 「この公演で聴けるかも」)。1 画面 = 1 FFI で、集計・並び・閾値は全部コア
     * (collectionDashboard)。collectedIds / pickIdolIds は呼び出し側 (UserMarkRepository) が解決して渡す。
     */
    suspend fun fetchCollectionDashboard(collectedIds: Set<String>, pickIdolIds: Set<String>): CollectionDashboardRecord =
        snapshots.query { store ->
            store.collectionDashboard(
                collectedIds.toList(), pickIdolIds.toList(), JstDay.today(), CATCH_CHANCE_LIMIT.toUInt()
            )
        }

    // MARK: - コミュニティの熱量 (人気・急上昇・お気に入り・試聴・フル再生のランキング)

    /**
     * みんなの集計から [kind] の順位表を作る。順位・点・今週の数・ブランドの絞り込みはコア
     * (`SnapshotStore.communityRanking`)。ここは曲メタ (題・ジャケ) の引き当てだけ。
     * 集計が取れなければ null (空の順位表と区別する)。
     */
    suspend fun fetchCommunityRanking(kind: CommunityRankingKind, brandId: String?, limit: Int): CommunityRanking? {
        val stats = communityApi.songStats() ?: return null
        val ranked = snapshots.query { store -> store.communityRanking(stats, kind, brandId, limit.toUInt()) }
        val songs = db.songDao().fetchSongsByIds(ranked.map { it.songId }).associateBy { it.id }
        return CommunityRanking(
            playsSince = stats.playsSince,
            items = ranked.map { r ->
                val song = songs[r.songId]
                CommunityRankingItem(
                    rank = r.rank.toInt(),
                    songId = r.songId,
                    value = r.value.toLong(),
                    title = song?.title ?: r.songId,
                    brandId = song?.brandId,
                    artworkUrl = song?.artworkUrl
                )
            }
        )
    }

    internal companion object {
        /** 「この公演で聴けるかも」に出す公演の数。 */
        private const val CATCH_CHANCE_LIMIT = 8

        /**
         * お気に入りランキングを 1 ページ ([CommunityApi.FAVORITES_RANKING_PAGE_SIZE] 件) ずつ読み、
         * ブランドで絞った件数が [limit] に届くまで offset を進める (iOS CommunityAPI.favoritesRanking と同じ)。
         * 一度に全件は取らない。小さいブランドの曲も上位 200 で切れない。
         * 読んでいる間に順位が入れ替わってページをまたいで同じ曲が出ることがあるので、曲 ID で重複を除く。
         */
        suspend fun collectFavoritesRanking(
            brandId: String?,
            limit: Int,
            fetchPage: suspend (offset: Int) -> List<CommunityApi.FavoriteRankingDto>,
            resolve: suspend (List<CommunityApi.FavoriteRankingDto>) -> List<FavoriteRankingEntry>
        ): List<FavoriteRankingEntry> {
            val pageSize = CommunityApi.FAVORITES_RANKING_PAGE_SIZE
            val entries = mutableListOf<FavoriteRankingEntry>()
            val seen = HashSet<String>()
            var offset = 0
            while (entries.size < limit) {
                val dtos = fetchPage(offset)
                val fresh = dtos.filter { seen.add(it.songId) }
                entries += resolve(fresh).filter { brandId == null || it.brandId == brandId }
                // 満杯でないページが最後。満杯でも新しい曲が 1 つも無ければ進めても同じなので打ち切る。
                if (dtos.size < pageSize || fresh.isEmpty()) break
                offset += pageSize
            }
            return entries.take(limit)
        }
    }
}

/** 順位表の 1 行。[value] は種類ごとの数 (人気=点、急上昇=今週の再生回数、ほかはその数)。 */
data class CommunityRankingItem(
    val rank: Int,
    val songId: String,
    val value: Long,
    val title: String,
    val brandId: String?,
    val artworkUrl: String?
)

/** [playsSince] は再生回数を数え始めた日 (`yyyy-MM-dd`)。 */
data class CommunityRanking(val playsSince: String, val items: List<CommunityRankingItem>)
