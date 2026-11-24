package com.fugaif.imaslivedb.ui.songs

import com.fugaif.imaslivedb.data.lyrics.Lyrics
import uniffi.imas_core.LyricShareEnd
import uniffi.imas_core.shareLyricLinesLabel
import uniffi.imas_core.shareLyricUrl

/**
 * 歌詞タブで、共有のために選んだ行の範囲 (`Lyrics.lines` の添字)。iOS `LyricShareSelection.swift` の移植。
 *
 * 長押しした行が起点 ([anchor])、選択中にタップした行が終点 ([focus])。終点を起点の
 * 前後どちらに置いても、その間の行が全部入る (行ごとの選択。行内の位置は持たない)。
 * 歌詞タブ ([SongLyricsTab]) が書き、曲詳細 (`SongSheetContent`) が画面の下に帯を出す。
 *
 * ⚠️ 持つのは添字だけ。本文は持たない (共有に乗るのは URL だけ)。
 */
data class LyricShareSelection(val songId: String, val anchor: Int, val focus: Int = anchor) {
    val range: IntRange get() = minOf(anchor, focus)..maxOf(anchor, focus)
    val isSingleLine: Boolean get() = anchor == focus

    operator fun contains(line: Int): Boolean = line in range

    /** 公開サイトの曲ページ + `#lyric-12` / `#lyric-12-14` (組み立てはコア)。受け取った人のブラウザで開く。 */
    val url: String
        get() = shareLyricUrl(
            songId,
            LyricShareEnd(range.first.coerceAtLeast(0).toUInt(), null),
            LyricShareEnd(range.last.coerceAtLeast(0).toUInt(), null),
        )

    /** 「12行目」「12〜14行目」。番号は本文のある行で数える (コア)。 */
    fun linesLabel(lyrics: Lyrics): String =
        shareLyricLinesLabel(lyrics.lines.map { it.text }, range.first.toUInt(), range.last.toUInt())

    /** 帯の下段。1 行だけのうちは広げ方を案内する (見ただけでは分からない)。 */
    val note: String get() = if (isSingleLine) "ほかの行をタップで範囲を広げる" else "この部分へのリンク"
}
