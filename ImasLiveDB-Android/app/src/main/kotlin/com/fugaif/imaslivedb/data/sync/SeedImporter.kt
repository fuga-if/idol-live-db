package com.fugaif.imaslivedb.data.sync

import android.content.Context
import android.util.Log
import androidx.sqlite.db.SupportSQLiteDatabase
import com.fugaif.imaslivedb.data.db.AppDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.reseedCommonColumns
import uniffi.imas_core.reseedMasterTargetTables
import uniffi.imas_core.reseedNeeded
import uniffi.imas_core.reseedParseDataVersion
import uniffi.imas_core.reseedSummaryLabel
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
 * seed を ATTACH して行だけをコピーする。移すのは **コアの台帳にあるマスタ表のうち、
 * Room と seed の両方にあるもの** (reseed と同じ allow-list。[reseedMasterTargetTables]) の、
 * 両方に共通する列だけ ([reseedCommonColumns])。
 *  - song_units 等 (seed 側のみ / Room エンティティ無し) → 移す先が無いので落ちる
 *  - user_marks / personal_tags / expenses / song_videos (台帳に無い) → 触らない
 *    (端末にしかないデータ・CloudKit 同期で埋まるもの)
 *  - meta は台帳から除かれる。初回投入では seed の行をそのまま入れ、入れ直しでは
 *    data_version と content_hash だけを書き換える (iOS の reseed と同じ)。
 *
 * 初回投入 ([importIfNeeded]) と、アプリ更新時の入れ直し ([reseedIfNeeded]) は同じ規則で動く。
 * どちらも 1 トランザクションで、途中で失敗すれば端末の DB は元のまま。
 */
object SeedImporter {

