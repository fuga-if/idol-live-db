package com.fugaif.imaslivedb.data.sync

import android.content.Context
import androidx.room.Room
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.db.dao.SyncDao
import com.fugaif.imaslivedb.data.model.Brand
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * [CloudKitSyncEngine] の実行の仕方 (単一実行・取り消し・大量削除)。CloudKit はフェイクに差し替える。
 */
@RunWith(RobolectricTestRunner::class)
class CloudKitSyncEngineTest {

    private lateinit var context: Context
    private lateinit var db: AppDatabase
    private lateinit var dao: RecordingSyncDao
    private lateinit var scope: CoroutineScope

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        // 前のテストの同期の起点を持ち越さない。
        context.getSharedPreferences("imas_sync", Context.MODE_PRIVATE).edit().clear().commit()
        db = AppDatabase.configure(Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java))
            .allowMainThreadQueries()
            .build()
        dao = RecordingSyncDao(db.syncDao())
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    }

    @After
    fun tearDown() {
        scope.cancel()
        db.close()
    }

    private fun engine(
        manifest: suspend () -> String? = { null },
        digests: suspend () -> String? = { null },
        source: CloudKitRecordSource,
    ) = CloudKitSyncEngine(
        context, db, source, scope, dao, isConfigured = { true }, manifestSource = manifest, digestSource = digests
    )

    /** 同時に 2 回頼まれても、取得は 1 回。2 回目は実行中の同期を共有する。 */
    @Test
    fun concurrentRequestsShareOneRun() = runBlocking {
        val gate = CompletableDeferred<Unit>()
        val calls = ConcurrentHashMap<String, AtomicInteger>()
        val engine = engine { recordType, _ ->
            calls.getOrPut(recordType) { AtomicInteger() }.incrementAndGet()
            gate.await()
            emptyList()
        }

        val first = engine.requestSync()
        val second = engine.requestSync()
        gate.complete(Unit)
        withTimeout(10_000) { first.await(); second.await() }

        assertSame(first, second)
        assertTrue(calls.isNotEmpty())
        assertTrue("2 回取りに行った: $calls", calls.values.all { it.get() == 1 })
        assertTrue(engine.state.value is CloudKitSyncEngine.SyncState.Completed)
    }

    /** 取り消された同期は Error にならない (別の実行が出した結果を上書きしない)。 */
    @Test
    fun cancellationIsNotAnError() = runBlocking {
        val started = CompletableDeferred<Unit>()
        val engine = engine { _, _ ->
            started.complete(Unit)
            awaitCancellation()
        }

        val run = engine.requestSync()
        withTimeout(10_000) { started.await() }
        run.cancel()
        run.join()

        assertTrue("取り消しが Error になった: ${engine.state.value}",
            engine.state.value !is CloudKitSyncEngine.SyncState.Error)
    }

    /**
     * seed の投入を頼んだ画面が途中で消えても (回転など)、投入の後処理 (入れ替わった知らせ) まで
     * 走り切る (RedTeam A-L1)。
     */
    @Test
    fun seedImportFinishesEvenIfTheCallerGoesAway() = runBlocking {
        val engine = engine { _, _ -> emptyList() }
        val replaced = scope.async { engine.localDataReplaced.first() }
        yield()

        val caller = launch(Dispatchers.IO) { engine.ensureLocalData() }
        delay(50)
        caller.cancel()

        withTimeout(30_000) { replaced.await() }
        assertTrue(engine.hasData())
    }

    /**
     * 全件取り直しの後の孤児の掃除が数千件でも完了し、1 回の DELETE に渡す ID は
     * バインド変数の上限 (Android 11 以前の SQLite は 999) を超えない。
     */
    @Test
    fun thousandsOfOrphansAreDeletedInChunks() = runBlocking {
        db.syncDao().upsertBrands((0..2000).map { Brand("b$it", "ブランド$it", "B$it", null, it) })
        val engine = engine { recordType, _ ->
            if (recordType == "Brand") listOf(brandRecord("b0")) else emptyList()
        }

        withTimeout(30_000) { engine.requestSync().await() }

        assertTrue("同期が完了しない: ${engine.state.value}", engine.state.value is CloudKitSyncEngine.SyncState.Completed)
        assertEquals(listOf("b0"), db.syncDao().brandIds())
        assertTrue("1 回で ${dao.maxBrandDeleteBatch} 件消そうとした", dao.maxBrandDeleteBatch in 1..900)
    }

    /**
     * 起動側の同期は、前のフル同期から 24h を過ぎたら (記録が無ければすぐ) epoch から全件を取り直す
     * (iOS と同じ間隔。孤児の掃除もフルでだけ走る)。設定画面の全データ同期は 24h のタイマーを進めない。
     */
    @Test
    fun startupSyncFallsBackToFullEvery24Hours() = runBlocking {
        db.syncDao().upsertBrands(listOf(Brand("b0", "ブランド", "B", null, 0)))
        val prefs = context.getSharedPreferences("imas_sync", Context.MODE_PRIVATE)
        val hourAgo = System.currentTimeMillis() - 3_600_000L
        prefs.edit().putLong("last_sync_ms", hourAgo).commit()
        val brandSince = mutableListOf<Long>()
        val engine = engine { recordType, since ->
            if (recordType == "Brand") brandSince += since
            if (recordType == "Brand") listOf(brandRecord("b0")) else emptyList()
        }
        suspend fun run(full: Boolean = false) = withTimeout(30_000) {
            (if (full) engine.requestFullSync() else engine.requestSync()).await()
        }

        run()   // フル同期の記録が無い → フル
        run()   // 直後 → 差分
        prefs.edit().putLong("last_full_sync_ms", System.currentTimeMillis() - 25 * 3_600_000L).commit()
        run()   // 25h 前 → フル
        assertEquals(0L, brandSince[0])
        assertTrue("差分にならない: $brandSince", brandSince[1] > 0L)
        assertEquals(0L, brandSince[2])

        prefs.edit().remove("last_full_sync_ms").commit()
        run(full = true)
        assertTrue("全データ同期が 24h のタイマーを進めた", !prefs.contains("last_full_sync_ms"))
    }

    /**
     * 起動時の差分は目録を先に読み、動いていない型は問い合わせない。保存する同期の起点は
     * 端末の今ではなく、目録が見ていた時点より手前 (目録にまだ載っていない変更を飛び越えない)。
     * 人が頼んだ差分は目録を読まず、全部の型を問い合わせる。
     */
    @Test
    fun automaticSyncSkipsTypesTheManifestSaysAreUnchanged() = runBlocking {
        db.syncDao().upsertBrands(listOf(Brand("b0", "ブランド", "B", null, 0)))
        val prefs = context.getSharedPreferences("imas_sync", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val since = now - 3_600_000L
        prefs.edit().putLong("last_sync_ms", since).putLong("last_full_sync_ms", now).commit()
        val asked = java.util.Collections.synchronizedList(mutableListOf<String>())
        var manifestReads = 0
        val generatedAt = System.currentTimeMillis()
        val engine = engine(
            source = { recordType, _ -> asked += recordType; emptyList() },
            manifest = {
                manifestReads++
                // Song だけが前回の同期より後に動いた。Brand は古い。ほかは目録に載っていない。
                """{"generatedAt":$generatedAt,"types":{"Brand":${since - 1000},"Song":${since + 1000}}}"""
            }
        )

        withTimeout(30_000) { engine.requestSync(automatic = true).await() }
        assertEquals(1, manifestReads)
        assertTrue("動いていない Brand を問い合わせた: $asked", "Brand" !in asked)
        assertTrue("動いた Song を問い合わせていない: $asked", "Song" in asked)
        assertTrue("目録に無い型を省いた: $asked", "Idol" in asked)
        val saved = prefs.getLong("last_sync_ms", 0L)
        assertTrue("同期の起点が目録の時刻より先に進んだ: $saved", saved < generatedAt)
        assertTrue("同期の起点が進んでいない: $saved", saved > since)

        asked.clear()
        withTimeout(30_000) { engine.requestSync().await() }
        assertEquals("人が頼んだ差分で目録を読んだ", 1, manifestReads)
        assertTrue("人が頼んだ差分で Brand を省いた: $asked", "Brand" in asked)
    }

    /**
     * 何も取り込まなかった同期は「マスタは動いていない」と言う (スナップショットを全部読み直さない)。
     * 1 件でも取り込めば動いたと言う。
     */
    @Test
    fun completedSaysWhetherTheMasterChanged() = runBlocking {
        db.syncDao().upsertBrands(listOf(Brand("b0", "ブランド", "B", null, 0)))
        val prefs = context.getSharedPreferences("imas_sync", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        prefs.edit().putLong("last_sync_ms", now - 3_600_000L).putLong("last_full_sync_ms", now).commit()

        val quiet = engine(source = { _, _ -> emptyList() })
        withTimeout(30_000) { quiet.requestSync().await() }
        val idle = quiet.state.value as CloudKitSyncEngine.SyncState.Completed
        assertEquals(0, idle.fetched)
        assertTrue("何も取り込んでいないのに動いたと言った", !idle.masterChanged)

        val busy = engine(source = { recordType, _ ->
            if (recordType == "Brand") listOf(brandRecord("b1")) else emptyList()
        })
        withTimeout(30_000) { busy.requestSync().await() }
        val changed = busy.state.value as CloudKitSyncEngine.SyncState.Completed
        assertTrue("取り込んだのに動いていないと言った", changed.masterChanged)
    }

    /**
     * フル同期は、単一 PK の型 (孤児掃除が要る) を毎回 epoch から取り直す。複合 PK の型は
     * 一度 epoch から取り切ったら、次からは取り込んだ最大の modifiedAt の少し手前から取り、
     * 目録で動いていないと分かれば問い合わせない。全データ同期は続き位置を捨てて全部 epoch から。
     */
    @Test
    fun fullSyncResumesCompositeTypesFromTheirCursor() = runBlocking {
        db.syncDao().upsertBrands(listOf(Brand("b0", "ブランド", "B", null, 0)))
        val prefs = context.getSharedPreferences("imas_sync", Context.MODE_PRIVATE)
        val modifiedAt = System.currentTimeMillis() - 86_400_000L
        val since = java.util.concurrent.ConcurrentHashMap<String, MutableList<Long>>()
        var manifest: String? = null
        val engine = engine(manifest = { manifest }) { recordType, sinceMs ->
            since.getOrPut(recordType) { java.util.Collections.synchronizedList(mutableListOf()) } += sinceMs
            when (recordType) {
                "Brand" -> listOf(brandRecord("b0"))
                "IdolBrand" -> if (sinceMs == 0L) listOf(
                    """{"recordName":"idol_brands-i0-b0","recordType":"IdolBrand","fields":{"idolId":{"value":"i0","type":"STRING"},"brandId":{"value":"b0","type":"STRING"},"deletedAt":{"value":$modifiedAt,"type":"TIMESTAMP"},"modifiedAt":{"value":$modifiedAt,"type":"TIMESTAMP"}}}"""
                ) else emptyList()
                else -> emptyList()
            }
        }
        suspend fun fullRun(manual: Boolean = false) = withTimeout(30_000) {
            prefs.edit().remove("last_full_sync_ms").commit()   // フルの時期が来たことにする
            (if (manual) engine.requestFullSync() else engine.requestSync(automatic = true)).await()
        }

        fullRun()   // 1 回目: 続き位置が無い → 全部 epoch から
        assertEquals(listOf(0L), since["IdolBrand"]?.toList())
        assertEquals(modifiedAt, prefs.getLong("type_cursor_ms_IdolBrand", 0L))

        fullRun()   // 2 回目: 複合 PK は続き位置の 10 分手前から、単一 PK はまた epoch から
        assertEquals(listOf(0L, modifiedAt - 600_000L), since["IdolBrand"]?.toList())
        assertEquals(listOf(0L, 0L), since["Brand"]?.toList())

        // 3 回目: 目録が「IdolBrand は続き位置から動いていない」と言う → 問い合わせない
        manifest = """{"generatedAt":${System.currentTimeMillis()},"types":{"IdolBrand":$modifiedAt,"Brand":$modifiedAt}}"""
        fullRun()
        assertEquals("動いていない複合 PK の型を問い合わせた", 2, since["IdolBrand"]?.size)
        assertEquals("単一 PK の型を省いた (孤児掃除ができない)", 3, since["Brand"]?.size)

        fullRun(manual = true)   // 全データ同期: 続き位置を捨てて epoch から
        assertEquals(0L, since["IdolBrand"]?.last())
    }

    /**
     * 単一 PK の型は、手元の ID 一覧がサーバのダイジェストと一致したときだけ全件取得を省き、
     * 続き位置から取る。食い違えば (サーバで行が消えた等) 全件を取り直して孤児を消す。
     */
    @Test
    fun fullSyncSkipsSinglePkTypesWhoseIdsMatchTheServerDigest() = runBlocking {
        db.syncDao().upsertBrands(listOf(Brand("b0", "ブランド", "B", null, 0), Brand("b1", "ブランド", "B", null, 1)))
        val prefs = context.getSharedPreferences("imas_sync", Context.MODE_PRIVATE)
        val modifiedAt = System.currentTimeMillis() - 86_400_000L
        val brandSince = java.util.Collections.synchronizedList(mutableListOf<Long>())
        var serverIds = listOf("b0", "b1")
        val engine = engine(
            digests = { """{"generated_at":"x","digests":{"Brand":"${uniffi.imas_core.syncIdsDigest(serverIds)}"}}""" }
        ) { recordType, sinceMs ->
            if (recordType != "Brand") return@engine emptyList()
            brandSince += sinceMs
            if (sinceMs == 0L) serverIds.map { brandRecord(it, modifiedAt) } else emptyList()
        }
        suspend fun fullRun() = withTimeout(30_000) {
            prefs.edit().remove("last_full_sync_ms").commit()
            engine.requestSync(automatic = true).await()
        }

        fullRun()   // 1 回目: 続き位置が無い → epoch から
        fullRun()   // 2 回目: ID が一致 → 続き位置の 10 分手前から
        assertEquals(listOf(0L, modifiedAt - 600_000L), brandSince.toList())

        serverIds = listOf("b0")   // サーバで b1 が物理削除された
        fullRun()   // 食い違い → epoch から取り直し、孤児を消す
        assertEquals(0L, brandSince.last())
        assertEquals(listOf("b0"), db.syncDao().brandIds())
    }

    private fun brandRecord(id: String, modifiedAt: Long? = null) =
        """{"recordName":"$id","recordType":"Brand","fields":{"name":{"value":"ブランド","type":"STRING"},"shortName":{"value":"B","type":"STRING"}${modifiedAt?.let { ""","modifiedAt":{"value":$it,"type":"TIMESTAMP"}""" } ?: ""}}}"""

    /** ブランドの DELETE に渡された ID の数の最大を記録する。 */
    class RecordingSyncDao(private val real: SyncDao) : SyncDao by real {
        @Volatile var maxBrandDeleteBatch = 0
            private set

        override suspend fun deleteBrands(ids: List<String>) {
            maxBrandDeleteBatch = maxOf(maxBrandDeleteBatch, ids.size)
            real.deleteBrands(ids)
        }
    }
}
