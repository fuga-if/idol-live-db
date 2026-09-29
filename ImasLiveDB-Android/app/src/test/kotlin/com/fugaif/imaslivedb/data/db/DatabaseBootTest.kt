package com.fugaif.imaslivedb.data.db

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.room.Room
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.util.concurrent.atomic.AtomicInteger

/**
 * 起動時に DB を開く流れ ([DatabaseBoot])。開けなければ落とさずに復旧画面の状態にし、
 * 「もう一度試す」で開き直せる。
 */
@RunWith(RobolectricTestRunner::class)
class DatabaseBootTest {

    private val context: Context = RuntimeEnvironment.getApplication()

    /**
     * 本番と同じ Room の経路で開けない DB (アプリより新しい版で作られたもの = 移行が無い) を開くと、
     * 例外で落ちずに Failed になる。端末のファイルは消さない。
     */
    @Test
    fun unopenableDatabaseLeadsToRecoveryInsteadOfACrash() = runBlocking {
        val name = "newer.sqlite"
        val file = context.getDatabasePath(name).apply { parentFile?.mkdirs() }
        SQLiteDatabase.openOrCreateDatabase(file, null).use { it.version = 99 }

        val boot = DatabaseBoot {
            AppDatabase.configure(Room.databaseBuilder(context, AppDatabase::class.java, name))
                .allowMainThreadQueries()
                .build()
                .openHelper.writableDatabase
        }
        boot.prepare()

        val state = boot.state.value
        assertTrue("落ちずに復旧画面へ: $state", state is DatabaseBoot.State.Failed)
        assertTrue("詳細が空: $state", (state as DatabaseBoot.State.Failed).detail.isNotBlank())
        assertTrue("端末のファイルを消した", file.exists())
    }

    /** 失敗の後の「もう一度試す」で開き直し、開けたらそれ以上は開かない。 */
    @Test
    fun retryReopensAndReadyIsFinal() = runBlocking {
        val attempts = AtomicInteger()
        val boot = DatabaseBoot {
            if (attempts.incrementAndGet() == 1) throw IllegalStateException("disk I/O error")
        }

        boot.prepare()
        assertEquals(DatabaseBoot.State.Failed("disk I/O error"), boot.state.value)
        boot.prepare()
        assertEquals(DatabaseBoot.State.Ready, boot.state.value)
        boot.prepare()
        assertEquals(2, attempts.get())
    }

    /** 開いている途中にもう一度頼まれても、二重には開かない。 */
    @Test
    fun concurrentPrepareOpensOnce() = runBlocking {
        val attempts = AtomicInteger()
        val gate = CompletableDeferred<Unit>()
        val boot = DatabaseBoot {
            attempts.incrementAndGet()
            gate.await()
        }

        val first = async { boot.prepare() }
        val second = async { boot.prepare() }
        gate.complete(Unit)
        first.await()
        second.await()

        assertEquals(1, attempts.get())
        assertEquals(DatabaseBoot.State.Ready, boot.state.value)
    }
}
