package com.fugaif.imaslivedb.data.local

import android.content.Context
import androidx.room.Room
import com.fugaif.imaslivedb.data.backup.BackupExportImportService
import com.fugaif.imaslivedb.data.community.LocalPollVoteLog
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.repository.ExpenseRepository
import com.fugaif.imaslivedb.data.repository.PersonalTagRepository
import com.fugaif.imaslivedb.data.repository.PlaylistRepository
import com.fugaif.imaslivedb.data.repository.ProducerCardRepository
import com.fugaif.imaslivedb.data.repository.UserMarkRepository
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import uniffi.imas_core.BrandRole
import uniffi.imas_core.BrandRoleBrand
import uniffi.imas_core.BrandRoleRecord
import uniffi.imas_core.BrandRoleRow
import uniffi.imas_core.brandRoleFromIndex
import uniffi.imas_core.brandRoleSettings
import uniffi.imas_core.brandRoleSteps

/**
 * 担当ブランド (アプリ全体の設定) の保存とバックアップ。iOS `BrandRoleStoreTests` と対。
 * 段・既定・保存の形の規則はコアのテストが持つので、ここは端末の設定への読み書きとバックアップの経路だけを見る。
 */
@RunWith(RobolectricTestRunner::class)
class BrandRoleStoreTest {

    private val context: Context = RuntimeEnvironment.getApplication()
    private val opened = mutableListOf<AppDatabase>()

    @Before
    fun setUp() {
        context.getSharedPreferences("imas_settings", Context.MODE_PRIVATE).edit().clear().commit()
    }

    @After
    fun tearDown() {
        opened.forEach { it.close() }
    }

    private fun row(id: String, role: BrandRole) = BrandRoleRow(id, id, null, role)

    /** スライダーの段の番号と段は行って戻る (端は寄せる)。 */
    @Test
    fun stepIndexRoundTrips() {
        brandRoleSteps().forEach { assertEquals(it.role, brandRoleFromIndex(it.index.toLong())) }
        assertEquals(listOf("なし", "担当", "メイン"), brandRoleSteps().map { it.label })
        assertEquals(BrandRole.MAIN, brandRoleFromIndex(7))
    }

    @Test
    fun saveMarksConfiguredAndPrompted() {
        assertFalse(BrandRoleStore.isConfigured(context))
        assertTrue(BrandRoleStore.shouldPrompt(context))
        BrandRoleStore.save(context, listOf(row("765", BrandRole.MAIN), row("ml", BrandRole.MAIN), row("cg", BrandRole.OSHI), row("sc", BrandRole.NONE)))
        assertTrue(BrandRoleStore.isConfigured(context))
        assertFalse(BrandRoleStore.shouldPrompt(context))
        assertEquals(BrandRoleStore.json(context), BrandRoleStore.json.value)
        val record = BrandRoleRecord(
            today = "2026-10-06",
            brands = listOf("765", "cg", "ml", "sc").mapIndexed { i, id -> BrandRoleBrand(id, id, null, i.toLong()) },
            oshiBrandIds = emptyList(), visits = emptyList()
        )
        val settings = brandRoleSettings(BrandRoleStore.json(context), record)
        assertEquals("メインは複数", listOf(BrandRole.MAIN, BrandRole.OSHI, BrandRole.MAIN, BrandRole.NONE), settings.rows.map { it.role })

        // 飛ばしただけなら決めていない (既定のまま) が、もう案内しない。
        setUp()
        BrandRoleStore.markPrompted(context)
        assertFalse(BrandRoleStore.isConfigured(context))
        assertFalse(BrandRoleStore.shouldPrompt(context))
    }

    /** バックアップで運び、まだ決めていない端末にだけ戻す。 */
    @Test
    fun backupCarriesBrandRolesIntoAnUnsetDevice() = runBlocking {
        val db = AppDatabase.configure(Room.databaseBuilder(context, AppDatabase::class.java, "brand_roles.sqlite"))
            .allowMainThreadQueries().build().also { opened += it }
        BrandRoleStore.save(context, listOf(row("765", BrandRole.MAIN), row("cg", BrandRole.OSHI)))
        val json = BackupExportImportService.buildEnvelopeJson(
            context, UserMarkRepository(db), LocalPollVoteLog(context), PersonalTagRepository(db),
            ExpenseRepository(db), PlaylistRepository(db), ProducerCardRepository(db)
        )
        val exported = BrandRoleStore.json(context)

        setUp()
        import(json, db)
        assertEquals(exported, BrandRoleStore.json(context))

        // 端末で決め直していれば戻さない。
        BrandRoleStore.save(context, listOf(row("sc", BrandRole.MAIN)))
        val mine = BrandRoleStore.json(context)
        import(json, db)
        assertEquals(mine, BrandRoleStore.json(context))
    }

    private suspend fun import(json: String, db: AppDatabase) {
        BackupExportImportService.importEnvelopeJson(
            context, json, db, UserMarkRepository(db), LocalPollVoteLog(context),
            PersonalTagRepository(db), ExpenseRepository(db), PlaylistRepository(db),
            ProducerCardRepository(db), restoreDeviceId = false
        )
    }
}
