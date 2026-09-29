package com.fugaif.imaslivedb.data.sync

import org.junit.Assert.assertEquals
import org.junit.Test
import uniffi.imas_core.CkRow
import uniffi.imas_core.CkSongRow

/**
 * [SyncMappers.songs] の単体テスト。
 *
 * CloudKit の行 → Room の [com.fugaif.imaslivedb.data.model.Song] へ写す変換は、
 * 列を追加したのに読み忘れると同期のたびに NULL/false で上書きされる
 * (`SyncMappers.kt` の songs() コメント参照)。isCollab / hasKamisabiCard のような
 * 真偽値の列は「読んでいること」を固定しておかないと、コアを先に直しても
 * サイレントに巻き戻る事故が起きやすいのでここで契約にする。
 */
class SyncMappersSongTest {

    @Test fun readsIsCollabFlag() {
        val rows = listOf(
            CkRow.Song(baseSongRow(id = "s1", isCollab = true, hasKamisabiCard = false)),
            CkRow.Song(baseSongRow(id = "s2", isCollab = false, hasKamisabiCard = false))
        )

        val songs = SyncMappers.songs(rows).associateBy { it.id }

        assertEquals(true, songs.getValue("s1").isCollab)
        assertEquals(false, songs.getValue("s2").isCollab)
    }

    @Test fun readsHasKamisabiCardFlag() {
        val rows = listOf(
            CkRow.Song(baseSongRow(id = "s1", isCollab = false, hasKamisabiCard = true)),
            CkRow.Song(baseSongRow(id = "s2", isCollab = false, hasKamisabiCard = false))
        )

        val songs = SyncMappers.songs(rows).associateBy { it.id }

        assertEquals(true, songs.getValue("s1").hasKamisabiCard)
        assertEquals(false, songs.getValue("s2").hasKamisabiCard)
    }

    @Test fun readsNote() {
        val rows = listOf(
            CkRow.Song(baseSongRow(id = "s1", isCollab = false, hasKamisabiCard = false, note = "ミリシタ 1 周年記念楽曲")),
            CkRow.Song(baseSongRow(id = "s2", isCollab = false, hasKamisabiCard = false))
        )

        val songs = SyncMappers.songs(rows).associateBy { it.id }

        assertEquals("ミリシタ 1 周年記念楽曲", songs.getValue("s1").note)
        assertEquals(null, songs.getValue("s2").note)
    }

    /** 検証に関係ない列は固定値で埋めた最小の [CkSongRow]。 */
    private fun baseSongRow(
        id: String,
        isCollab: Boolean,
        hasKamisabiCard: Boolean,
        note: String? = null
    ) = CkSongRow(
        id = id,
        title = "title-$id",
        titleKana = null,
        brandId = "765as",
        songType = "solo",
        releaseDate = null,
        durationSec = null,
        composer = null,
        lyricist = null,
        arranger = null,
        cdSeries = null,
        cdTitle = null,
        artworkUrl = null,
        previewUrl = null,
        appleMusicId = null,
        appleMusicAlbumId = null,
        isrc = null,
        lyricsUrl = null,
        parentSongId = null,
        singerLabel = null,
        unitName = null,
        unitId = null,
        seriesGroup = null,
        unitVersionId = null,
        jointBrandIds = null,
        isCollab = isCollab,
        hasKamisabiCard = hasKamisabiCard,
        note = note
    )
}
