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
import android.graphics.Bitmap
import com.fugaif.imaslivedb.data.producercard.ProducerCardAssembler
import com.fugaif.imaslivedb.data.producercard.ProducerCardFiles
import com.fugaif.imaslivedb.data.producercard.ProducerCardMyRecord
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCardDesign
import com.fugaif.imaslivedb.ui.producercard.ProducerCardDisplay
import com.fugaif.imaslivedb.ui.producercard.ProducerCardFace
import uniffi.imas_core.CardDesign
import uniffi.imas_core.CardFileImageKind
import uniffi.imas_core.CardLink
import uniffi.imas_core.XAvatarLookup
import uniffi.imas_core.cardDesigns
import uniffi.imas_core.cardXAvatarHandle
import uniffi.imas_core.decodeCardFile
import uniffi.imas_core.decodeProducerCard
import uniffi.imas_core.xAvatarLookup
import uniffi.imas_core.xAvatarLookupMessage
import uniffi.imas_core.xProfileApiUrl
import uniffi.imas_core.CardLinkKind
import uniffi.imas_core.ProducerCardInput
import uniffi.imas_core.ProfileAutoField
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
            size = ProfileSheetSize.STORY, hidden = listOf(ProfileAutoField.QR),
            brandOn = listOf("sc"), brandMain = "sc"
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
        val sheet = default.copy(style = ProfileSheetStyle.CAREER, brandOff = listOf("ml"))
        val mine = myCard("ふがP").copy(message = "現地派", sinceYear = 2014)
            .withLinks(listOf(CardLink(CardLinkKind.X, "fuga_p")))
            .withHidden(setOf(ProducerCardField.ATTENDED))
            .withProfile(sheet)
            .withCardDesign(CardDesign.FORMAL)
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
        assertEquals("デザインもバックアップで戻る", CardDesign.FORMAL, restored.cardDesign)

        // 2 回目は何も増えない (id で重複を弾く)。
        assertEquals(0, import().addedProducerCards)
        assertEquals(1, targetRepo.receivedCount())
    }

    // ---- デザイン・自作の画像・X のアイコン (iOS ProducerCardStoreTests と対) ----

    /** デザインは端末の表に入り、名刺の中身にも載る。デザインを選んでいなければ既定。 */
    @Test
    fun myCardDesignReachesTheCard() = runBlocking {
        val repo = ProducerCardRepository(database())
        val mine = myCard("ふがP")
        assertEquals("空のキーは既定のデザイン", cardDesigns().first().design, mine.cardDesign)
        repo.saveMyCard(mine.withCardDesign(CardDesign.POP))
        val loaded = repo.myCard()!!
        assertEquals("pop", loaded.design)
        val record = ProducerCardMyRecord(emptyList(), emptyList(), 0)
        val encoded = ProducerCardAssembler.encode(loaded, record)!!
        val back = decodeProducerCard(encoded.url)!!
        assertEquals(CardDesign.POP, back.design)
        assertEquals("card_name_pop", ProducerCardDisplay.nameFont(back))
    }

    /** 書体を選んでいた頃の保存のキーは、近いデザインに読み替える。 */
    @Test
    fun oldFontKeysReadAsNearestDesign() {
        val cases = listOf(
            "gothic" to CardDesign.PASS, "mincho" to CardDesign.FORMAL, "maru" to CardDesign.POP,
            "hand" to CardDesign.POP, "pop" to CardDesign.POP, "" to CardDesign.PASS, "unknown" to CardDesign.PASS
        )
        for ((key, design) in cases) assertEquals(key, design, myCard("ふがP").copy(design = key).cardDesign)
    }

    /** 自作の画像の名刺は、画像が手元にあれば画像で、無ければ (QR だけで受け取った) 入場証で描く。 */
    @Test
    fun customDesignNeedsFaceImage() {
        val card = encodeProducerCard(
            ProducerCardInput(
                name = "しろくまP", message = "", sinceYear = null, oshiIdolIds = emptyList(), links = emptyList(),
                showCount = null, songCount = null, nextShowId = null, attended = emptyList(),
                issuedOn = "2026-10-06", design = CardDesign.CUSTOM
            )
        ).card
        val face = ProducerCardFace(front = "file:///tmp/front.jpg", back = null)
        assertEquals(ImasProducerCardDesign.Face("file:///tmp/front.jpg", null), ProducerCardDisplay.cardDesign(card, face))
        assertEquals(ImasProducerCardDesign.Pass, ProducerCardDisplay.cardDesign(card, null))
    }

    /** 自分の名刺ファイルには、デザインが自作の画像のときだけ表・裏の画像が入る。 */
    @Test
    fun myCardFileCarriesFacesOnlyForCustomDesign() = runBlocking {
        val image = Bitmap.createBitmap(91, 55, Bitmap.Config.ARGB_8888)
        try {
            ProducerCardFiles.saveMyFace(context, image, ProducerCardFiles.Side.FRONT)
            ProducerCardFiles.saveMyFace(context, image, ProducerCardFiles.Side.BACK)
            val module = AppModule.from(context)
            val record = ProducerCardMyRecord(emptyList(), emptyList(), 0)
            fun faces(bytes: ByteArray) = decodeCardFile(bytes)!!.images.map { it.kind }.filter { it != CardFileImageKind.PHOTO }

            val custom = ProducerCardAssembler.encode(myCard("ふがP").withCardDesign(CardDesign.CUSTOM), record)!!
            assertEquals(
                listOf(CardFileImageKind.FACE_FRONT, CardFileImageKind.FACE_BACK),
                faces(ProducerCardAssembler.myCardFile(context, module, custom)!!)
            )
            val formal = ProducerCardAssembler.encode(myCard("ふがP").withCardDesign(CardDesign.FORMAL), record)!!
            assertTrue(faces(ProducerCardAssembler.myCardFile(context, module, formal)!!).isEmpty())
        } finally {
            ProducerCardFiles.deleteMyFace(context, ProducerCardFiles.Side.FRONT)
            ProducerCardFiles.deleteMyFace(context, ProducerCardFiles.Side.BACK)
        }
    }

    /** X のアイコンの規則 (ID の取り出し・読みに行く先・返事の分け方) はコア。 */
    @Test
    fun xAvatarRulesComeFromCore() {
        assertEquals(
            "fuga_p",
            cardXAvatarHandle(listOf(CardLink(CardLinkKind.BLUESKY, "a.bsky.social"), CardLink(CardLinkKind.X, "fuga_p")))
        )
        assertNull(cardXAvatarHandle(listOf(CardLink(CardLinkKind.BLUESKY, "a.bsky.social"))))
        assertTrue(xProfileApiUrl("fuga_p") != null)
        assertEquals(XAvatarLookup.NotFound, xAvatarLookup("fuga_p", 404.toUShort(), ""))
        assertTrue(xAvatarLookupMessage(XAvatarLookup.Protected, "fuga_p") != null)
    }
}
