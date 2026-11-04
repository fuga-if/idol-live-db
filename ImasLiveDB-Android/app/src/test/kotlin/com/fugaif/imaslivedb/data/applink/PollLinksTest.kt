package com.fugaif.imaslivedb.data.applink

import android.content.Intent
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** お題の共有 URL を Intent から拾う (読み方の規則はコア。ここは受け口の形だけ確かめる)。 */
@RunWith(RobolectricTestRunner::class)
class PollLinksTest {
    private fun view(url: String) = Intent(Intent.ACTION_VIEW, Uri.parse(url))

    @Test
    fun 公開サイトの共有URLはお題の画面() {
        assertEquals(
            PollLink.Detail("27384517-a77f-4d30-b654-84d08b79e105"),
            PollLinks.parse(view("https://idollivedb.fugaapp.site/polls/#poll-27384517-a77f-4d30-b654-84d08b79e105"))
        )
    }

    @Test
    fun 旧い共有URLとアプリのスキームも受ける() {
        assertEquals(PollLink.Detail("p@1"), PollLinks.parse(view("https://imas-live-api.tokata3011.workers.dev/app/polls/p%401")))
        assertEquals(PollLink.Detail("p1"), PollLinks.parse(view("imaslivedb://polls/p1")))
    }

    @Test
    fun 節を指さない一覧はお題の一覧() {
        assertEquals(PollLink.List, PollLinks.parse(view("https://idollivedb.fugaapp.site/polls/")))
    }

    @Test
    fun お題でないものは拾わない() {
        assertNull(PollLinks.parse(view("https://idollivedb.fugaapp.site/p/#abc")))
        assertNull(PollLinks.parse(Intent(Intent.ACTION_SEND)))
        assertNull(PollLinks.parse(null))
    }
}
