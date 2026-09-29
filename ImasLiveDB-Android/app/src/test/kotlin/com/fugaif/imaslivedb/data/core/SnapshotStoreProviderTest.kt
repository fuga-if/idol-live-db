package com.fugaif.imaslivedb.data.core

import android.content.Context
import androidx.room.Room
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.sync.CloudKitSyncEngine
import com.fugaif.imaslivedb.data.sync.SeedImporter
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * マスタの読み取りはスナップショットだけが答える ([SnapshotStoreProvider])。
 * まだ読み込めていない間の読み取りは読み込みを待ち、読み込めなければ投げて、次の読み取りで読み直す。
 */
@RunWith(RobolectricTestRunner::class)
class SnapshotStoreProviderTest {

    private val context: Context = RuntimeEnvironment.getApplication()

    @Test
    fun firstQueryLoadsTheSnapshot() = runBlocking {
        val db = database()
        try {
            assertTrue(SeedImporter.importIfNeeded(context, db))
            val provider = SnapshotStoreProvider(context, CloudKitSyncEngine(context, db))

            // 前もって読み込みを頼まなくても、最初の読み取りが読み込んでから答える。
            val brands = provider.query { store -> store.brandRecords() }

            assertEquals(db.brandDao().fetchBrands().map { it.id }.toSet(), brands.map { it.id }.toSet())
        } finally {
            db.close()
        }
    }

    @Test
    fun queryThrowsUntilTheDatabaseExistsThenLoads() = runBlocking {
        val memory = AppDatabase.configure(Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)).build()
        val provider = SnapshotStoreProvider(context, CloudKitSyncEngine(context, memory))

        // DB のファイルがまだ無い (初回起動で seed を入れる前)。
        val failed = runCatching { provider.query { store -> store.brandRecords() } }
        assertTrue("読めないのに答えた: $failed", failed.exceptionOrNull() is SnapshotUnavailableException)

        val db = database()
        try {
            assertTrue(SeedImporter.importIfNeeded(context, db))
            assertTrue(provider.query { store -> store.brandRecords() }.isNotEmpty())
        } finally {
            db.close()
            memory.close()
        }
    }

    /** スナップショットが読むのと同じ名前の DB (Robolectric の実行ごとに別のディレクトリ)。 */
    private fun database(): AppDatabase =
        AppDatabase.configure(Room.databaseBuilder(context, AppDatabase::class.java, "master.sqlite"))
            .allowMainThreadQueries()
            .build()
}
