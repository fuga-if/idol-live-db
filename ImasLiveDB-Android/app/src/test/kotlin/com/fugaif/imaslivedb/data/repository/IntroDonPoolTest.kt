package com.fugaif.imaslivedb.data.repository

import androidx.room.Room
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.sync.CloudKitSyncEngine
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * イントロドンの出題プール ([SongRepository.fetchIntroDonSongs])。
 *
 * 出題できるかはコア (`introQuizPlayableIndices`) の規則で決まり、Android は常に
 * Apple Music の契約なし (preview_url が唯一の音源) として渡す。ここで見るのは
 * 「未契約の端末で、鳴らせない曲がプールに入らない」ことと、ブランドの絞り込みが効くこと。
 */
@RunWith(RobolectricTestRunner::class)
class IntroDonPoolTest {

    private lateinit var db: AppDatabase
    private lateinit var repository: SongRepository

    @Before
    fun setUp() {
        val context = RuntimeEnvironment.getApplication()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        // 出題プールはスナップショットを読まない (候補の読み出しと規則だけ)。
        repository = SongRepository(db, SnapshotStoreProvider(context, CloudKitSyncEngine(context, db)))
    }

    @After
    fun tearDown() {
        db.close()
    }

    @Test
    fun poolHoldsOnlySongsWithAPreview() = runBlocking {
        db.syncDao().upsertSongs(
            listOf(
                song("preview", previewUrl = "https://example.com/p.m4a"),
                // 配信 ID だけの曲は、契約の無い端末では無音で出題されてしまう。
                song("catalog_only", appleMusicId = "123"),
                song("empty_preview", previewUrl = "", appleMusicId = "456"),
                // 派生曲は選択肢に同名の別バージョンが並ぶので出さない。
                song("remix", previewUrl = "https://example.com/r.m4a", parentSongId = "preview"),
                // 親が空文字なのは派生曲ではない (コアの規則。旧 SQL は `IS NULL` で落としていた)。
                song("blank_parent", previewUrl = "https://example.com/b.m4a", parentSongId = ""),
            )
        )

        assertEquals(setOf("preview", "blank_parent"), repository.fetchIntroDonSongs().map { it.id }.toSet())
    }

    @Test
    fun brandSelectionNarrowsThePool() = runBlocking {
        db.syncDao().upsertSongs(
            listOf(
                song("ml_song", brandId = "ml", previewUrl = "https://example.com/1.m4a"),
                song("sc_song", brandId = "sc", previewUrl = "https://example.com/2.m4a"),
                song("cg_song", brandId = "cg", previewUrl = "https://example.com/3.m4a"),
            )
        )

        assertEquals(setOf("ml_song", "sc_song"), repository.fetchIntroDonSongs(setOf("ml", "sc")).map { it.id }.toSet())
        assertEquals(3, repository.fetchIntroDonSongs().size)
    }

    private fun song(
        id: String,
        brandId: String = "765as",
        previewUrl: String? = null,
        appleMusicId: String? = null,
        parentSongId: String? = null
    ) = Song(
        id = id, title = "title-$id", titleKana = null, brandId = brandId, songType = "solo",
        releaseDate = null, durationSec = null, composer = null, lyricist = null, arranger = null,
        cdSeries = null, cdTitle = null, artworkUrl = null, previewUrl = previewUrl,
        appleMusicId = appleMusicId, appleMusicAlbumId = null, isrc = null, lyricsUrl = null,
        parentSongId = parentSongId, singerLabel = null, unitName = null, unitId = null
    )
}
