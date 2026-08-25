package com.fugaif.imaslivedb.ui.idols

import com.fugaif.imaslivedb.data.model.Idol
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.imas_core.IdolListFilterCriteria

/**
 * `sortIdols` / `filterIdols` の単体テスト。iOS `IdolListSortingTests` と同じ不変条件を固定する
 * (両 OS で並び・ヒット範囲が食い違わないようにするため)。
 *
 * 判定本体は imas-core なので、ここが見ているのは「Kotlin の射影と index 引き直しが
 * 正しく繋がっているか」と「Android から見た契約」。JVM から imas-core の
 * ホスト dylib を叩く (パスは app/build.gradle.kts の jna.library.path)。
 */
class IdolListFilteringTest {

    private fun idol(
        id: String,
        brandId: String = "cg",
        name: String = id,
        sortOrder: Int = 0,
        nameKana: String? = null,
        nickname: String? = null,
        aliases: String? = null,
        attribute: String? = null,
        age: Int? = null,
        height: Double? = null,
        weight: Double? = null,
        birthday: String? = null,
        debutDate: String? = null
    ) = Idol(
        id = id,
        brandId = brandId,
        name = name,
        nameKana = nameKana,
        nameRomaji = null,
        color = null,
        sortOrder = sortOrder,
        birthday = birthday,
        bloodType = null,
        height = height,
        weight = weight,
        birthPlace = null,
        age = age,
        bust = null,
        waist = null,
        hip = null,
        constellation = null,
        hobbies = null,
        talents = null,
        description = null,
        gender = null,
        handedness = null,
        familyName = null,
        givenName = null,
        nickname = nickname,
        debutDate = debutDate,
        attribute = attribute,
        isExternal = false,
        aliases = aliases,
        voiceActors = null
    )

    private fun criteria(
        selectedBrandIds: List<String> = emptyList(),
        selectedAttribute: String? = null,
        requireMyPick: Boolean = false,
        myPickIds: List<String> = emptyList(),
        requireFavorite: Boolean = false,
        favoriteIds: List<String> = emptyList(),
        requireNote: Boolean = false,
        noteIds: List<String> = emptyList(),
        searchText: String = "",
        castNames: Map<String, String> = emptyMap()
    ) = IdolListFilterCriteria(
        selectedBrandIds = selectedBrandIds,
        selectedAttribute = selectedAttribute,
        requireMyPick = requireMyPick,
        myPickIds = myPickIds,
        requireFavorite = requireFavorite,
        favoriteIds = favoriteIds,
        requireNote = requireNote,
        noteIds = noteIds,
        searchText = searchText,
        castNames = castNames
    )

    @Test
    fun `年齢は既定で年上から`() {
        val idols = listOf(idol("a", age = 15), idol("b", age = 32), idol("c", age = 21))
        assertEquals(listOf("b", "c", "a"), sortIdols(idols, IdolSortOrder.AGE).map { it.id })
    }

    @Test
    fun `年齢の昇順は年下から`() {
        val idols = listOf(idol("a", age = 15), idol("b", age = 32), idol("c", age = 21))
        assertEquals(listOf("a", "c", "b"), sortIdols(idols, IdolSortOrder.AGE, ascending = true).map { it.id })
    }

    @Test
    fun `値なしは並び方向に関わらず末尾`() {
        val idols = listOf(idol("none1"), idol("young", age = 12), idol("none2"), idol("old", age = 30))

        val desc = sortIdols(idols, IdolSortOrder.AGE, ascending = false).map { it.id }
        assertEquals(listOf("old", "young"), desc.take(2))
        assertEquals(setOf("none1", "none2"), desc.takeLast(2).toSet())

        val asc = sortIdols(idols, IdolSortOrder.AGE, ascending = true).map { it.id }
        assertEquals("昇順でも値なしが先頭に来てはいけない", listOf("young", "old"), asc.take(2))
        assertEquals(setOf("none1", "none2"), asc.takeLast(2).toSet())
    }

    @Test
    fun `身長は既定で高い順`() {
        val idols = listOf(idol("s", height = 140.0), idol("t", height = 191.0), idol("m", height = 158.0))
        assertEquals(listOf("t", "m", "s"), sortIdols(idols, IdolSortOrder.HEIGHT).map { it.id })
    }

    @Test
    fun `体重の昇順は軽い順`() {
        val idols = listOf(idol("h", weight = 52.0), idol("l", weight = 30.0), idol("m", weight = 41.0))
        assertEquals(listOf("l", "m", "h"), sortIdols(idols, IdolSortOrder.WEIGHT, ascending = true).map { it.id })
    }

    @Test
    fun `五十音順`() {
        val idols = listOf(idol("c", nameKana = "うえの"), idol("a", nameKana = "あまみ"), idol("b", nameKana = "いおり"))
        assertEquals(listOf("a", "b", "c"), sortIdols(idols, IdolSortOrder.NAME_KANA).map { it.id })
    }

    @Test
    fun `誕生日の昇順は1月から`() {
        val idols = listOf(
            idol("dec", birthday = "--12-01"),
            idol("jan", birthday = "--01-03"),
            idol("jul", birthday = "--07-17")
        )
        assertEquals(listOf("jan", "jul", "dec"), sortIdols(idols, IdolSortOrder.BIRTHDAY).map { it.id })
    }

