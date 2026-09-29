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

    private fun engine(source: CloudKitRecordSource) =
        CloudKitSyncEngine(context, db, source, scope, dao, isConfigured = { true })

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

    private fun brandRecord(id: String) =
        """{"recordName":"$id","recordType":"Brand","fields":{"name":{"value":"ブランド","type":"STRING"},"shortName":{"value":"B","type":"STRING"}}}"""

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
