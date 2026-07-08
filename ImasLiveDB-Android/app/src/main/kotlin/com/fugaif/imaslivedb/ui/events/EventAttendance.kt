package com.fugaif.imaslivedb.ui.events

import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.ShowCast

/**
 * イベント内の出演状況。iOS `EventAttendance` (Database/QueryTypes.swift) の 1:1 移植。
 * ユニット被覆判定 (披露ユニット表示) は Setlist 側の担当範囲と重複するため対象外。
 */
data class EventAttendance(
    val brandIdols: List<Idol>,
    val shows: List<Show>,
    val presenceByShow: Map<String, Set<String>>,
    val leadByShow: Map<String, Set<String>>,
    val guestByShow: Map<String, Set<String>>
) {
    val leadIdolIds: Set<String> = leadByShow.values.flatten().toSet()
    val guestIdolIds: Set<String> = guestByShow.values.flatten().toSet()

    val leadIdols: List<Idol> = brandIdols.filter { it.id in leadIdolIds }
    val guestIdols: List<Idol> = brandIdols.filter { it.id in guestIdolIds }

    private val presentIds: Set<String> = presenceByShow.values.flatten().toSet()
    val presentIdols: List<Idol> = brandIdols.filter { it.id in presentIds }
    val absentIdols: List<Idol> = brandIdols.filter { it.id !in presentIds }

    val isFullAttendance: Boolean = brandIdols.isNotEmpty() && absentIdols.isEmpty()

    data class Group(val id: String, val label: String, val idols: List<Idol>)

    /** 「全日 / DAYn のみ / 欠席」でアイドルをグループ化する (複数日公演の場合のみ意味を持つ)。 */
    fun grouped(): List<Group> {
        if (brandIdols.isEmpty()) return emptyList()
        val totalDays = shows.size

        val showsByIdol = mutableMapOf<String, MutableList<String>>()
        shows.forEach { show ->
            (presenceByShow[show.id] ?: emptySet()).forEach { idolId ->
                showsByIdol.getOrPut(idolId) { mutableListOf() }.add(show.id)
            }
        }

        val showLabelById = shows.mapIndexed { idx, sh ->
            sh.id to if (totalDays > 1) "DAY${idx + 1}" else sh.name
        }.toMap()
        val showIndexById = shows.mapIndexed { idx, sh -> sh.id to idx }.toMap()

        data class Bucket(val order: Int, val label: String, val idols: MutableList<Idol>)
        val buckets = mutableListOf<Bucket>()
        val indexByLabel = mutableMapOf<String, Int>()

        fun bucket(label: String, order: Int, idol: Idol) {
            val idx = indexByLabel[label]
            if (idx != null) {
                buckets[idx].idols.add(idol)
            } else {
                buckets.add(Bucket(order, label, mutableListOf(idol)))
                indexByLabel[label] = buckets.size - 1
            }
        }

        brandIdols.forEach { idol ->
            val attended = showsByIdol[idol.id] ?: emptyList()
            when {
                attended.isEmpty() -> bucket("欠席", 999, idol)
                attended.size == totalDays -> bucket(if (totalDays > 1) "全日" else "出演", 0, idol)
                else -> {
                    val labels = attended.mapNotNull { showLabelById[it] }
                    val combined = labels.joinToString("・")
                    val firstIdx = attended.mapNotNull { showIndexById[it] }.minOrNull() ?: 0
                    val order = 100 + firstIdx * 10 + attended.size
                    bucket("${combined} のみ", order, idol)
                }
            }
        }

        return buckets.sortedBy { it.order }.map { Group(it.label, it.label, it.idols) }
    }

    companion object {
        /** show_cast 全行 + ブランド名簿から EventAttendance を組み立てる。 */
        fun build(shows: List<Show>, brandIdols: List<Idol>, castRows: List<ShowCast>): EventAttendance {
            val presence = mutableMapOf<String, MutableSet<String>>()
            val lead = mutableMapOf<String, MutableSet<String>>()
            val guest = mutableMapOf<String, MutableSet<String>>()
            castRows.forEach { row ->
                presence.getOrPut(row.showId) { mutableSetOf() }.add(row.idolId)
                when (row.castRole) {
                    "lead" -> lead.getOrPut(row.showId) { mutableSetOf() }.add(row.idolId)
                    "guest" -> guest.getOrPut(row.showId) { mutableSetOf() }.add(row.idolId)
                }
            }
            return EventAttendance(brandIdols, shows, presence, lead, guest)
        }
    }
}
