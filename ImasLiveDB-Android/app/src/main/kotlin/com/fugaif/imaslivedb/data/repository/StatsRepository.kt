package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.BrandSongCount
import com.fugaif.imaslivedb.data.model.DatabaseStats
import com.fugaif.imaslivedb.data.model.FavoriteRankingEntry
import com.fugaif.imaslivedb.data.model.YearlyShowCount
import uniffi.imas_core.CollectionDashboardRecord

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

    private companion object {
        /** 「この公演で聴けるかも」に出す公演の数。 */
        const val CATCH_CHANCE_LIMIT = 8
    }
}
