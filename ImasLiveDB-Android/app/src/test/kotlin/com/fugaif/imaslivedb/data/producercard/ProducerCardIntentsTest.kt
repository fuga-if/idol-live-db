package com.fugaif.imaslivedb.data.producercard

import android.content.Context
import android.content.Intent
import android.net.Uri
import java.io.ByteArrayInputStream
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import uniffi.imas_core.CardLink
import uniffi.imas_core.CardLinkKind
import uniffi.imas_core.ProducerCardInput
import uniffi.imas_core.encodeCardFile
import uniffi.imas_core.encodeProducerCard
import uniffi.imas_core.producerCardPayload
import uniffi.imas_core.producerCardUrlFromPayload

/**
 * 名刺のリンク・名刺ファイルの判定はコアの規則で、Intent から拾える (iOS `testDeeplinkParsesCardUrlsAndFiles` と対)。
 */
@RunWith(RobolectricTestRunner::class)
class ProducerCardIntentsTest {

    private val context: Context = RuntimeEnvironment.getApplication()

    private fun payload(name: String): String {
        val input = ProducerCardInput(
            name = name, message = "", sinceYear = 2014u, oshiIdolIds = listOf("765_haruka"),
            links = listOf(CardLink(CardLinkKind.X, "fuga_p")), showCount = 3u, songCount = 10u,
            nextShowId = null, attended = emptyList(), issuedOn = "2026-10-06"
        )
        return producerCardPayload(encodeProducerCard(input).card)
    }

    private fun view(url: String) = Intent(Intent.ACTION_VIEW, Uri.parse(url))

    @Test
    fun parsesCardUrls() {
        val p = payload("ふがP")
        assertEquals(ProducerCardIntent.Card(p), ProducerCardIntents.parse(view(producerCardUrlFromPayload(p))))
        assertEquals(ProducerCardIntent.Card(p), ProducerCardIntents.parse(view("imaslivedb://p#$p")))
        assertNull("名刺でない URL は拾わない", ProducerCardIntents.parse(view("https://idollivedb.fugaapp.site/events/")))
        assertNull(ProducerCardIntents.parse(Intent(Intent.ACTION_MAIN)))
        assertNull(ProducerCardIntents.parse(null))
    }

    @Test
    fun parsesCardFiles() {
        val uri = Uri.parse("content://com.example.files/ふがPのP名刺.imascard")
        assertEquals(ProducerCardIntent.File(uri), ProducerCardIntents.parse(view(uri.toString())))
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/vnd.imaslivedb.card"
            putExtra(Intent.EXTRA_STREAM, uri)
        }
        assertEquals(ProducerCardIntent.File(uri), ProducerCardIntents.parse(send))
    }

    /** 名刺ファイルを開くと中身 (# の後ろ) が戻る。名刺ファイルでなければ null。 */
    @Test
    fun readsCardFileContents() = runBlocking {
        val p = payload("しろくまP")
        val file = File(context.cacheDir, "card.imascard").apply { writeBytes(encodeCardFile(p, emptyList())!!) }
        assertEquals(p, ProducerCardIntents.readCardFile(context, Uri.fromFile(file))?.payload)
        val junk = File(context.cacheDir, "junk.imascard").apply { writeText("not a card") }
        assertNull(ProducerCardIntents.readCardFile(context, Uri.fromFile(junk)))
    }

    @Test
    fun readBoundedStopsAtTheLimit() {
        assertEquals(10, ProducerCardIntents.readBounded(ByteArrayInputStream(ByteArray(10)), limit = 10)?.size)
        assertNull(ProducerCardIntents.readBounded(ByteArrayInputStream(ByteArray(11)), limit = 10))
    }
}
