package com.fugaif.imaslivedb.data.sync

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.room.Room
import androidx.sqlite.db.SupportSQLiteDatabase
import com.fugaif.imaslivedb.data.db.AppDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.io.File

/**
 * [SeedImporter] を、ビルド時に db/master.sql から生成した本物の seed (assets/master_seed.sqlite)
 * で動かす。
 *
 * DB は本番と同じ設定 ([AppDatabase.configure]: 移行とコールバック) でメモリ上に作る。
 * 初回起動の「空の DB に seed を入れる」を再現し、seed の中身がそのまま入ることを確かめる。
 */
@RunWith(RobolectricTestRunner::class)
class SeedImporterTest {

    private lateinit var context: Context
    private lateinit var db: AppDatabase
    private lateinit var seedFile: File
    private lateinit var seed: SQLiteDatabase

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        db = AppDatabase.configure(Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java))
            .allowMainThreadQueries()
            .build()
        seedFile = File.createTempFile("seed", ".sqlite")
        context.assets.open(SEED_ASSET).use { input -> seedFile.outputStream().use { input.copyTo(it) } }
        seed = SQLiteDatabase.openDatabase(seedFile.path, null, SQLiteDatabase.OPEN_READONLY)
    }

    @After
    fun tearDown() {
        seed.close()
        db.close()
        seedFile.delete()
    }

    /** 空の DB に入れると、seed と共通の表はどれも seed と同じ行数になる。 */
    @Test
    fun importsEveryCommonTableFromTheSeed() = runBlocking {
        assertTrue(SeedImporter.importIfNeeded(context, db))
        assertNull(SeedImporter.lastImportError)

        val room = db.openHelper.writableDatabase
        val common = tables(room).intersect(tables(seed).toSet()) - INTERNAL_TABLES
        assertTrue("seed と共通の表が見つからない: $common", "songs" in common && "setlist_performers" in common)
        for (table in common) {
            assertEquals("$table の行数", count(seed, table), count(room, table))
        }
    }

    /**
     * brands が入っていれば投入済みとみなし、2 回目は seed を読まない。
     * (行数が変わらないだけなら INSERT OR IGNORE でも同じになるので、消した行が戻らないことで見る)
     */
    @Test
    fun skipsWhenBrandsAlreadyExist() = runBlocking {
        assertTrue(SeedImporter.importIfNeeded(context, db))
        val room = db.openHelper.writableDatabase
        room.execSQL("DELETE FROM songs")

        assertTrue(SeedImporter.importIfNeeded(context, db))
        assertEquals("投入済みの DB に seed を入れ直した", 0, count(room, "songs"))
    }

    /**
     * 新しく作った DB に入れると、スタッフと記念日は seed の値そのものになる。
     * (DB の作成時に直書きの古い値を先に入れると、seed の INSERT OR IGNORE に勝ってしまう)
     */
    @Test
    fun staffAndAnniversariesComeFromTheSeed() = runBlocking {
        assertTrue(SeedImporter.importIfNeeded(context, db))
        val room = db.openHelper.writableDatabase
        for ((table, columns) in SEEDED_ROWS) {
            val sql = "SELECT $columns FROM $table ORDER BY id"
            assertEquals(table, rows(seed, sql), rows(room, sql))
        }
    }

    /** 端末ローカルにしかない表には何も入れない (seed は利用者のデータを持たない)。 */
    @Test
    fun leavesLocalOnlyTablesEmpty() = runBlocking {
        assertTrue(SeedImporter.importIfNeeded(context, db))
        val room = db.openHelper.writableDatabase
        for (table in listOf("user_marks", "personal_tags", "expenses")) {
            assertEquals("$table に行が入った", 0, count(room, table))
        }
    }

    /**
     * 同梱の seed が端末より新しければ、マスタ表を seed で入れ直す。複合 PK の表に残った
     * 余剰行 (CloudKit で物理削除された歌唱者など) も消え、端末にしかない表は残る。
     */
    @Test
    fun reseedReplacesMasterTablesAndKeepsLocalData() = runBlocking {
        assertTrue(SeedImporter.importIfNeeded(context, db))
        val room = db.openHelper.writableDatabase
        val item = rows(room, "SELECT id FROM setlist_items LIMIT 1")[0][0]
        room.execSQL("INSERT INTO setlist_performers (setlist_item_id, idol_id) VALUES ('$item', 'removed_idol')")
        room.execSQL("INSERT INTO user_marks (entity_type, entity_id, kind, bool_value, text_value, updated_at) VALUES ('song', 's', 'favorite', 1, NULL, 't')")
        room.execSQL("INSERT INTO personal_tags (entity_type, entity_id, tag_name, created_at) VALUES ('song', 's', 'tag', 't')")
        room.execSQL("INSERT INTO expenses (id, date, category, amount, updated_at) VALUES ('e1', '2026-01-01', 'ticket', 100, 't')")
        // 端末は前の版の seed で入っている。
        room.execSQL("UPDATE meta SET value = '1' WHERE key = 'data_version'")
        room.execSQL("DELETE FROM meta WHERE key = 'content_hash'")

        assertTrue(SeedImporter.reseedFrom(db, seedFile.path))

        assertEquals("余剰の歌唱者が残った", count(seed, "setlist_performers"), count(room, "setlist_performers"))
        for (table in listOf("user_marks", "personal_tags", "expenses")) {
            assertEquals("$table が消えた", 1, count(room, table))
        }
        val meta = "SELECT key, value FROM meta WHERE key IN ('data_version', 'content_hash') ORDER BY key"
        assertEquals(rows(seed, meta), rows(room, meta))
    }

    /**
     * 入れ直しが失敗したら、判定済みの印を付けず次の起動でもう一度試す (RedTeam A-M4)。
     * ただし何度も失敗し続けるときは、上限の回数で諦める。
     */
    @Test
    fun failedReseedIsRetriedOnTheNextLaunchUpToALimit() = runBlocking {
        assertTrue(SeedImporter.importIfNeeded(context, db))
        forgetReseedCheck()

        var attempts = 0
        repeat(5) { SeedImporter.reseedIfNeeded(context, db) { attempts++; error("ATTACH と WAL が当たった") } }
        assertEquals("失敗した入れ直しを上限まで試し直していない", 3, attempts)
    }

    /** 入れ直しが済んだら、同じ更新の間は判定し直さない。 */
    @Test
    fun reseedIsCheckedOncePerUpdate() = runBlocking {
        assertTrue(SeedImporter.importIfNeeded(context, db))
        forgetReseedCheck()

        var attempts = 0
        repeat(2) { SeedImporter.reseedIfNeeded(context, db) { attempts++; false } }
        assertEquals(1, attempts)
    }

    /** 新規インストールの初回投入の直後は、入れ直しの判定のために seed を複製し直さない (RedTeam A-L6)。 */
    @Test
    fun firstImportSkipsTheReseedCheck() = runBlocking {
        assertTrue(SeedImporter.importIfNeeded(context, db))

        var attempts = 0
        SeedImporter.reseedIfNeeded(context, db) { attempts++; false }
        assertEquals(0, attempts)
    }

    private fun forgetReseedCheck() {
        context.getSharedPreferences("imas_seed", Context.MODE_PRIVATE).edit().clear().commit()
    }

    /** seed が端末と同じなら入れ直さない (端末の行はそのまま)。 */
    @Test
    fun reseedSkipsWhenSeedIsNotNewer() = runBlocking {
        assertTrue(SeedImporter.importIfNeeded(context, db))
        val room = db.openHelper.writableDatabase
        room.execSQL("DELETE FROM songs")

        assertTrue(!SeedImporter.reseedFrom(db, seedFile.path))
        assertEquals(0, count(room, "songs"))
    }

    private fun tables(db: SQLiteDatabase): List<String> =
        db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'", null).use { c ->
            buildList { while (c.moveToNext()) add(c.getString(0)) }
        }

    private fun tables(db: SupportSQLiteDatabase): List<String> =
        db.query("SELECT name FROM sqlite_master WHERE type='table'").use { c ->
            buildList { while (c.moveToNext()) add(c.getString(0)) }
        }

    private fun rows(db: SQLiteDatabase, sql: String): List<List<String?>> =
        db.rawQuery(sql, null).use { c ->
            buildList { while (c.moveToNext()) add((0 until c.columnCount).map { c.getString(it) }) }
        }

    private fun rows(db: SupportSQLiteDatabase, sql: String): List<List<String?>> =
        db.query(sql).use { c ->
            buildList { while (c.moveToNext()) add((0 until c.columnCount).map { c.getString(it) }) }
        }

    private fun count(db: SQLiteDatabase, table: String): Int =
        db.rawQuery("SELECT COUNT(*) FROM \"$table\"", null).use { it.moveToFirst(); it.getInt(0) }

    private fun count(db: SupportSQLiteDatabase, table: String): Int =
        db.query("SELECT COUNT(*) FROM \"$table\"").use { it.moveToFirst(); it.getInt(0) }

    private companion object {
        const val SEED_ASSET = "master_seed.sqlite"

        /** 作成時の直書きと seed の両方が入れていた表と、比べる列。 */
        val SEEDED_ROWS = listOf(
            "staff" to "id, brand_id, name, name_kana, name_romaji, role, birthday, sort_order",
            "anniversaries" to "id, brand_id, label, date, kind, sort_order",
        )

        /** 行を移さない SQLite / Room の内部表。 */
        val INTERNAL_TABLES = setOf("room_master_table", "android_metadata", "sqlite_sequence")
    }
}
