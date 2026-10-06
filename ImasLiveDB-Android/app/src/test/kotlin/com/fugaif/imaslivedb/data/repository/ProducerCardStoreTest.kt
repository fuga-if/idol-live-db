package com.fugaif.imaslivedb.data.repository

import android.content.Context
import androidx.room.Room
import com.fugaif.imaslivedb.data.backup.BackupExportImportService
import com.fugaif.imaslivedb.data.community.LocalPollVoteLog
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.model.ProducerCardField
import com.fugaif.imaslivedb.data.model.ReceivedProducerCard
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import uniffi.imas_core.CardLink
import uniffi.imas_core.CardLinkKind
import uniffi.imas_core.ProducerCardInput
import uniffi.imas_core.ProfileSheetSize
import uniffi.imas_core.ProfileSheetStyle
import uniffi.imas_core.encodeProducerCard
import uniffi.imas_core.producerCardPayload
import uniffi.imas_core.profileSheetDefault

/**
 * P名刺 (自分の名刺・名刺入れ) の端末 DB とバックアップの往復のテスト (iOS `ProducerCardStoreTests` と対)。
 *
 * 名刺は端末にしか無いので、復元は「無い行を足すだけ」で、既にある名刺のメモや
 * 書き直した自分の名刺を古いもので上書きしないこと。
 */
@RunWith(RobolectricTestRunner::class)
class ProducerCardStoreTest {

    private val context: Context = RuntimeEnvironment.getApplication()
    private val opened = mutableListOf<AppDatabase>()

    @After
    fun tearDown() {
        opened.forEach { it.close() }
    }

