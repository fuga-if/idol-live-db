package com.fugaif.imaslivedb.data.model

import uniffi.imas_core.Vocabulary
import uniffi.imas_core.VocabularyTerm
import uniffi.imas_core.songTypeTerm
import uniffi.imas_core.vocabulary

/**
 * 画面に出す語 (曲種別・催しの種別と性格・参加形態・チケットの日付・タグのカテゴリ)。
 *
 * 語はコア (imas-core `vocabulary`) が持つ。ここは 1 回だけ引いて、生値 → 語を引く口を
 * 並べるだけ (行ごとに FFI を呼ばない)。並びは選択肢に出す並び。iOS `Vocab` と同じ。
 */
object Vocab {
    val table: Vocabulary by lazy { vocabulary() }

    /** 曲種別の語の覚え書き (生値 → 語。知らない値も「無い」として覚える)。 */
    private val songTypes = HashMap<String, VocabularyTerm?>()

    /**
     * 曲種別。知らない値は null (出さない)。古い値 (`group` / `original` / `unknown`) の読み方は
     * コアの `songTypeTerm` が決める。生値の種類は数個なので、値ごとに 1 回だけ引いて覚える。
     */
    fun songType(raw: String?): VocabularyTerm? {
        if (raw == null) return null
        return synchronized(songTypes) { songTypes.getOrPut(raw) { songTypeTerm(raw) } }
    }

    fun eventKind(raw: String): VocabularyTerm? = table.eventKinds.firstOrNull { it.value == raw }
    fun eventType(raw: String): VocabularyTerm? = table.eventTypes.firstOrNull { it.value == raw }
    fun attendanceType(raw: String): VocabularyTerm? = table.attendanceTypes.firstOrNull { it.value == raw }

    /** チケットの日付の語。`column` は events の列名 (`ticket_deadline` 等)。 */
    fun ticketDate(column: String): VocabularyTerm? = table.ticketDates.firstOrNull { it.value == column }
}
