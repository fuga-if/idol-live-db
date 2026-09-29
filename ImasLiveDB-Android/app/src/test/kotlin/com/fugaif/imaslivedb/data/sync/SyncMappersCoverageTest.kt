package com.fugaif.imaslivedb.data.sync

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.imas_core.CkBrandRow
import uniffi.imas_core.CkCostumeRow
import uniffi.imas_core.CkCostumeWearRow
import uniffi.imas_core.CkCreatorRow
import uniffi.imas_core.CkEventRow
import uniffi.imas_core.CkIdolBrandRow
import uniffi.imas_core.CkIdolRow
import uniffi.imas_core.CkRow
import uniffi.imas_core.CkSetlistItemRow
import uniffi.imas_core.CkSetlistPerformerRow
import uniffi.imas_core.CkShowCastRow
import uniffi.imas_core.CkShowRow
import uniffi.imas_core.CkShowTicketRow
import uniffi.imas_core.CkSongArtistRow
import uniffi.imas_core.CkSongRow
import uniffi.imas_core.CkSongVideoRow
import uniffi.imas_core.CkUnitMemberRow
import uniffi.imas_core.CkUnitRow
import uniffi.imas_core.CkUnitVersionRow
import uniffi.imas_core.CkVenueHallRow
import uniffi.imas_core.CkVenueNameRow
import uniffi.imas_core.CkVenueRow
import java.lang.reflect.Field
import java.lang.reflect.Modifier

/**
 * [SyncMappers] が、コアの行 (`Ck*Row`) の**全フィールド**を Room のエンティティへ渡していることを確かめる。
 *
 * Room は同期の行を REPLACE で書くので、読み落とした列は同期のたびに NULL / 既定値で上書きされる
 * (過去に series_group・unit_version_id・joint_brand_ids、Android では events.name_kana で起きた)。
 * 行の型をリフレクションで舐めるので、コアが列を足すとマッパーを直すまでここが落ちる。
 *
 * 各フィールドに区別できる値を入れた行を写し、同名のエンティティの値と比べる。真偽値は
 * 既定値に紛れないよう true / false の両方で回す。
 */
class SyncMappersCoverageTest {

    /** 1 つのレコード型の写し方。[notMapped] は意図して渡さないフィールドと、その理由。 */
    private class Case<R : Any>(
        val rowClass: Class<R>,
        val wrap: (R) -> CkRow,
        val map: (List<CkRow>) -> List<Any>,
        val notMapped: Map<String, String> = emptyMap()
    )

    private val cases: List<Case<*>> = listOf(
        Case(
            CkBrandRow::class.java, CkRow::Brand, SyncMappers::brands,
            notMapped = mapOf(
                "iconUrl" to "brands に列が無く、Android にはブランドのアイコンを出す画面も無い (SyncMappers.brands)"
            )
        ),
        // voiceActors は行に載らない (生レコードから別に拾う) ので、ここでは空で渡す。
        Case(CkIdolRow::class.java, CkRow::Idol, { SyncMappers.idols(it, emptyMap()) }),
        Case(CkEventRow::class.java, CkRow::Event, SyncMappers::events),
        Case(CkShowRow::class.java, CkRow::Show, SyncMappers::shows),
        Case(CkVenueRow::class.java, CkRow::Venue, SyncMappers::venues),
        Case(CkVenueNameRow::class.java, CkRow::VenueName, SyncMappers::venueNames),
        Case(CkVenueHallRow::class.java, CkRow::VenueHall, SyncMappers::venueHalls),
        Case(CkUnitVersionRow::class.java, CkRow::UnitVersion, SyncMappers::unitVersions),
        Case(CkCostumeRow::class.java, CkRow::Costume, SyncMappers::costumes),
        Case(CkCostumeWearRow::class.java, CkRow::CostumeWear, SyncMappers::costumeWears),
        Case(CkCreatorRow::class.java, CkRow::Creator, SyncMappers::creators),
        Case(CkSongRow::class.java, CkRow::Song, SyncMappers::songs),
        Case(CkUnitRow::class.java, CkRow::Unit, SyncMappers::units),
        Case(CkIdolBrandRow::class.java, CkRow::IdolBrand, SyncMappers::idolBrands),
        Case(CkSongArtistRow::class.java, CkRow::SongArtist, SyncMappers::songArtists),
        Case(CkUnitMemberRow::class.java, CkRow::UnitMember, SyncMappers::unitMembers),
        Case(CkShowCastRow::class.java, CkRow::ShowCast, SyncMappers::showCasts),
        Case(CkSetlistItemRow::class.java, CkRow::SetlistItem, SyncMappers::setlistItems),
        Case(CkSetlistPerformerRow::class.java, CkRow::SetlistPerformer, SyncMappers::setlistPerformers),
        Case(CkSongVideoRow::class.java, CkRow::SongVideo, SyncMappers::songVideos),
        Case(CkShowTicketRow::class.java, CkRow::ShowTicket, SyncMappers::showTickets),
    )

