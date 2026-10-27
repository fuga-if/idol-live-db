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

/** Android 版の許諾 (2026年10月〜2027年9月、以降自動更新)。 */
object JASRACLicense {
    const val NUMBER = "J261043814"
    const val NOTICE = "JASRAC許諾第${NUMBER}号"
}

object NexToneLicense {
    const val NUMBER = "ID000012667"
    const val NOTICE = "NexTone許諾番号 $NUMBER"
}
