package com.fugaif.imaslivedb.data.backup

import android.content.Context
import androidx.room.Room
import com.fugaif.imaslivedb.data.community.LocalPollVoteLog
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Expense
import com.fugaif.imaslivedb.data.model.PersonalTag
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.data.repository.ExpenseRepository
import com.fugaif.imaslivedb.data.repository.PersonalTagRepository
import com.fugaif.imaslivedb.data.repository.UserMarkRepository
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import uniffi.imas_core.ExpenseCategory

/**
 * バックアップの取り込みは、端末の DB に入れる分 (マーク・マイタグ・収支) を 1 トランザクションで入れる。
 */
@RunWith(RobolectricTestRunner::class)
class BackupImportTransactionTest {

    private val context: Context = RuntimeEnvironment.getApplication()
    private val opened = mutableListOf<AppDatabase>()

    @After
    fun tearDown() {
        opened.forEach { it.close() }
    }

    /**
     * 収支を入れるところで失敗したら、先に入れたマークとマイタグも残らない。
     * 一部の表だけ入った状態で止まると、取り込み直しても「もうある」分は飛ばされ、
     * 何が欠けたかが分からなくなる。失敗の原因が消えれば、取り込み直しで全部入る。
     */
    @Test
    fun failureWhileWritingExpensesLeavesNothingHalfImported() = runBlocking {
        val source = database("source.sqlite")
        val mark = UserMark(UserMark.IDOL, "idol_a", UserMark.FAVORITE, true, null, "2026-09-01T00:00:00Z")
        val tag = PersonalTag(PersonalTag.IDOL, "idol_a", "遠征", "2026-09-01T00:00:00Z")
        val expense = Expense.make("2026-09-01", ExpenseCategory.TICKET, 9800, null, null, null)
        source.userMarkDao().insertAll(listOf(mark))
        source.personalTagDao().insertAll(listOf(tag))
        source.expenseDao().insertAllIfAbsent(listOf(expense))
        val json = BackupExportImportService.buildEnvelopeJson(
            context, UserMarkRepository(source), LocalPollVoteLog(context),
            PersonalTagRepository(source), ExpenseRepository(source)
        )

        val target = database("target.sqlite")
        val failExpenses = "fail_expense_insert"
        target.openHelper.writableDatabase.execSQL(
            "CREATE TRIGGER $failExpenses BEFORE INSERT ON expenses BEGIN SELECT RAISE(ABORT, 'disk full'); END"
        )

        val failed = runCatching { import(json, target) }
        assertTrue("収支の書き込み失敗が伝わらない", failed.isFailure)
        assertEquals("マークだけ入った", emptyList<UserMark>(), UserMarkRepository(target).getAll())
        assertEquals("マイタグだけ入った", emptyList<PersonalTag>(), PersonalTagRepository(target).getAll())

        target.openHelper.writableDatabase.execSQL("DROP TRIGGER $failExpenses")
        val result = import(json, target)
        assertEquals(listOf(mark), UserMarkRepository(target).getAll())
        assertEquals(listOf(tag), PersonalTagRepository(target).getAll())
        assertEquals(listOf(expense), ExpenseRepository(target).getAll())
        assertEquals(1, result.addedMarks)
        assertEquals(1, result.addedPersonalTags)
        assertEquals(1, result.addedExpenses)
    }

    private suspend fun import(json: String, db: AppDatabase): BackupImportResult =
        BackupExportImportService.importEnvelopeJson(
            context, json, db, UserMarkRepository(db), LocalPollVoteLog(context),
            PersonalTagRepository(db), ExpenseRepository(db), restoreDeviceId = false
        )

    private fun database(name: String): AppDatabase =
        AppDatabase.configure(Room.databaseBuilder(context, AppDatabase::class.java, name))
            .allowMainThreadQueries()
            .build()
            .also { opened += it }
}
