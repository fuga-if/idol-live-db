package com.fugaif.imaslivedb.data.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * 検索ハイライトの範囲 ([TextSearch.matchRange])。iOS `SearchHighlightTests` と 1:1。
 *
 * 規則そのものはコア (imas-core `domain/text_search_index.rs`) が持っているので、
 * ここで見るのは **コアが返す UTF-8 バイト位置を Kotlin の添字 (UTF-16) に正しく移せているか**。
 * 多バイト文字だらけの日本語で 1 バイトずれると、色が半文字ずれるか範囲が出せなくなる。
 *
 * JVM から imas-core のホスト dylib を叩く (パスは app/build.gradle.kts の jna.library.path)。
 */
class SearchHighlightTest {

    private fun highlighted(text: String, needle: String): String? =
        TextSearch.matchRange(text, needle)?.let { text.substring(it.start, it.end) }

    /** 回帰 (2026-08-27): 「おね」で一覧に出た「マリオネットの心」に色が付かなかった。 */
    @Test fun hiraganaQueryHighlightsKatakana() {
        assertEquals("オネ", highlighted("マリオネットの心", "おね"))
        assertEquals("おね", highlighted("おねがい", "オネ"))
    }

    /** 先頭でも末尾でも、多バイト文字をまたいでも位置がずれない。 */
    @Test fun rangeIsExactAcrossMultibyteText() {
        assertEquals("夢色", highlighted("夢色ハーモニー", "夢色"))
        assertEquals("モニー", highlighted("夢色ハーモニー", "もにー"))
        assertEquals("シンデレラ", highlighted("お願い！シンデレラ", "しんでれら"))
    }

    /** サロゲートペア (絵文字は 1 文字 = UTF-16 で 2 単位) をまたいでも添字がずれない。 */
    @Test fun rangeIsExactAfterSurrogatePairs() {
        assertEquals("ライブ", highlighted("🎤🎶ライブ", "ライブ"))
    }

    /** 大文字小文字は畳む (従来どおり)。 */
    @Test fun caseIsFolded() {
        assertEquals("READY", highlighted("READY!!", "ready"))
    }

    /** 当たらない語と空の語では範囲を返さない (色を敷かない)。 */
    @Test fun noRangeWithoutAHit() {
        assertNull(highlighted("夢色ハーモニー", "星空"))
        assertNull(highlighted("夢色ハーモニー", ""))
    }

    /** [TextSearch.matches] は「色を敷ける一致」と同じ判定であること。 */
    @Test fun matchesAgreesWithRange() {
        assertEquals(true, TextSearch.matches("マリオネットの心", "おね"))
        assertEquals(false, TextSearch.matches("マリオネットの心", "星空"))
    }
}
