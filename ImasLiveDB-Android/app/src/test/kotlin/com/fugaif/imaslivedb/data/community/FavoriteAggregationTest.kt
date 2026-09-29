package com.fugaif.imaslivedb.data.community

import android.content.Context
import androidx.room.Room
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.data.repository.UserMarkRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.CoroutineScope
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/** 曲のお気に入りをみんなの集計に送る ([FavoriteAggregation])。iOS と同じ振る舞い。 */
@RunWith(RobolectricTestRunner::class)
class FavoriteAggregationTest {

    private val context: Context = RuntimeEnvironment.getApplication()

    /** 付け外しは曲のお気に入りだけを送る (他の種別・他のマークは送らない)。 */
    @Test
    fun onlySongFavoritesAreReported() = runBlocking {
        val reported = mutableListOf<Pair<String, Boolean>>()
        val db = AppDatabase.configure(Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java))
            .allowMainThreadQueries().build()
        val marks = UserMarkRepository(db) { id, value -> reported += id to value }

        marks.toggle(UserMark.SONG, "s1", UserMark.FAVORITE)
        marks.toggle(UserMark.IDOL, "i1", UserMark.FAVORITE)
        marks.toggle(UserMark.SONG, "s1", UserMark.PICK)
        marks.toggle(UserMark.SONG, "s1", UserMark.FAVORITE)
        db.close()

        assertEquals(listOf("s1" to true, "s1" to false), reported)
    }

    /**
     * 送れなかったものは積んでおき、前面に出たときに送り直す。同じ曲は最後の値だけ。
     * 3 回失敗したら諦める (規則は imas-core の pending_favorites)。
     */
    @Test
    fun failedReportsAreRetriedUpToThreeTimes() = runBlocking {
        var online = false
        val sent = mutableListOf<Pair<String, Boolean>>()
        val aggregation = FavoriteAggregation(context, CoroutineScope(Dispatchers.Unconfined), sleep = {}) { id, value ->
            if (!online && id == "s1") error("offline")
            if (!online && id == "s2") error("offline")
            sent += id to value
        }

        aggregation.report("s1", true)
        aggregation.report("s1", false)
        aggregation.report("s2", true)
        assertEquals(emptyList<Pair<String, Boolean>>(), sent)

        online = true
        aggregation.flushPending()
        assertEquals(listOf("s1" to false, "s2" to true), sent)
        aggregation.flushPending()
        assertEquals("送り直しは 1 回だけ", 2, sent.size)

        online = false
        aggregation.report("s1", true)
        repeat(3) { aggregation.flushPending() }
        online = true
        aggregation.flushPending()
        assertEquals("3 回失敗したら諦める", 2, sent.size)
    }

    /**
     * 送れずに積んだ (A, true) の後で (A, false) を送れたら、積み残しの (A, true) は捨てる。
     * 残っていると、前面に出たときに古い true を送り直して集計が戻る (RedTeam A-L2)。
     */
    @Test
    fun aSuccessfulReportDropsTheStalePendingValue() = runBlocking {
        var online = false
        val sent = mutableListOf<Pair<String, Boolean>>()
        val aggregation = FavoriteAggregation(context, CoroutineScope(Dispatchers.Unconfined), sleep = {}) { id, value ->
            if (!online) error("offline")
            sent += id to value
        }

        aggregation.report("stale", true)
        online = true
        aggregation.report("stale", false)
        aggregation.flushPending()

        assertEquals("古い値を送り直した", listOf("stale" to false), sent)
    }
}
