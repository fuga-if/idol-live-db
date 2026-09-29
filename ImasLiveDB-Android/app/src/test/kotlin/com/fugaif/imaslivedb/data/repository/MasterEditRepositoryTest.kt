package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.model.SetlistPerformer
import com.fugaif.imaslivedb.testing.SeededDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * 編集の反映 ([MasterEditRepository]) は、書いた直後からスナップショット経由の読み取りにも見える。
 */
@RunWith(RobolectricTestRunner::class)
class MasterEditRepositoryTest {

    private lateinit var seeded: SeededDatabase
    private lateinit var events: EventRepository
    private lateinit var edits: MasterEditRepository

    @Before
    fun setUp() {
        seeded = SeededDatabase(RuntimeEnvironment.getApplication())
        events = EventRepository(seeded.db, seeded.snapshots)
        edits = MasterEditRepository(seeded.db, seeded.snapshots)
    }

    @After
    fun tearDown() {
        seeded.close()
    }

    @Test
    fun replacedSetlistIsVisibleThroughTheSnapshotRightAway() = runBlocking {
        val showId = seeded.db.openHelper.readableDatabase
            .query("SELECT si.show_id FROM setlist_items si JOIN setlist_performers sp ON sp.setlist_item_id = si.id LIMIT 1")
            .use { it.moveToFirst(); it.getString(0) }
        val before = events.fetchPerformersByItem(showId)
        val (itemId, performers) = before.entries.first { it.value.isNotEmpty() }
        val removed = performers.first().idolId!!

        edits.replaceSetlist(
            deletedItemIds = emptyList(),
            deletedPerformers = listOf(itemId to removed),
            items = emptyList(),
            performers = emptyList()
        )

        val after = events.fetchPerformersByItem(showId)[itemId].orEmpty().map { it.idolId }
        assertTrue("消した歌唱者がスナップショットに残った", removed !in after)
        assertEquals(performers.size - 1, after.size)

        edits.replaceSetlist(emptyList(), emptyList(), emptyList(), listOf(SetlistPerformer(itemId, removed)))
        assertTrue(removed in events.fetchPerformersByItem(showId)[itemId].orEmpty().map { it.idolId })
    }
}
