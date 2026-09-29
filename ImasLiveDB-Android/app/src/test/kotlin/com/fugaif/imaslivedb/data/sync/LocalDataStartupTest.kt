package com.fugaif.imaslivedb.data.sync

import androidx.room.Room
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.db.AppDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * 起動時、seed を入れる前に誰かがスナップショットを読んでいても、最初の画面には
 * 投入後のマスタが出る (RedTeam A-M3)。
 */
@RunWith(RobolectricTestRunner::class)
class LocalDataStartupTest {

    private val context = RuntimeEnvironment.getApplication()
    private lateinit var db: AppDatabase

    @Before
    fun setUp() {
        db = AppDatabase.configure(Room.databaseBuilder(context, AppDatabase::class.java, "master.sqlite"))
            .allowMainThreadQueries()
            .build()
    }

    @After
    fun tearDown() = db.close()

    @Test
    fun theFirstScreenSeesTheSeedEvenIfSomeoneReadTheEmptySnapshotFirst() = runBlocking {
        val sync = CloudKitSyncEngine(context, db)
        val snapshots = SnapshotStoreProvider(context, sync)
        db.syncDao().brandCount() // DB のファイルを作る
        // seed を入れる前に読んだ人がいる (通知の積み直しなど): 空のスナップショットが読み込み済みになる。
        assertTrue(snapshots.loadedStore().brandRecords().isEmpty())

        val store = checkNotNull(LocalDataStartup.prepare(sync, snapshots))

        assertTrue("最初の画面が空のスナップショットを見ている", store.brandRecords().isNotEmpty())
    }
}
