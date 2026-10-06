package com.fugaif.imaslivedb.data.lyrics

import androidx.compose.runtime.mutableStateMapOf

/**
 * 歌詞の投稿の書きかけ (曲ごと)。投稿画面の外に置いて、画面が作り直されても入力が消えない
 * ようにする (同期の完了などで画面が組み直されると、画面内の `remember` は消える)。
 * iOS `Services/LyricSubmissionDrafts.swift` と対。
 *
 * 端末のメモリにだけ置く (保存しない)。送れたとき・破棄したときに消す。
 */
object LyricSubmissionDrafts {

    data class Draft(
        val text: String = "",
        val agreed: Boolean = false,
        /** 読み取りに自信の無かった行 (見直してもらうために出す)。 */
        val doubtfulLines: List<String> = emptyList()
    )

    private val drafts = mutableStateMapOf<String, Draft>()

    fun draft(songId: String): Draft = drafts[songId] ?: Draft()

    fun update(songId: String, change: (Draft) -> Draft) {
        drafts[songId] = change(draft(songId))
    }

    fun clear(songId: String) {
        drafts.remove(songId)
    }
}