    private const val ASSET = "master_seed.sqlite"
    private const val TAG = "SeedImporter"
    private const val PREFS_NAME = "imas_seed"
    /** reseed の判定を済ませたアプリ更新 (PackageInfo.lastUpdateTime)。 */
    private const val KEY_CHECKED_UPDATE = "reseed_checked_update_time"
    /** 入れ直しに失敗した回数と、それがどの更新でのことか。 */
    private const val KEY_FAILED_UPDATE = "reseed_failed_update_time"
    private const val KEY_FAILED_COUNT = "reseed_failed_count"
    /** 同じ更新で入れ直しに失敗し続けたら、この回数で諦める (毎起動で seed を複製し続けない)。 */
    private const val MAX_RESEED_ATTEMPTS = 3

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
        try {
            withSeedFile(context) { seedPath -> copyMasterTables(db, seedPath, replace = false) }
            lastImportError = null
            // 入れたばかりの seed は同梱のものそのものなので、この更新での入れ直しの判定は要らない
            // (判定のために seed をもう一度複製して ATTACH しない)。
            packageUpdateTime(context)?.let { markChecked(prefs(context), it) }
        } catch (e: Exception) {
            Log.e(TAG, "seed import 失敗 (CloudKit 同期にフォールバック)", e)
            lastImportError = "初期データの読み込みに失敗しました。アプリを再起動しても直らない場合は再インストールをお試しください。\n(詳細: ${e.message})"
        }
        db.syncDao().brandCount() > 0  // 投入後の状態を返す
    }

    /**
     * 同梱の seed が端末のマスタより新しければ、マスタ表を seed で入れ直す (iOS の reseed と同じ)。
     * 入れ直したら true。
     *
     * CloudKit で物理削除された行 (過剰に付いた歌唱者・削除済みのキャストなど) は、差分同期では
     * 端末に届かず、孤児の掃除も単一 PK の表しか見ない。アプリを更新したときに同梱の seed で
     * 入れ直すことで、複合 PK の表の余剰行もまとめて消える。
     *
     * - 入れ直すかどうか・どの表を入れ直すか・どの列を移すかはコアが決める
     *   (reseedNeeded / reseedMasterTargetTables の allow-list / reseedCommonColumns)。
     *   端末にしかない表 (user_marks / personal_tags / expenses) と song_videos は台帳に無いので触らない。
     * - seed が変わるのはアプリの更新のときだけなので、判定は更新ごとに 1 回だけ行う
     *   (seed の複製と meta の読み出しを毎起動にしない)。
     * - 入れ直した後は、seed を作った時点より後の変更を取り直すため、呼び出し側で次の同期をフルにする。
     */
    suspend fun reseedIfNeeded(context: Context, db: AppDatabase): Boolean =
        reseedIfNeeded(context, db) { seedPath -> reseedFrom(db, seedPath) }

    /** [reseed] を差し替えられる入口 (テスト用)。本番は [reseedFrom]。 */
    internal suspend fun reseedIfNeeded(
        context: Context,
        db: AppDatabase,
        reseed: (String) -> Boolean
    ): Boolean = withContext(Dispatchers.IO) {
        val updatedAt = packageUpdateTime(context)
        val prefs = prefs(context)
        if (updatedAt != null && prefs.contains(KEY_CHECKED_UPDATE) && prefs.getLong(KEY_CHECKED_UPDATE, 0L) == updatedAt) {
            return@withContext false
        }
        if (!hasAsset(context) || db.syncDao().brandCount() == 0) return@withContext false
        val reseeded = try {
            withSeedFile(context, reseed)
        } catch (e: Exception) {
            // 失敗しても端末のマスタはトランザクションで元のまま。判定済みの印は付けず、次の起動で
            // もう一度試す (同時に走る Room の読み取りと ATTACH が当たるなど、一時的な失敗がある)。
            // 同じ更新で失敗し続けるときは上限の回数で諦める (差分同期と 24h のフル同期が残りを埋める)。
            Log.e(TAG, "reseed 失敗 (端末のマスタはそのまま)", e)
            if (updatedAt != null) recordFailure(prefs, updatedAt)
            return@withContext false
        }
        if (updatedAt != null) markChecked(prefs, updatedAt)
        reseeded
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun markChecked(prefs: android.content.SharedPreferences, updatedAt: Long) {
        prefs.edit().putLong(KEY_CHECKED_UPDATE, updatedAt).remove(KEY_FAILED_UPDATE).remove(KEY_FAILED_COUNT).apply()
    }

    private fun recordFailure(prefs: android.content.SharedPreferences, updatedAt: Long) {
        val sameUpdate = prefs.contains(KEY_FAILED_UPDATE) && prefs.getLong(KEY_FAILED_UPDATE, 0L) == updatedAt
        val failures = (if (sameUpdate) prefs.getInt(KEY_FAILED_COUNT, 0) else 0) + 1
        if (failures >= MAX_RESEED_ATTEMPTS) {
            markChecked(prefs, updatedAt)
        } else {
            prefs.edit().putLong(KEY_FAILED_UPDATE, updatedAt).putInt(KEY_FAILED_COUNT, failures).apply()
        }
    }

    /** [seedPath] の seed が新しければ入れ直す。判定とコピーの本体 (テストはここを直接呼ぶ)。 */
    internal fun reseedFrom(db: AppDatabase, seedPath: String): Boolean {
        val sdb = db.openHelper.writableDatabase
        val local = readMeta(sdb, null)
        val bundle = attached(sdb, seedPath) { readMeta(sdb, "seed") }
        if (!reseedNeeded(bundle.version, local.version, bundle.contentHash, local.contentHash)) return false
        val copied = copyMasterTables(db, seedPath, replace = true)
        Log.i(TAG, "reseed ${reseedSummaryLabel(local.version, bundle.version, copied.toUInt(), 0u)}")
        return true
    }

    /**
     * seed を ATTACH して、コアの台帳にあるマスタ表を 1 トランザクションで移す。移した表の数を返す。
     *
     * @param replace true = 入れ直し (全表を DELETE してから全表を INSERT する 2 段。iOS と同じ順で、
     *   ON DELETE CASCADE による再削除を避ける)。meta は data_version と content_hash だけ書き換える。
     *   false = 空の DB への初回投入 (INSERT OR IGNORE。meta は seed の行をそのまま入れる)。
     */
    private fun copyMasterTables(db: AppDatabase, seedPath: String, replace: Boolean): Int {
        val sdb = db.openHelper.writableDatabase
        return attached(sdb, seedPath) {
            val tables = reseedMasterTargetTables(tableNames(sdb, "seed"), tableNames(sdb, null))
            sdb.beginTransaction()
            try {
                if (replace) tables.forEach { sdb.execSQL("DELETE FROM main.\"$it\"") }
                var copied = 0
                for (t in tables) {
                    val cols = reseedCommonColumns(columnNames(sdb, "seed", t), columnNames(sdb, null, t))
                    if (cols.isEmpty()) continue
                    val colList = cols.joinToString(",") { "\"$it\"" }
                    val verb = if (replace) "INSERT" else "INSERT OR IGNORE"
                    sdb.execSQL("$verb INTO main.\"$t\" ($colList) SELECT $colList FROM seed.\"$t\"")
                    copied++
                }
                if (replace) {
                    sdb.execSQL(
                        "INSERT OR REPLACE INTO main.meta (key, value) " +
                            "SELECT key, value FROM seed.meta WHERE key IN ('data_version', 'content_hash')"
                    )
                } else {
                    sdb.execSQL("INSERT OR IGNORE INTO main.meta (key, value) SELECT key, value FROM seed.meta")
                }
                sdb.setTransactionSuccessful()
                Log.i(TAG, "seed ${if (replace) "reseed" else "import"} 完了: $copied tables")
                copied
            } finally {
                sdb.endTransaction()
            }
        }
    }

    private class SeedMeta(val version: Long, val contentHash: String?)

    private fun readMeta(db: SupportSQLiteDatabase, schema: String?): SeedMeta {
        val prefix = schema?.let { "$it." } ?: ""
        fun value(key: String): String? =
            db.query("SELECT value FROM ${prefix}meta WHERE key = ?", arrayOf(key)).use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        return SeedMeta(reseedParseDataVersion(value("data_version")), value("content_hash"))
    }

    /** ATTACH / DETACH はトランザクションの外で行う必要がある。 */
    private fun <T> attached(db: SupportSQLiteDatabase, seedPath: String, block: () -> T): T {
        db.execSQL("ATTACH DATABASE ? AS seed", arrayOf(seedPath))
        try {
            return block()
        } finally {
            db.execSQL("DETACH DATABASE seed")
        }
    }

    /** asset の seed を一時ファイルに複製して渡す (SQLite は asset を直接開けない)。 */
    private fun <T> withSeedFile(context: Context, block: (String) -> T): T {
        val tmp = File(context.cacheDir, "seed_import.sqlite")
        try {
            context.assets.open(ASSET).use { input ->
                tmp.outputStream().use { input.copyTo(it, bufferSize = 64 * 1024) }
            }
            return block(tmp.absolutePath)
        } finally {
            tmp.delete()
        }
    }

    private fun packageUpdateTime(context: Context): Long? = try {
        context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime
    } catch (e: Exception) {
        null
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
