package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.FavoriteRankingEntry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * お気に入りランキングはブランドを手元で絞るので、絞った件数がたまるまで 200 件ずつ
 * offset を進めて読む (iOS CommunityAPI.favoritesRanking と同じ)。
 */
class FavoritesRankingPagingTest {

    /** 全体の並び。偶数番目は "a"、奇数番目は "b" のブランドの曲。 */
    private val all = (0 until 450).map { CommunityApi.FavoriteRankingDto("s$it", 1000 - it) }
    private fun brandOf(songId: String) = if (songId.removePrefix("s").toInt() % 2 == 0) "a" else "b"

    private fun resolve(dtos: List<CommunityApi.FavoriteRankingDto>) =
        dtos.map { FavoriteRankingEntry(it.songId, it.count, it.songId, brandOf(it.songId), null) }

    @Test
    fun stopsAsSoonAsEnoughEntriesAreCollected() = runBlocking {
        val offsets = mutableListOf<Int>()
        val result = StatsRepository.collectFavoritesRanking(
            brandId = "a",
            limit = 20,
            fetchPage = { offset -> offsets += offset; all.drop(offset).take(200) },
            resolve = ::resolve
        )
        assertEquals(listOf(0), offsets)
        assertEquals((0 until 40 step 2).map { "s$it" }, result.map { it.songId })
    }

    @Test
    fun pagesUntilShortPageWhenBrandIsSmall() = runBlocking {
        val offsets = mutableListOf<Int>()
        val result = StatsRepository.collectFavoritesRanking(
            brandId = "b",
            limit = 1000,
            fetchPage = { offset -> offsets += offset; all.drop(offset).take(200) },
            resolve = ::resolve
        )
        // 3 ページ目 (50 件) が満杯でないので終わり。
        assertEquals(listOf(0, 200, 400), offsets)
        assertEquals(225, result.size)
    }

    @Test
    fun dedupesSongsRepeatedAcrossPages() = runBlocking {
        // 読んでいる間に順位が動いて、前のページの末尾の曲が次のページにも出る。
        val pages = mapOf(
            0 to all.take(200),
            200 to listOf(all[199]) + all.drop(200).take(10)
        )
        val result = StatsRepository.collectFavoritesRanking(
            brandId = null,
            limit = 1000,
            fetchPage = { offset -> pages.getValue(offset) },
            resolve = ::resolve
        )
        assertEquals(210, result.size)
        assertEquals(result.size, result.map { it.songId }.toSet().size)
    }
}
