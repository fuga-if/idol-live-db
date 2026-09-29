package com.fugaif.imaslivedb.data.db

import android.content.Context
import androidx.room.Room
import androidx.room.testing.MigrationTestHelper
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Room の移行 ([AppDatabase.ALL_MIGRATIONS]) を、配布済みの旧版の DB から最新版まで流して確かめる。
 *
 * 旧版の DB は `app/schemas` の JSON (= その版で Room が作った形) から組み立てる。
 * 確かめることは 2 つ。
 *  - 移行後の形が最新版の宣言 (`@Entity`) と厳密に一致する。Room 2.6.1 は列も索引も
 *    厳密に照合するので、ずれた端末は起動のたびに落ち、データ消去でしか抜けられない。
 *  - 端末ローカルにしかない表 (user_marks / personal_tags / expenses) の行が残る。
 *
 * 照合は 2 通りで行う。[MigrationTestHelper.runMigrationsAndValidate] (最新版の JSON と照合) と、
 * 本番と同じ `Room.databaseBuilder` で開く経路 (生成された `AppDatabase_Impl` の照合)。
 */
@RunWith(RobolectricTestRunner::class)
class AppDatabaseMigrationTest {

    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        AppDatabase::class.java,
        emptyList(),
        FrameworkSQLiteOpenHelperFactory()
    )

    private val context: Context get() = InstrumentationRegistry.getInstrumentation().targetContext

    /** 配布済みの Room 4 / 7 の端末は、この版を通って上がってくる (MIGRATION_9_10 が索引を作る)。 */
    @Test fun migrates9ToLatest() = assertMigrates(from = 9)

    /** 配布済みの版 (11 / 12)。 */
    @Test fun migrates11ToLatest() = assertMigrates(from = 11)

    @Test fun migrates12ToLatest() = assertMigrates(from = 12)

    @Test fun migrates13ToLatest() = assertMigrates(from = 13)

    @Test fun migrates15ToLatest() = assertMigrates(from = 15)

    /** v10〜v18 を新規に作った端末には索引が無い。MIGRATION_18_19 が作る。 */
    @Test fun migrates18ToLatest() = assertMigrates(from = 18)

    @Test fun migrates19ToLatest() = assertMigrates(from = 19)

    /**
     * v20 で足した声優の表は、上がってきた端末では空。最後に取り込んだ seed の指紋を消して、
     * 次の起動で同梱の seed から入れ直させる (版番号は残す)。
     */
    @Test
    fun migrating19To20ForcesTheNextReseed() {
        val name = "reseed_19.sqlite"
        helper.createDatabase(name, 19).use {
            it.execSQL("INSERT INTO meta (key, value) VALUES ('data_version', '88'), ('content_hash', 'abc')")
        }
        helper.runMigrationsAndValidate(name, 20, true, AppDatabase.MIGRATION_19_20).use { db ->
            db.query("SELECT key, value FROM meta ORDER BY key").use { c ->
                val rows = buildList { while (c.moveToNext()) add(c.getString(0) to c.getString(1)) }
                assertEquals(listOf("data_version" to "88"), rows)
            }
            assertEquals(0, count(db, "idol_voice_actors"))
        }
    }

    private fun assertMigrates(from: Int) {
        val validated = "validated_$from.sqlite"
        helper.createDatabase(validated, from).use { insertLocalOnlyRows(it, from) }
        helper.runMigrationsAndValidate(validated, LATEST, true, *AppDatabase.ALL_MIGRATIONS)
            .use { assertLocalOnlyRowsSurvive(it, from) }

        // 本番の起動と同じ経路 (onUpgrade → 生成コードの照合) でも落ちないこと。
        val opened = "opened_$from.sqlite"
        helper.createDatabase(opened, from).use { insertLocalOnlyRows(it, from) }
        val room = Room.databaseBuilder(context, AppDatabase::class.java, opened)
            .addMigrations(*AppDatabase.ALL_MIGRATIONS)
            .allowMainThreadQueries()
            .build()
        try {
            assertLocalOnlyRowsSurvive(room.openHelper.writableDatabase, from)
        } finally {
            room.close()
        }
    }

    private fun insertLocalOnlyRows(db: SupportSQLiteDatabase, version: Int) {
        db.execSQL(
            "INSERT INTO user_marks (entity_type, entity_id, kind, bool_value, text_value, updated_at) " +
                "VALUES ('idol', 'ml_miki', 'pick', 1, NULL, '2026-01-01T00:00:00Z')"
        )
        db.execSQL(
            "INSERT INTO personal_tags (entity_type, entity_id, tag_name, created_at) " +
                "VALUES ('song', 'as_ready', '推し曲', '2026-01-01T00:00:00Z')"
        )
        if (version >= EXPENSES_SINCE) {
            db.execSQL(
                "INSERT INTO expenses (id, date, category, amount, show_id, event_id, note, updated_at) " +
                    "VALUES ('e1', '2026-01-01', 'ticket', 12000, NULL, NULL, NULL, '2026-01-01T00:00:00Z')"
            )
        }
    }

    private fun assertLocalOnlyRowsSurvive(db: SupportSQLiteDatabase, from: Int) {
        assertEquals("user_marks が消えた", 1, count(db, "user_marks"))
        assertEquals("personal_tags が消えた", 1, count(db, "personal_tags"))
        assertEquals("expenses が消えた", if (from >= EXPENSES_SINCE) 1 else 0, count(db, "expenses"))
    }

    private fun count(db: SupportSQLiteDatabase, table: String): Int =
        db.query("SELECT COUNT(*) FROM $table").use { it.moveToFirst(); it.getInt(0) }

    private companion object {
        /** `@Database(version = …)` と同じ値。版を上げたらここも上げる。 */
        const val LATEST = 20

        /** 家計簿 (expenses) を作った版 (MIGRATION_16_17)。 */
        const val EXPENSES_SINCE = 17
    }
}