    private fun database(name: String = "cards.sqlite"): AppDatabase =
        AppDatabase.configure(Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java))
            .allowMainThreadQueries()
            .build()
            .also { opened += it }

    /** コアで組んだ本物の名刺の中身。 */
    private fun payload(name: String): String {
        val input = ProducerCardInput(
            name = name, message = "", sinceYear = 2014u, oshiIdolIds = listOf("765_haruka"),
            links = listOf(CardLink(CardLinkKind.X, "fuga_p")), showCount = 3u, songCount = 10u,
            nextShowId = null, attended = emptyList(), issuedOn = "2026-10-06"
        )
        return producerCardPayload(encodeProducerCard(input).card)
    }

    private fun received(id: String, name: String, memo: String? = null) = ReceivedProducerCard(
        id = id, payload = payload(name), source = "app", showId = "sh_1", showDate = "2026-10-05",
        memo = memo, receivedAt = "2026-10-05T21:00:00Z", updatedAt = "2026-10-05T21:00:00Z"
    )

    private fun myCard(name: String) = MyProducerCard.empty().copy(name = name)

    @Test
    fun myCardRoundTripsLinksAndHiddenFields() = runBlocking {
        val repo = ProducerCardRepository(database())
        assertNull(repo.myCard())
        val links = listOf(CardLink(CardLinkKind.X, "fuga_p"), CardLink(CardLinkKind.BLUESKY, "fuga.bsky.social"))
        val card = myCard("ふがP").copy(sinceYear = 2014)
            .withLinks(links)
            .withHidden(setOf(ProducerCardField.ATTENDED, ProducerCardField.SONG_COUNT))
        repo.saveMyCard(card)

        val loaded = repo.myCard()!!
        assertEquals("ふがP", loaded.name)
        assertEquals(links, loaded.links)
        assertEquals(setOf(ProducerCardField.ATTENDED, ProducerCardField.SONG_COUNT), loaded.hidden)
        assertEquals("iOS と同じ保存のキー", "song_count,attended", loaded.hiddenFields)
        assertTrue(loaded.shows(ProducerCardField.OSHI))
        assertFalse(loaded.shows(ProducerCardField.ATTENDED))
    }

    /** プロフィール帳は自分の名刺の行に持つ。まだ作っていなければ既定の中身 (規則はコア)。 */
    @Test
    fun profileSheetRoundTripsOnMyCard() = runBlocking {
        val repo = ProducerCardRepository(database())
        val card = myCard("ふがP")
        assertEquals(profileSheetDefault(), card.profile)
        val sheet = card.profile.copy(
            size = ProfileSheetSize.STORY, furigana = "ふがぴー",
            favoriteSongIds = listOf("s1"), brandOn = listOf("sc")
        )
        repo.saveMyCard(card.withProfile(sheet))
        assertEquals(sheet, repo.myCard()?.profile)

        // P名刺を直して保存しても、プロフィール帳は消えない。
        repo.saveMyCard(repo.myCard()!!.copy(message = "現地派"))
        assertEquals(sheet, repo.myCard()?.profile)
    }

    @Test
    fun receivedCardsSaveFindByPayloadAndDelete() = runBlocking {
        val repo = ProducerCardRepository(database())
        val a = received("c1", "しろくまP")
        repo.saveReceived(a)
        repo.saveReceived(received("c2", "あおいP"))

        assertEquals(2, repo.receivedCards().size)
        val found = repo.receivedCardByPayload(a.payload)
        assertEquals("c1", found?.id)
        assertEquals("しろくまP", found?.card?.name)

        repo.saveReceived(a.copy(memo = "物販列で隣"))
        assertEquals("同じ id は上書き", 2, repo.receivedCards().size)
        assertEquals("物販列で隣", repo.receivedCard("c1")?.memo)

        repo.deleteReceived("c1")
        assertEquals(listOf("c2"), repo.receivedIds())
        assertEquals(1, repo.receivedCount())
    }

    @Test
    fun restoreAddsOnlyMissingCardsAndKeepsMyCard() = runBlocking {
        val repo = ProducerCardRepository(database())
        repo.saveReceived(received("c1", "しろくまP", memo = "新しいメモ"))
        val added = repo.restoreReceivedIfAbsent(
            listOf(received("c1", "しろくまP", memo = "古いメモ"), received("c2", "あおいP"))
        )
        assertEquals(1, added)
        assertEquals("既にある名刺のメモを古いもので上書きしない", "新しいメモ", repo.receivedCard("c1")?.memo)

        repo.saveMyCard(myCard("書き直した名前"))
        assertEquals(0, repo.restoreMyCardIfAbsent(listOf(myCard("古い名前"))))
        assertEquals("書き直した名前", repo.myCard()?.name)
    }

    /** 同じ相手の名刺 (中身が同じ) は、別の id で届いても 1 枚にする。 */
    @Test
    fun samePayloadIsNotStoredTwice() = runBlocking {
        val repo = ProducerCardRepository(database())
        val first = repo.insertReceivedIfNew(received("c1", "しろくまP"))
        val second = repo.insertReceivedIfNew(received("c2", "しろくまP"))
        assertEquals("c1", first.id)
        assertEquals("同じ中身なら既にある名刺を返す", "c1", second.id)
        assertEquals(0, repo.restoreReceivedIfAbsent(listOf(received("c3", "しろくまP"))))
        assertEquals(listOf("c1"), repo.receivedIds())
    }

    /** 書き出したバックアップを空の端末に取り込むと、名刺入れと自分の名刺が戻る。 */
    @Test
    fun backupRoundTripRestoresProducerCards() = runBlocking {
        val source = database()
        val sourceRepo = ProducerCardRepository(source)
        val default = profileSheetDefault()
        val sheet = default.copy(
            style = ProfileSheetStyle.CAREER,
            answers = default.answers.mapIndexed { i, a -> if (i == 0) a.copy(text = "アニメで見て") else a }
        )
        val mine = myCard("ふがP").copy(message = "現地派", sinceYear = 2014)
            .withLinks(listOf(CardLink(CardLinkKind.X, "fuga_p")))
            .withHidden(setOf(ProducerCardField.ATTENDED))
            .withProfile(sheet)
        sourceRepo.saveMyCard(mine)
        sourceRepo.saveReceived(received("c1", "しろくまP", memo = "物販列で隣"))
        val json = BackupExportImportService.buildEnvelopeJson(
            context, UserMarkRepository(source), LocalPollVoteLog(context),
            PersonalTagRepository(source), ExpenseRepository(source), PlaylistRepository(source), sourceRepo
        )

        val target = database()
        val targetRepo = ProducerCardRepository(target)
        suspend fun import() = BackupExportImportService.importEnvelopeJson(
            context, json, target, UserMarkRepository(target), LocalPollVoteLog(context),
            PersonalTagRepository(target), ExpenseRepository(target), PlaylistRepository(target),
            targetRepo, restoreDeviceId = false
        )
        assertEquals(1, import().addedProducerCards)
        val card = targetRepo.receivedCards().single()
        assertEquals("c1", card.id)
        assertEquals("物販列で隣", card.memo)
        assertEquals("しろくまP", card.card?.name)
        val restored = targetRepo.myCard()!!
        assertEquals("ふがP", restored.name)
        assertEquals(2014, restored.sinceYear)
        assertEquals(mine.links, restored.links)
        assertEquals(setOf(ProducerCardField.ATTENDED), restored.hidden)
        assertEquals("プロフィール帳もバックアップで戻る", sheet, restored.profile)

        // 2 回目は何も増えない (id で重複を弾く)。
        assertEquals(0, import().addedProducerCards)
        assertEquals(1, targetRepo.receivedCount())
    }
}
