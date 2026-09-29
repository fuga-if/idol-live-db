package com.fugaif.imaslivedb.ui.settings

import android.app.Application
import android.net.Uri
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.room.Room
import com.fugaif.imaslivedb.data.backup.BackupExportImportService
import com.fugaif.imaslivedb.data.community.LocalPollVoteLog
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.data.repository.ExpenseRepository
import com.fugaif.imaslivedb.data.repository.PersonalTagRepository
import com.fugaif.imaslivedb.data.repository.UserMarkRepository
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import uniffi.imas_core.backupImportSummary
import java.io.File

/**
 * 設定の引き継ぎ欄 ([BackupViewModel])。取り込みは画面ではなくアプリのスコープで走る。
 */
@RunWith(RobolectricTestRunner::class)
class BackupViewModelTest {

    private val app: Application = RuntimeEnvironment.getApplication()

    /**
     * ファイルからの取り込みを始めた直後に画面 (ViewModel) が破棄されても、取り込みは最後まで入る。
     * 画面のスコープで走らせていた頃は、画面を離れたり回したりすると途中で止まっていた。
     */
    @Test
    fun importFinishesEvenAfterTheScreenGoesAway() = runBlocking {
        val mark = UserMark(UserMark.IDOL, "idol_backup_vm_test", UserMark.PICK, true, null, "2026-09-01T00:00:00Z")
        val file = File(app.cacheDir, "backup.json").apply { writeText(backupJsonOf(mark)) }
        val marks = AppModule.from(app).userMarkRepository

        val store = ViewModelStore()
        val viewModel = ViewModelProvider(store, ViewModelProvider.AndroidViewModelFactory.getInstance(app))[
            BackupViewModel::class.java
        ]
        viewModel.importFrom(Uri.fromFile(file), restoreDeviceId = false)
        store.clear()

        // AppModule はプロセスで 1 つなので、他のテストが入れたマークも同じ DB に居る。
        // 自分のマークが入ったかだけを見る。
        withTimeout(10_000) {
            while (mark !in marks.getAll()) delay(20)
        }
    }

    /** 復元の結果は、コアの文面 (入ったものだけを並べる。iOS と同じ) で出す。 */
    @Test
    fun restoreSummaryIsTheCoreText() = runBlocking {
        val mark = UserMark(UserMark.IDOL, "idol_backup_summary_test", UserMark.FAVORITE, true, null, "2026-09-01T00:00:00Z")
        val file = File(app.cacheDir, "summary.json").apply { writeText(backupJsonOf(mark)) }
        val viewModel = ViewModelProvider(ViewModelStore(), ViewModelProvider.AndroidViewModelFactory.getInstance(app))[
            BackupViewModel::class.java
        ]

        viewModel.importFrom(Uri.fromFile(file), restoreDeviceId = false)
        val summary = withTimeout(10_000) {
            var s: String? = null
            while (s == null) {
                s = viewModel.uiState.value.importSummary
                if (s == null) delay(20)
            }
            s
        }

        assertEquals(backupImportSummary(1, 0, 0, 0, 0, false), summary)
    }

    /** [mark] だけを持つ端末から書き出したバックアップ。 */
    private suspend fun backupJsonOf(mark: UserMark): String {
        val source = AppDatabase.configure(Room.databaseBuilder(app, AppDatabase::class.java, "source.sqlite"))
            .allowMainThreadQueries()
            .build()
        return try {
            source.userMarkDao().insertAll(listOf(mark))
            BackupExportImportService.buildEnvelopeJson(
                app, UserMarkRepository(source), LocalPollVoteLog(app),
                PersonalTagRepository(source), ExpenseRepository(source)
            )
        } finally {
            source.close()
        }
    }
}
