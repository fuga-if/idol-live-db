package com.fugaif.imaslivedb.data.lyrics

/**
 * 歌詞タブ (= コールガイド) を画面に出してよいか。iOS `Services/LyricsFeature.swift` と対。
 *
 * 2026-10-06 に歌詞を全削除して閉じ、同日から利用者の投稿で集め直すことにして開け直した。
 */
object LyricsFeature {
    val isAvailable: Boolean get() = true

    /** 歌詞の投稿 ([com.fugaif.imaslivedb.ui.lyrics.LyricSubmissionScreen]) を受け付けるか。 */
    val acceptsSubmissions: Boolean get() = true
}
