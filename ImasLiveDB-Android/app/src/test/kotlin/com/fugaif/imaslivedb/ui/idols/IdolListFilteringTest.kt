package com.fugaif.imaslivedb.ui.idols

import com.fugaif.imaslivedb.data.model.Idol
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
        nameKana: String? = null,
        aliases: String? = null,
        attribute: String? = null,
        age: Int? = null,
        height: Double? = null
    ) = Idol(
        id = id,
        brandId = brandId,
        name = name,
        nameKana = nameKana,
        nameRomaji = null,
        color = null,
        sortOrder = 0,
        birthday = null,
        bloodType = null,
        height = height,
        weight = null,
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
        nickname = null,
        debutDate = null,
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
        voiceActorText: String = "",
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
        voiceActorText = voiceActorText,
        castNames = castNames
    )

    @Test
    fun `年齢は既定で年上から`() {
        val idols = listOf(idol("a", age = 15), idol("b", age = 32), idol("c", age = 21))
        assertEquals(listOf("b", "c", "a"), sortIdols(idols, IdolSortOrder.AGE).idols.map { it.id })
    }

    @Test
    fun `値なしは並び方向に関わらず末尾`() {
        val idols = listOf(idol("none1"), idol("young", age = 12), idol("none2"), idol("old", age = 30))

        val desc = sortIdols(idols, IdolSortOrder.AGE, ascending = false).idols.map { it.id }
        assertEquals(listOf("old", "young"), desc.take(2))
        assertEquals(setOf("none1", "none2"), desc.takeLast(2).toSet())

        val asc = sortIdols(idols, IdolSortOrder.AGE, ascending = true).idols.map { it.id }
        assertEquals("昇順でも値なしが先頭に来てはいけない", listOf("young", "old"), asc.take(2))
        assertEquals(setOf("none1", "none2"), asc.takeLast(2).toSet())
    }

    @Test
    fun `公式順だけがブランド区切りを保つ`() {
        assertTrue(IdolSortOrder.OFFICIAL.keepsBrandGrouping)
        IdolSortOrder.entries.filter { it != IdolSortOrder.OFFICIAL }.forEach {
            assertFalse("${it.label} は通し並びであるべき", it.keepsBrandGrouping)
        }
    }

    @Test
    fun `指標ラベルはコアが返したものを id で配る`() {
        val sorted = sortIdols(listOf(idol("x", age = 17, height = 158.0), idol("y")), IdolSortOrder.AGE)
        assertEquals(mapOf("x" to "17歳"), sorted.metricById)
        assertTrue(sortIdols(listOf(idol("x", age = 17)), IdolSortOrder.OFFICIAL).metricById.isEmpty())
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
    fun `名前の検索はCV名に当てずCV名の検索で当たる`() {
        val idols = listOf(idol("uzuki", name = "島村卯月"), idol("rin", name = "渋谷凛"))
        val casts = mapOf("uzuki" to "大橋彩香")
        assertTrue(filterIdols(idols, criteria(searchText = "大橋", castNames = casts)).isEmpty())
        val hit = filterIdols(idols, criteria(voiceActorText = "大橋", castNames = casts))
        assertEquals(listOf("uzuki"), hit.map { it.id })
        val counts = idolSearchCounts(idols, criteria(castNames = casts), "大橋")
        assertEquals(0u, counts.name)
        assertEquals(1u, counts.voiceActor)
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
}
