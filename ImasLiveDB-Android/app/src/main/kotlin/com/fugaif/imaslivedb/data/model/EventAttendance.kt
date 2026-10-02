package com.fugaif.imaslivedb.data.model

import uniffi.imas_core.AttendanceGroupRecord

/**
 * イベント内の出演状況。iOS `EventAttendance` (Database/QueryTypes.swift) の 1:1 移植。
 * 母集団と出席の判定はコアの `eventAttendance` が持ち、ここは表示用の集計だけ
 * ([com.fugaif.imaslivedb.data.repository.EventRepository.fetchEventAttendance])。
 * ユニット被覆判定 (披露ユニット表示) は Setlist 側の担当範囲と重複するため対象外。
 */
data class EventAttendance(
    val brandIdols: List<Idol>,
    val shows: List<Show>,
    val presenceByShow: Map<String, Set<String>>,
    val leadByShow: Map<String, Set<String>>,
    val guestByShow: Map<String, Set<String>>,
    private val groupRecords: List<AttendanceGroupRecord> = emptyList()
) {
    val leadIdolIds: Set<String> = leadByShow.values.flatten().toSet()
    val guestIdolIds: Set<String> = guestByShow.values.flatten().toSet()

    val leadIdols: List<Idol> = brandIdols.filter { it.id in leadIdolIds }
    val guestIdols: List<Idol> = brandIdols.filter { it.id in guestIdolIds }

    private val presentIds: Set<String> = presenceByShow.values.flatten().toSet()
    val presentIdols: List<Idol> = brandIdols.filter { it.id in presentIds }
    val absentIdols: List<Idol> = brandIdols.filter { it.id !in presentIds }

    val isFullAttendance: Boolean = brandIdols.isNotEmpty() && absentIdols.isEmpty()

    data class Group(
        val id: String,
        val label: String,
        val idols: List<Idol>,
        /** 日付ごとの塊ならその公演 (見出しに日付と公演名を出す)。「出演」「欠席」は null。 */
        val showId: String? = null
    )

    /**
     * 出演者の塊。複数日は日付ごと (`DAY1`/`DAY2`…)、単日公演は `出演`、どこにも出ていない人は
     * 最後に `欠席`。塊の切り方・見出し・並びはコア (`EventAttendanceRecord.groups`)。
     * ここは id を [brandIdols] の実体に引き直すだけ。
     */
    val groups: List<Group> = brandIdols.associateBy { it.id }.let { byId ->
        groupRecords.map { record ->
            Group(
                id = record.label,
                label = record.label,
                idols = record.idolIds.mapNotNull { byId[it] },
                showId = record.showId
            )
        }
    }
}
