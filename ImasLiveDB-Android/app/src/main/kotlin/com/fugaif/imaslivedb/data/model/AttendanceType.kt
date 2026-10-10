package com.fugaif.imaslivedb.data.model

/**
 * 参加形態 (`user_marks.text_value`)。iOS `AttendanceType` の 1:1 移植。
 *
 * 1 公演に複数付けられ、保存値は `live,stream` のように並ぶ。読み書きはコア
 * (`attendanceTypes` / `attendanceSetType`) で、種別なし (旧データ) は現地扱い。
 */
enum class AttendanceType(val raw: String) {
    LIVE("live"),
    STREAM("stream"),
    LIVE_VIEWING("live_viewing");

    /** 画面に出す語 (券の形態も同じ語)。語はコアの vocabulary。 */
    val label: String get() = Vocab.attendanceType(raw)?.shortLabel ?: raw

    companion object {
        fun from(raw: String?): AttendanceType? = entries.firstOrNull { it.raw == raw }

        /** その公演で選べる形態。iOS `AttendanceAvailability.options` と同じく常に 3 形態を出す。 */
        fun options(): List<AttendanceType> = entries
    }
}
