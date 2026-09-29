package com.fugaif.imaslivedb.data.sync

import androidx.room.Room
import com.fugaif.imaslivedb.data.db.AppDatabase
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
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
import uniffi.imas_core.ckIngestWebServicesBatch
import uniffi.imas_core.ckIsIngestedRecordType
import java.lang.reflect.Field
import java.lang.reflect.Modifier

/**
 * 同期エンジンが取り込むレコード型を 1 型ずつ、CloudKit Web Services の生 JSON から
 * コアの取り込み (ckIngestWebServicesBatch) → 行まで通す (iOS 79e92d86 と同じ狙い)。
 *
 * 型名を打ち間違えると、その型の同期が黙って全件落ちる (取り込み対象外として捨てられる)。
 * 行の各フィールドに区別できる値を載せ、型ごとに 1 件が行として出て、値が届くことを見る。
 */
@RunWith(RobolectricTestRunner::class)
class CloudKitIngestCoverageTest {

    /** レコード型名 → そのレコードから出る行の型。 */
    private val rowClassByRecordType: Map<String, Class<*>> = mapOf(
        "Brand" to CkBrandRow::class.java,
        "Idol" to CkIdolRow::class.java,
        "Event" to CkEventRow::class.java,
        "ImasUnit" to CkUnitRow::class.java,
        "Venue" to CkVenueRow::class.java,
        "Creator" to CkCreatorRow::class.java,
        "UnitVersion" to CkUnitVersionRow::class.java,
        "Costume" to CkCostumeRow::class.java,
        "CostumeWear" to CkCostumeWearRow::class.java,
        "VenueName" to CkVenueNameRow::class.java,
        "VenueHall" to CkVenueHallRow::class.java,
        "IdolBrand" to CkIdolBrandRow::class.java,
        "Show" to CkShowRow::class.java,
        "Song" to CkSongRow::class.java,
        "UnitMember" to CkUnitMemberRow::class.java,
        "SongArtist" to CkSongArtistRow::class.java,
        "ShowCast" to CkShowCastRow::class.java,
        "SetlistItem" to CkSetlistItemRow::class.java,
        "SetlistPerformer" to CkSetlistPerformerRow::class.java,
        "SongVideo" to CkSongVideoRow::class.java,
        "ShowTicket" to CkShowTicketRow::class.java,
    )

    @Test
    fun everyRecordTypeTheEngineSyncsIsIngestedByTheCore() {
        val context = RuntimeEnvironment.getApplication()
        val db = AppDatabase.configure(Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)).build()
        val types = try {
            CloudKitSyncEngine(context, db).ingestedRecordTypes
        } finally {
            db.close()
        }
        assertEquals(rowClassByRecordType.keys, types)
        val notIngested = types.filterNot { ckIsIngestedRecordType(it) }.toSet()
        assertTrue("コアが取り込まない型名: $notIngested", notIngested.isEmpty())
    }

    @Test
    fun eachRecordTypeReachesItsRowFromARawRecord() {
        val problems = rowClassByRecordType
            .flatMap { (recordType, rowClass) -> problems(recordType, rowClass) }
        assertTrue(problems.joinToString("\n"), problems.isEmpty())
    }

    /** 実数 (DOUBLE) と時刻 (TIMESTAMP) の列が型どおりに読まれる。 */
    @Test
    fun realAndTimestampColumnsAreRead() {
        val idol = ingest("Idol", "i1", mapOf(
            "id" to field("i1", "STRING"), "brandId" to field("ml", "STRING"), "name" to field("名前", "STRING"),
            "height" to field(158.5, "DOUBLE"), "age" to field(14, "INT64"), "isExternal" to field(1, "INT64"),
        )).single() as CkRow.Idol
        assertEquals(158.5, idol.row.height)
        assertEquals(14L, idol.row.age?.toLong())
        assertTrue(idol.row.isExternal)

        // 2026-09-23T00:00:00.999Z。秒未満は切り捨てる。
        val video = ingest("SongVideo", "v1", mapOf(
            "id" to field("v1", "STRING"), "songId" to field("s1", "STRING"),
            "youtubeUrl" to field("https://www.youtube.com/watch?v=x", "STRING"),
            "createdAt" to field(1_790_121_600_999L, "TIMESTAMP"),
        )).single() as CkRow.SongVideo
        assertEquals("2026-09-23T00:00:00Z", video.row.createdAt)
    }

    private fun problems(recordType: String, rowClass: Class<*>): List<String> {
        val fields = instanceFields(rowClass).filterNot { it.name == "createdAt" }
        val values = fields.mapIndexed { i, f -> f.name to sampleValue(f, i) }.toMap()
        val recordName = (values["id"] as? String) ?: "test-$recordType"
        val rows = ingest(recordType, recordName, values.mapValues { (name, v) -> jsonField(name, v) })
        if (rows.size != 1) return listOf("$recordType: 1 件が ${rows.size} 行になった (型名か必須の列を見直す)")
        val payload = rows.single().javaClass.declaredFields.first { !Modifier.isStatic(it.modifiers) }
            .apply { isAccessible = true }.get(rows.single())
        if (payload.javaClass != rowClass) return listOf("$recordType: ${payload.javaClass.simpleName} になった")
        return fields.mapNotNull { f ->
            val got = f.get(payload)
            val want = values.getValue(f.name)
            if (same(want, got)) null else "$recordType.${f.name}: $want → $got"
        }
    }

    private fun ingest(recordType: String, recordName: String, fields: Map<String, JSONObject>): List<CkRow> {
        val json = JSONObject()
            .put("recordName", recordName)
            .put("recordType", recordType)
            .put("fields", JSONObject(fields))
        return ckIngestWebServicesBatch(recordType, listOf(json.toString()), NOW).rows
    }

    private fun sampleValue(field: Field, index: Int): Any = when (field.type) {
        // 値の決まった列は、コアが正規化しない正しい値にする。
        String::class.java -> ENUM_LIKE_VALUES[field.name] ?: "${field.name}-値"
        java.lang.Long.TYPE, java.lang.Long::class.java -> 1_000L + index
        java.lang.Integer.TYPE, java.lang.Integer::class.java -> 1_000 + index
        java.lang.Double.TYPE, java.lang.Double::class.java -> 1_000.5 + index
        java.lang.Boolean.TYPE, java.lang.Boolean::class.java -> true
        else -> "${field.name}-値"
    }

    private fun jsonField(name: String, value: Any): JSONObject = when (value) {
        is String -> field(value, "STRING")
        is Boolean -> field(if (value) 1 else 0, "INT64")
        is Double -> field(value, "DOUBLE")
        else -> field(value, "INT64")
    }

    private fun field(value: Any, type: String) = JSONObject().put("value", value).put("type", type)

    private fun instanceFields(type: Class<*>): List<Field> =
        type.declaredFields.filterNot { Modifier.isStatic(it.modifiers) }.onEach { it.isAccessible = true }

    private fun same(expected: Any?, actual: Any?): Boolean = when {
        expected is Double || actual is Double ->
            (expected as? Number)?.toDouble() == (actual as? Number)?.toDouble()
        expected is Number && actual is Number -> expected.toLong() == actual.toLong()
        expected is String && actual is String -> expected.equals(actual, ignoreCase = true)
        else -> expected == actual
    }

    private companion object {
        const val NOW = 1_790_000_000_000L

        /** 値の決まった列の正しい値 (色は `#` 無しの 16 進、出演の役割は語彙の値)。 */
        val ENUM_LIKE_VALUES = mapOf("color" to "E22B30", "castRole" to "lead")
    }
}
