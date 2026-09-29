package com.fugaif.imaslivedb.data.core

import android.util.Log
import uniffi.imas_core.textSearchMatchRange

/**
 * 元の文字列で絞り込み語が当たった範囲。Kotlin の String (UTF-16) の添字で、[end] は排他
 * (`AnnotatedString.addStyle` にそのまま渡せる形)。
 */
data class TextMatchSpan(val start: Int, val end: Int)

/**
 * 絞り込み語が「どこに当たったか」を訊く口。iOS `String.searchMatchRange(of:)` と同じ役割。
 *
 * 判定規則は imas-core (`domain/text_search_index.rs`) が正本で、一覧に載せるかを決める
 * `matching_indices` と**同じ畳み込み** (大文字小文字 / ひらがな↔カタカナ) を通る。
 * ここに `contains` / `indexOf` を書くと照合規則を二重に持つことになり、実際に iOS でズレた:
 * コアがかなを畳むようになっても Swift 側が畳まないままで、「おね」で一覧に出た
 * 「マリオネットの心」に色が付かなかった。ハイライトを敷く側はこの口だけを使うこと。
 */
object TextSearch {

    private const val TAG = "TextSearch"

    // ネイティブライブラリが同梱されていないビルド (Rust 未ビルドのコントリビューター環境)
    // では uniffi の呼び出しがリンクエラーで落ちる。FuzzySearch と同じ流儀で
    // 「ハイライト無し」に落として、一覧そのものは機能を失わずに動かす。
    @Volatile
    private var available = true

    /** 当たった範囲。当たっていなければ null (色を敷かない)。 */
    fun matchRange(haystack: String, needle: String): TextMatchSpan? {
        if (!available || haystack.isEmpty() || needle.isEmpty()) return null
        val hit = runCatching { textSearchMatchRange(haystack, needle) }
            .onFailure {
                available = false
                Log.w(TAG, "一致範囲が引けない → ハイライト無しで継続", it)
            }
            .getOrNull() ?: return null
        return haystack.utf16Span(hit.start.toInt(), hit.end.toInt())
    }

    /**
     * 当たったか (範囲そのものは要らない側)。
     *
     * 範囲が出せない = 色を敷けない ときは false にする。「一致したと言いながら色が付かない」
     * 説明行を出さないため (iOS `SongRowView.contains` と同じ扱い)。
     */
    fun matches(haystack: String, needle: String): Boolean = matchRange(haystack, needle) != null
}

/**
 * コアが返す **UTF-8 バイト位置** を Kotlin String (UTF-16) の添字へ移す。
 *
 * コアがバイト位置で返すのは、Swift の String.Index がそこから直接作れるから。Kotlin の
 * 添字は UTF-16 コード単位なので、先頭からコードポイントを辿って数え直す (日本語は 1 文字
 * 3 バイトなので、バイト位置をそのまま添字に使うと色が別の場所に付く)。
 *
 * 位置が文字境界に落ちない = 文字列とバイト列の対応が壊れている (不正なサロゲート等) ときは
 * null。半端な範囲に色を敷くより、色を敷かない方が安全。
 */
private fun String.utf16Span(startByte: Int, endByte: Int): TextMatchSpan? {
    if (startByte > endByte) return null
    var byte = 0
    var index = 0
    var start = -1
    while (true) {
        if (byte == startByte && start < 0) start = index
        if (byte == endByte && start >= 0) return TextMatchSpan(start, index)
        if (index >= length || byte > endByte) return null
        val codePoint = codePointAt(index)
        byte += utf8Length(codePoint)
        index += Character.charCount(codePoint)
    }
}

/** コードポイント 1 個ぶんの UTF-8 バイト数。 */
private fun utf8Length(codePoint: Int): Int = when {
    codePoint < 0x80 -> 1
    codePoint < 0x800 -> 2
    codePoint < 0x10000 -> 3
    else -> 4
}
