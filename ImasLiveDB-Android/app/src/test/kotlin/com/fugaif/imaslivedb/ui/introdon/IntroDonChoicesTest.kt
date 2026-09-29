package com.fugaif.imaslivedb.ui.introdon

import com.fugaif.imaslivedb.data.model.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/**
 * イントロドンの選択肢生成 (imas-core 委譲) の単体テスト。iOS の `IntroQuizChoicesTests` と 1:1。
 *
 * 規則そのもの (タイトルでのユニーク化・不正解候補が pool 順を保つこと等) は
 * imas-core の `domain/intro_quiz_choices.rs` の Rust テストが担う。ここでは
 * Kotlin ラッパ (射影とシード調達) を通しても核心が成り立つことを見る。核心は
 * 「同名異曲が pool にあっても、正解と同じタイトルが不正解として並ばない」こと
 * (並ぶと正しい答えを選んでも不正解になる)。
 */
class IntroDonChoicesTest {

    private fun song(id: String, title: String) = Song(
        id = id, title = title, titleKana = null, brandId = null, songType = "original",
        releaseDate = null, durationSec = null, composer = null, lyricist = null, arranger = null,
        cdSeries = null, cdTitle = null, artworkUrl = null, previewUrl = null, appleMusicId = null,
        appleMusicAlbumId = null, isrc = null, lyricsUrl = null, parentSongId = null,
        singerLabel = null, unitName = null, unitId = null
    )

    /** 1 問だけのバッチで選択肢を引く (規則検証の便宜用)。 */
    private fun choicesFor(answer: Song, pool: List<Song>, seed: Int = 42): List<String> =
        introDonChoicesAll(listOf(answer), pool, random = Random(seed)).first()

    // --- タイトルユニーク化の規則 ---

    /** 正解と同じタイトルの別バージョンは不正解候補にしない。 */
    @Test fun excludesSameTitleDifferentSong() {
        val answer = song("s1", "READY!!")
        val pool = listOf(answer, song("s2", "READY!! (M@STER VERSION)"), song("s3", "READY!!"))
        for (seed in 0 until 40) {
            val choices = choicesFor(answer, pool, seed)
            assertEquals(setOf("READY!!", "READY!! (M@STER VERSION)"), choices.toSet())
            assertEquals("正解と同じタイトルが重複して並んだ: $choices", 2, choices.size)
        }
    }

    /** 不正解どうしのタイトル重複も落とす (以前はここが抜けていた)。 */
    @Test fun deduplicatesAmongWrongCandidates() {
        val answer = song("s1", "自転車")
        val pool = listOf(song("s2", "隣に…"), song("s3", "隣に…"), song("s4", "オーバーマスター"))
        val choices = choicesFor(answer, pool)
        assertEquals(setOf("自転車", "隣に…", "オーバーマスター"), choices.toSet())
        assertEquals("不正解どうしの重複が残った: $choices", 3, choices.size)
    }

    // --- 出題される 4 択 ---

    /** 正解の位置が固定されない (常に末尾なら位置で当てられてしまう)。 */
    @Test fun answerPositionVaries() {
        val answer = song("s0", "答え")
        val pool = (1..10).map { song("s$it", "曲$it") }
        val positions = (0 until 40)
            .map { choicesFor(answer, pool, it).indexOf("答え") }
            .toSet()
        assertTrue("正解の位置が固定されている: $positions", positions.size > 1)
    }

    // --- バッチ (1 ゲーム = 1 呼び出し) ---

    /** 出題と同順・同数で返り、各問に自分の正解が入る。 */
    @Test fun returnsChoicesPerAnswerInOrder() {
        val pool = (1..10).map { song("s$it", "曲$it") }
        val answers = listOf(pool[0], pool[4], pool[9])

        val all = introDonChoicesAll(answers, pool, random = Random(42))

        assertEquals(answers.size, all.size)
        answers.zip(all).forEach { (answer, choices) ->
            assertEquals(4, choices.size)
            assertTrue("${answer.title} が自分の設問の選択肢にない", choices.contains(answer.title))
            assertEquals("重複した選択肢: $choices", choices.size, choices.toSet().size)
        }
    }
}
