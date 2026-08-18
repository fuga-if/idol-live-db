package com.fugaif.imaslivedb.data.model

/**
 * 参加形態 (`user_marks.text_value`)。iOS `AttendanceType` の 1:1 移植。
 *
 * 種別なし (旧データ) は現地扱い — 集計側の `EventDao.fetchAttendedEventTypeRows` と同じ解釈。
 */
enum class AttendanceType(val raw: String, val label: String) {
    LIVE("live", "現地"),
    STREAM("stream", "配信"),
    LIVE_VIEWING("live_viewing", "LV");

    companion object {
        fun from(raw: String?): AttendanceType? = entries.firstOrNull { it.raw == raw }

        /** その公演で選べる形態。iOS `AttendanceAvailability.options` と同じく常に 3 形態を出す。 */
        fun options(): List<AttendanceType> = entries
    }
}
