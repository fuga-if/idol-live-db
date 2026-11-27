package com.fugaif.imaslivedb.data.applink

import android.content.Intent
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** 公演・イベントのリンクを Intent から拾う (iOS DeeplinkRouter と同じ形)。 */
@RunWith(RobolectricTestRunner::class)
class DetailLinksTest {
    private fun view(url: String) = Intent(Intent.ACTION_VIEW, Uri.parse(url))

    @Test
    fun アプリのスキームは公演とイベント() {
        assertEquals(DetailLink.Show("sh_x_01"), DetailLinks.parse(view("imaslivedb://shows/sh_x_01")))
        assertEquals(DetailLink.Event("ev_x"), DetailLinks.parse(view("imaslivedb://events/ev_x")))
    }

    @Test
    fun 共有リンクはidをデコードして受ける() {
        assertEquals(
            DetailLink.Show("sh_あ_01"),
            DetailLinks.parse(view("https://imas-live-api.tokata3011.workers.dev/app/shows/sh_%E3%81%82_01"))
        )
        assertEquals(
            DetailLink.Event("ev_x"),
            DetailLinks.parse(view("https://imas-live-api.tokata3011.workers.dev/app/events/ev_x"))
        )
    }

    @Test
    fun 公演とイベントでないものは拾わない() {
        assertNull(DetailLinks.parse(view("imaslivedb://polls/p1")))
        assertNull(DetailLinks.parse(view("imaslivedb://shows/")))
        assertNull(DetailLinks.parse(view("imaslivedb://shows/a/b")))
        assertNull(DetailLinks.parse(view("https://imas-live-api.tokata3011.workers.dev/app/polls/p1")))
        assertNull(DetailLinks.parse(view("https://example.com/app/shows/sh_x_01")))
        assertNull(DetailLinks.parse(Intent(Intent.ACTION_SEND)))
        assertNull(DetailLinks.parse(null))
    }
}
