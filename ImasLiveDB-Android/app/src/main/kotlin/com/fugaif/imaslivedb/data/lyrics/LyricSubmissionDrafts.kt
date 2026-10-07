package com.fugaif.imaslivedb.data.lyrics

import androidx.compose.runtime.mutableStateMapOf
import uniffi.imas_core.RubyMark
import uniffi.imas_core.lyricRubyRebase
import uniffi.imas_core.lyricRubySplit

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
        val doubtfulLines: List<String> = emptyList(),
        /** 読み仮名。本文 ([text]) には記法 (《》・｜) を入れず、ここに分けて持つ。送るときに合わせる。 */
        val rubies: List<RubyMark> = emptyList()
    )

    private val drafts = mutableStateMapOf<String, Draft>()

    fun draft(songId: String): Draft = drafts[songId] ?: Draft()

    fun update(songId: String, change: (Draft) -> Draft) {
        drafts[songId] = change(draft(songId))
    }

    fun clear(songId: String) {
        drafts.remove(songId)
    }

    /**
     * 本文を書き換える。記法 (親字《よみ》) が入ってきたら (読み取り・貼り付け・手で打った《》)、
     * 本文から外して読み仮名の一覧へ移す。画面に記法を見せないため。書き換えで親字の位置がずれても
     * 付いていくよう、既にある読み仮名は [lyricRubyRebase] で付け直してから、新たに分けた分を足す。
     */
    fun setText(songId: String, text: String) {
        update(songId) { d ->
            var plain = text
            var added: List<RubyMark> = emptyList()
            if (text.contains("》")) {
                val split = lyricRubySplit(text)
                plain = split.plain
                added = split.marks
            }
            val rebased = if (d.rubies.isEmpty()) emptyList() else lyricRubyRebase(oldPlain = d.text, newPlain = plain, marks = d.rubies)
            d.copy(text = plain, rubies = rebased + added)
        }
    }
}
