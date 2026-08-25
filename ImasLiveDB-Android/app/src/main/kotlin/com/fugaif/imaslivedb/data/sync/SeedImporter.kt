package com.fugaif.imaslivedb.data.sync

import android.content.Context
import android.util.Log
import androidx.sqlite.db.SupportSQLiteDatabase
import com.fugaif.imaslivedb.data.db.AppDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.seedCommonColumns
import uniffi.imas_core.seedCommonTables
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
 *
 * **どのテーブル・どの列を移すか**の規則は共有コア (`domain::sync_planning`) が持つ
 * ([seedCommonTables] / [seedCommonColumns])。ここは sqlite_master / PRAGMA を引いて
 * 名前の配列を渡し、返ってきた対象に対して SQL を撃つだけ。列順は main 側の順序で返るので
 * `INSERT (cols) SELECT (cols)` の左右が必ず揃う。
 */
object SeedImporter {

    private const val ASSET = "master_seed.sqlite"
    private const val TAG = "SeedImporter"

    /**
     * 直近の import 失敗のユーザー可視メッセージ (成功時/未実行時は null)。
     * iOS AppDatabase.lastReseedFailure 相当。CloudKit token 未設定 + seed import 失敗の
     * 組み合わせだと、旧実装では Log.e だけで握り潰され、UI は「データを準備中…」のまま
     * 無限に待たされていた (MainActivity の hasData が false のまま state も進まない)。
     * @Volatile: importIfNeeded は Dispatchers.IO、読み手は Main スレッド。
     */
    @Volatile var lastImportError: String? = null
        private set

    /**
     * DB が空 (初回) で seed asset がある時だけ投入する。冪等。
     * 投入後にデータがあるか (UI を即表示してよいか) を返す。
     */
    suspend fun importIfNeeded(context: Context, db: AppDatabase): Boolean = withContext(Dispatchers.IO) {
        if (db.syncDao().brandCount() > 0) {
            lastImportError = null
            return@withContext true  // 既に投入済み
        }
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
                val tables = seedCommonTables(tableNames(sdb, null), tableNames(sdb, "seed"))
                sdb.beginTransaction()
                try {
                    for (t in tables) {
                        val cols = seedCommonColumns(columnNames(sdb, null, t), columnNames(sdb, "seed", t))
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
                lastImportError = null
            } finally {
                sdb.execSQL("DETACH DATABASE seed")
            }
        } catch (e: Exception) {
            Log.e(TAG, "seed import 失敗 (CloudKit 同期にフォールバック)", e)
            lastImportError = "初期データの読み込みに失敗しました。アプリを再起動しても直らない場合は再インストールをお試しください。\n(詳細: ${e.message})"
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

    /** sqlite_master に並んでいる順のテーブル名 (絞り込みはコアの seedCommonTables が行う)。 */
    private fun tableNames(db: SupportSQLiteDatabase, schema: String?): List<String> {
        val prefix = schema?.let { "$it." } ?: ""
        val out = mutableListOf<String>()
        db.query("SELECT name FROM ${prefix}sqlite_master WHERE type='table'").use { c ->
            while (c.moveToNext()) out.add(c.getString(0))
        }
        return out
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