    /** コアが取り込むレコード型のどれにも、写し方が用意されている。 */
    @Test
    fun everyRecordTypeHasAMapper() {
        val variants = CkRow::class.java.declaredClasses
            .filter { CkRow::class.java.isAssignableFrom(it) && it != CkRow::class.java }
            .map { it.simpleName }
            .toSet()
        val covered = cases.map { it.wrapSample(flag = true).javaClass.simpleName }.toSet()
        assertEquals(variants, covered)
    }

    @Test
    fun everyFieldReachesTheEntity() {
        val problems = cases.flatMap { it.problems(flag = true) + it.problems(flag = false) }
        assertTrue(problems.joinToString("\n"), problems.isEmpty())
    }

    private fun <R : Any> Case<R>.wrapSample(flag: Boolean): CkRow = wrap(sampleOf(rowClass, flag))

    /** 渡し損ねたフィールドを「型.フィールド: 期待 → 実際」の形で返す。 */
    private fun <R : Any> Case<R>.problems(flag: Boolean): List<String> {
        val row = sampleOf(rowClass, flag)
        val entities = map(listOf(wrap(row)))
        if (entities.size != 1) return listOf("${rowClass.simpleName}: 1 行が ${entities.size} 件になった")
        val entity = entities.single()
        return instanceFields(rowClass).mapNotNull { field ->
            if (field.name in notMapped) return@mapNotNull null
            val expected = field.get(row)
            val target = runCatching { entity.javaClass.getDeclaredField(field.name) }.getOrNull()
                ?: return@mapNotNull "${rowClass.simpleName}.${field.name}: ${entity.javaClass.simpleName} に同名のフィールドが無い"
            target.isAccessible = true
            val actual = target.get(entity)
            if (sameValue(expected, actual)) null
            else "${rowClass.simpleName}.${field.name} (flag=$flag): $expected → $actual"
        }
    }

    /** 全フィールドに区別できる値を入れた行。真偽値はすべて [flag]。 */
    private fun <R : Any> sampleOf(rowClass: Class<R>, flag: Boolean): R {
        val fields = instanceFields(rowClass)
        val types = fields.map { it.type }
        val constructor = rowClass.declaredConstructors.single { it.parameterTypes.toList() == types }
        val args = fields.mapIndexed { i, f -> sampleValue(f, i, flag) }
        @Suppress("UNCHECKED_CAST")
        return constructor.newInstance(*args.toTypedArray()) as R
    }

    private fun sampleValue(field: Field, index: Int, flag: Boolean): Any = when (field.type) {
        String::class.java -> "${field.name}-値"
        java.lang.Long.TYPE, java.lang.Long::class.java -> 1_000L + index
        java.lang.Integer.TYPE, java.lang.Integer::class.java -> 1_000 + index
        java.lang.Double.TYPE, java.lang.Double::class.java -> 1_000.5 + index
        java.lang.Boolean.TYPE, java.lang.Boolean::class.java -> flag
        else -> error("${field.declaringClass.simpleName}.${field.name}: 想定外の型 ${field.type}")
    }

    private fun instanceFields(type: Class<*>): List<Field> =
        type.declaredFields.filterNot { Modifier.isStatic(it.modifiers) }.onEach { it.isAccessible = true }

    /** 数は Long / Int / Double の違いを無視して値で比べる。 */
    private fun sameValue(expected: Any?, actual: Any?): Boolean = when {
        expected is Double || actual is Double ->
            (expected as? Number)?.toDouble() == (actual as? Number)?.toDouble()
        expected is Number && actual is Number -> expected.toLong() == actual.toLong()
        else -> expected == actual
    }
}