    @Test
    fun `デビュー日の降順は新しい順`() {
        val idols = listOf(
            idol("old", debutDate = "2011-11-28"),
            idol("new", debutDate = "2019-01-10"),
            idol("mid", debutDate = "2014-02-19")
        )
        assertEquals(listOf("new", "mid", "old"), sortIdols(idols, IdolSortOrder.DEBUT, ascending = false).map { it.id })
    }

    @Test
    fun `同値は公式順で安定させる`() {
        val idols = listOf(
            idol("third", sortOrder = 30, age = 17),
            idol("first", sortOrder = 10, age = 17),
            idol("second", sortOrder = 20, age = 17)
        )
        assertEquals(listOf("first", "second", "third"), sortIdols(idols, IdolSortOrder.AGE).map { it.id })
    }

    @Test
    fun `公式順は sortOrder を使う`() {
        val idols = listOf(idol("b", sortOrder = 2), idol("a", sortOrder = 1), idol("c", sortOrder = 3))
        assertEquals(listOf("a", "b", "c"), sortIdols(idols, IdolSortOrder.OFFICIAL).map { it.id })
    }

    @Test
    fun `公式順だけがブランド区切りを保つ`() {
        assertTrue(IdolSortOrder.OFFICIAL.keepsBrandGrouping)
        IdolSortOrder.entries.filter { it != IdolSortOrder.OFFICIAL }.forEach {
            assertFalse("${it.label} は通し並びであるべき", it.keepsBrandGrouping)
        }
    }

    @Test
    fun `指標ラベルは並び替え対象の項目だけ出す`() {
        val i = idol("x", age = 17, height = 158.0, weight = 45.0)
        assertEquals("17歳", IdolSortOrder.AGE.metricLabel(i))
        assertEquals("158cm", IdolSortOrder.HEIGHT.metricLabel(i))
        assertEquals("45kg", IdolSortOrder.WEIGHT.metricLabel(i))
        assertNull(IdolSortOrder.OFFICIAL.metricLabel(i))
        assertNull(IdolSortOrder.NAME_KANA.metricLabel(i))
    }

    @Test
    fun `値がなければ指標ラベルも出ない`() {
        val i = idol("x")
        assertNull(IdolSortOrder.AGE.metricLabel(i))
        assertNull(IdolSortOrder.HEIGHT.metricLabel(i))
    }

    @Test
    fun `検索は愛称にも当たる`() {
        // 「にこにー」は name にも nameKana にも含まれない。愛称を見ないとヒットしない。
        val idols = listOf(idol("niko", name = "矢澤にこ", nameKana = "やざわにこ", nickname = "にこにー"), idol("other", name = "他"))
        assertEquals(listOf("niko"), filterIdols(idols, criteria(searchText = "にこにー")).map { it.id })
    }

    @Test
    fun `検索は別名のフルネームにも当たる`() {
        // 表示名を短くしたアイドルをフルネームで引けること (aliases のカンマ分割はコア側)。
        val idols = listOf(
            idol("roko", name = "ロコ", nameKana = "ろこ", aliases = "伴田路子,はんだろこ"),
            idol("other", name = "他")
        )
        assertEquals(listOf("roko"), filterIdols(idols, criteria(searchText = "伴田")).map { it.id })
    }

    @Test
    fun `検索はCV名にも当たる`() {
        val idols = listOf(idol("uzuki", name = "島村卯月"), idol("rin", name = "渋谷凛"))
        val hit = filterIdols(idols, criteria(searchText = "大橋", castNames = mapOf("uzuki" to "大橋彩香")))
        assertEquals(listOf("uzuki"), hit.map { it.id })
    }

    @Test
    fun `検索語は trim しない`() {
        // iOS も imas-core も前後空白を落とさない。名前に空白が無い以上ヒット 0 件が正。
        val idols = listOf(idol("uzuki", name = "島村卯月"))
        assertTrue(filterIdols(idols, criteria(searchText = "島村 ")).isEmpty())
        assertEquals(listOf("uzuki"), filterIdols(idols, criteria(searchText = "島村")).map { it.id })
    }

    @Test
    fun `ブランド・属性・マイマークは AND で効く`() {
        val idols = listOf(
            idol("a", brandId = "cg", attribute = "cute"),
            idol("b", brandId = "cg", attribute = "cool"),
            idol("c", brandId = "ml", attribute = "cute")
        )
        val kept = filterIdols(
            idols,
            criteria(
                selectedBrandIds = listOf("cg"),
                selectedAttribute = "cute",
                requireMyPick = true,
                myPickIds = listOf("a", "c")
            )
        )
        assertEquals(listOf("a"), kept.map { it.id })
    }

    @Test
    fun `絞り込みは入力順を保つ`() {
        val idols = listOf(idol("c", sortOrder = 3), idol("a", sortOrder = 1), idol("b", sortOrder = 2))
        assertEquals(listOf("c", "a", "b"), filterIdols(idols, criteria()).map { it.id })
    }
}
