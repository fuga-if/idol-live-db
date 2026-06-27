package com.fugaif.imaslivedb.data.sync

import android.content.Context
import android.util.Log
import androidx.sqlite.db.SupportSQLiteDatabase
import com.fugaif.imaslivedb.data.db.AppDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * 初回起動時に、ビルド時生成した seed sqlite (assets/master_seed.sqlite) から
 * 実データを Room DB へ投入する。
 *
 * iOS は db/master.sql から生成した master.sqlite をバンドルし、その上に CloudKit 差分を
 * 当てる設計。Android も同じ思想で「seed = 基準データ / CloudKit = 増分同期」とする。
 * これにより CloudKit API token 未設定でもアプリは実データで完動する (token はリリース版の
 * 最新化のためだけ)。
 *
 * 方式: Room がスキーマの真実を握ったまま (createFromAsset のスキーマ検証クラッシュを避ける)、
 * seed を ATTACH して「Room と seed の両方に存在するテーブル」だけを、両方に共通する列だけ
 * INSERT OR IGNORE で行コピーする。
 *  - song_units 等 (seed 側のみ / Room エンティティ無し) → スキップ
 *  - user_marks / song_calls / song_videos (Room 側のみ / seed に無い) → 空のまま
 *    (ローカル投稿・CloudKit 同期で埋まる)
 */
object SeedImporter {

    private const val ASSET = "master_seed.sqlite"
    private const val TAG = "SeedImporter"
    private val SKIP_TABLES = setOf("room_master_table", "android_metadata", "sqlite_sequence")

    /**
     * DB が空 (初回) で seed asset がある時だけ投入する。冪等。
     * 投入後にデータがあるか (UI を即表示してよいか) を返す。
     */
    suspend fun importIfNeeded(context: Context, db: AppDatabase): Boolean = withContext(Dispatchers.IO) {
        if (db.syncDao().brandCount() > 0) return@withContext true  // 既に投入済み
        if (!hasAsset(context)) {
            Log.i(TAG, "seed asset 無し → skip (CloudKit 同期にフォールバック)")
            return@withContext false
        }

        val tmp = File(context.cacheDir, "seed_import.sqlite")
        try {
            context.assets.open(ASSET).use { input ->
                tmp.outputStream().use { input.copyTo(it, bufferSize = 64 * 1024) }
            }
            val sdb = db.openHelper.writableDatabase
            // ATTACH/DETACH はトランザクション外で実行する必要がある。
            sdb.execSQL("ATTACH DATABASE ? AS seed", arrayOf(tmp.absolutePath))
            try {
                val tables = commonTables(sdb)
                sdb.beginTransaction()
                try {
                    for (t in tables) {
                        val cols = commonColumns(sdb, t)
                        if (cols.isEmpty()) continue
                        val colList = cols.joinToString(",") { "\"$it\"" }
                        sdb.execSQL(
                            "INSERT OR IGNORE INTO main.\"$t\" ($colList) " +
                                "SELECT $colList FROM seed.\"$t\""
                        )
                    }
                    sdb.setTransactionSuccessful()
                } finally {
                    sdb.endTransaction()
                }
                Log.i(TAG, "seed import 完了: ${tables.size} tables")
            } finally {
                sdb.execSQL("DETACH DATABASE seed")
            }
        } catch (e: Exception) {
            Log.e(TAG, "seed import 失敗 (CloudKit 同期にフォールバック)", e)
        } finally {
            tmp.delete()
        }
        db.syncDao().brandCount() > 0  // 投入後の状態を返す
    }

    private fun hasAsset(context: Context): Boolean =
        try {
            context.assets.list("")?.contains(ASSET) == true
        } catch (e: Exception) {
            false
        }

    /** main と seed の両方に存在するテーブル名 (Room 内部テーブルは除外)。 */
    private fun commonTables(db: SupportSQLiteDatabase): List<String> {
        val main = tableNames(db, null)
        val seed = tableNames(db, "seed")
        return main.intersect(seed).filterNot { it in SKIP_TABLES }.toList()
    }

    private fun tableNames(db: SupportSQLiteDatabase, schema: String?): Set<String> {
        val prefix = schema?.let { "$it." } ?: ""
        val out = mutableSetOf<String>()
        db.query("SELECT name FROM ${prefix}sqlite_master WHERE type='table'").use { c ->
            while (c.moveToNext()) out.add(c.getString(0))
        }
        return out
    }

    /** main の列順を保ったまま、seed にも存在する列だけ返す。 */
    private fun commonColumns(db: SupportSQLiteDatabase, table: String): List<String> {
        val seed = columnNames(db, "seed", table)
        return columnNames(db, null, table).filter { it in seed }
    }

    private fun columnNames(db: SupportSQLiteDatabase, schema: String?, table: String): List<String> {
        val prefix = schema?.let { "$it." } ?: ""
        val out = mutableListOf<String>()
        db.query("PRAGMA ${prefix}table_info(\"$table\")").use { c ->
            val idx = c.getColumnIndex("name")
            while (c.moveToNext()) out.add(c.getString(idx))
        }
        return out
    }
}
