package com.fugaif.imaslivedb.data.local

import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** 端末ローカルの書き込み失敗は握りつぶさず、知らせに流す (iOS LocalWriteFailureTests と同じ)。 */
@RunWith(RobolectricTestRunner::class)
class LocalWriteFailureTest {

    @Test
    fun failureIsReportedAndReturnsNull() = runBlocking {
        val notice = async { LocalWriteFailure.notices.first() }
        yield()
        val result = localWrite<Int>("メモの保存") { throw IllegalStateException("disk full") }
        assertNull(result)
        assertEquals(LocalWriteFailure.notice("メモの保存"), notice.await())
    }

    @Test
    fun successPassesTheValueThrough() = runBlocking {
        assertEquals(3, localWrite("メモの保存") { 3 })
    }
}
