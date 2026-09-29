package com.fugaif.imaslivedb.data.repository

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
 * 編集で曲を選ぶピッカーの母集団 ([SongRepository.fetchSongsForPicker])。
 *
 * セトリの編集ではどの曲でも選べる必要がある (コアの `allSongsForPicker` のとおり)。
 * Android は曲一覧と同じ絞り込み (派生曲・その他ブランドを隠す) で母集団を作っていたので、
 * リミックスや別バージョンをセトリに入れられなかった。
 */
@RunWith(RobolectricTestRunner::class)
class SongPickerSourceTest {

    private lateinit var seeded: SeededDatabase
    private lateinit var repository: SongRepository

    @Before
    fun setUp() {
        seeded = SeededDatabase(RuntimeEnvironment.getApplication())
        repository = SongRepository(seeded.db, seeded.snapshots)
    }

    @After
    fun tearDown() {
        seeded.close()
    }

    @Test
    fun pickerOffersEverySongIncludingVariants() = runBlocking {
        val picked = repository.fetchSongsForPicker().map { it.id }
        val db = seeded.db.openHelper.readableDatabase
        val all = db.query("SELECT COUNT(*) FROM songs").use { it.moveToFirst(); it.getInt(0) }
        val variants = db.query("SELECT id FROM songs WHERE parent_song_id IS NOT NULL AND parent_song_id != ''").use { c ->
            buildList { while (c.moveToNext()) add(c.getString(0)) }
        }

        assertEquals(all, picked.size)
        assertTrue("派生曲が 1 件も無い seed では確かめられない", variants.isNotEmpty())
        assertTrue("選べない派生曲がある", picked.containsAll(variants))
    }
}
