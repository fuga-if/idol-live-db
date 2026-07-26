package com.fugaif.imaslivedb.ui.introdon

import com.fugaif.imaslivedb.data.model.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/**
 * イントロドンの選択肢生成の単体テスト。iOS の `IntroQuizChoicesTests` と 1:1。
 *
 * 核心は「同名異曲が pool にあっても、選択肢に同じタイトルが 2 つ並ばない」こと。
 * 以前の実装は正解と同じタイトルしか弾いておらず、不正解どうしの重複は素通りしていた。
 */
class IntroDonChoicesTest {

    private fun song(id: String, title: String) = Song(
        id = id, title = title, titleKana = null, brandId = null, songType = "original",
        releaseDate = null, durationSec = null, composer = null, lyricist = null, arranger = null,
        cdSeries = null, cdTitle = null, artworkUrl = null, previewUrl = null, appleMusicId = null,
        appleMusicAlbumId = null, isrc = null, lyricsUrl = null, parentSongId = null,
        singerLabel = null, unitName = null, unitId = null
    )

    // --- introDonWrongCandidates (規則そのもの) ---

    /** 正解と同じタイトルの別バージョンは不正解候補にしない。 */
    @Test fun excludesSameTitleDifferentSong() {
        val answer = song("s1", "READY!!")
        val pool = listOf(answer, song("s2", "READY!! (M@STER VERSION)"), song("s3", "READY!!"))
        val titles = introDonWrongCandidates(answer, pool).map { it.title }
        assertFalse(titles.contains("READY!!"))
        assertEquals(listOf("READY!! (M@STER VERSION)"), titles)
    }

    /** 正解そのもの (同じ id) は候補から外す。 */
    @Test fun excludesAnswerItself() {
        val answer = song("s1", "GO MY WAY!!")
        assertEquals(
            listOf("s2"),
            introDonWrongCandidates(answer, listOf(answer, song("s2", "蒼い鳥"))).map { it.id })
    }

    /** 不正解どうしのタイトル重複も落とす (以前はここが抜けていた)。 */
    @Test fun deduplicatesAmongWrongCandidates() {
        val answer = song("s1", "自転車")
        val pool = listOf(song("s2", "隣に…"), song("s3", "隣に…"), song("s4", "オーバーマスター"))
        assertEquals(
            listOf("隣に…", "オーバーマスター"),
            introDonWrongCandidates(answer, pool).map { it.title })
    }

    /** 順序は pool のまま (シャッフルは introDonChoices の責務)。 */
    @Test fun wrongCandidatesKeepPoolOrder() {
        val answer = song("s0", "答え")
        val pool = (1..5).map { song("s$it", "曲$it") }
        assertEquals((1..5).map { "s$it" }, introDonWrongCandidates(answer, pool).map { it.id })
    }

    @Test fun emptyPoolYieldsNoCandidates() {
        assertTrue(introDonWrongCandidates(song("s1", "答え"), emptyList()).isEmpty())
    }

    // --- introDonChoices (出題される 4 択) ---

    @Test fun returnsFourUniqueChoicesIncludingAnswer() {
        val answer = song("s0", "答え")
        val pool = (1..10).map { song("s$it", "曲$it") }
        val choices = introDonChoices(answer, pool, random = Random(42))

        assertEquals(4, choices.size)
        assertEquals("同じ選択肢が 2 つ並んではいけない", 4, choices.toSet().size)
        assertTrue("正解は必ず選択肢に入る", choices.contains("答え"))
    }

    /** 候補が足りなくても落ちず、正解は必ず残る。 */
    @Test fun withTooFewCandidates() {
        val choices = introDonChoices(song("s0", "答え"), listOf(song("s1", "曲1")), random = Random(7))
        assertEquals(listOf("曲1", "答え").sorted(), choices.sorted())
    }

    @Test fun withEmptyPool() {
        assertEquals(listOf("答え"), introDonChoices(song("s0", "答え"), emptyList(), random = Random(7)))
    }

    /** 正解の位置が固定されない (常に末尾なら位置で当てられてしまう)。 */
    @Test fun answerPositionVaries() {
        val answer = song("s0", "答え")
        val pool = (1..10).map { song("s$it", "曲$it") }
        val positions = (0 until 40)
            .map { introDonChoices(answer, pool, random = Random(it)).indexOf("答え") }
            .toSet()
        assertTrue("正解の位置が固定されている: $positions", positions.size > 1)
    }

    /** 同名異曲が多い実データ相当の pool でも、選択肢にタイトル重複が出ない。 */
    @Test fun neverProducesDuplicateTitles() {
        val answer = song("s0", "READY!!")
        val pool = listOf(
            song("s1", "READY!!"), song("s2", "READY!!"),
            song("s3", "CHANGE!!!!"), song("s4", "CHANGE!!!!"),
            song("s5", "M@STERPIECE")
        )
        for (seed in 0 until 40) {
            val choices = introDonChoices(answer, pool, random = Random(seed))
            assertEquals("重複した選択肢: $choices", choices.size, choices.toSet().size)
            assertTrue(choices.contains("READY!!"))
        }
    }
}
