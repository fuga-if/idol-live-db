package com.fugaif.imaslivedb.ui.schedule

import com.fugaif.imaslivedb.data.model.CalendarEntry
import java.time.LocalDate
import uniffi.imas_core.PeriodSpanInput
import uniffi.imas_core.weekPeriodBands

/**
 * 週内に描くチケット受付期間の帯 1 本ぶん。
 * 列インデックス + レーン (縦段) だけを持つ純粋なレイアウト値で、描画は呼び出し側に任せる。
 * 月グリッドと週ビューは座標系が違うが、ここまでの算出は共通なので共有する
 * (iOS `CalendarPeriodBand` と 1:1)。
 */
data class CalendarPeriodBand(
    val id: String,
    val entry: CalendarEntry,
    val name: String,
    val startCol: Int,
    val endCol: Int,
    /** 受付開始がこの週内 (左端を丸める)。 */
    val roundLeading: Boolean,
    /** 申込締切がこの週内 (右端を丸める)。 */
    val roundTrailing: Boolean,
    val lane: Int = 0
)

/**
 * この週 ([weekDays]) に重なる受付期間スパンを列範囲へ落とし込み、重ならないようレーン詰めする。
 * 列への落とし方・端の丸め・レーン詰め・同じイベントは 1 本はコア (weekPeriodBands)。週ごとに 1 回。
 */
fun packPeriodBands(
    weekDays: List<LocalDate>,
    byDate: Map<LocalDate, List<CalendarEntry>>
): List<CalendarPeriodBand> {
    val weekStart = weekDays.firstOrNull() ?: return emptyList()
    val periods = weekDays.flatMap { byDate[it].orEmpty() }.filterIsInstance<CalendarEntry.TicketPeriod>()
    if (periods.isEmpty()) return emptyList()
    val entryById = periods.associateBy { it.row.eventId }
    return weekPeriodBands(
        weekStart.toString(),
        periods.map { PeriodSpanInput(it.row.eventId, it.row.start, it.row.end) }
    ).mapNotNull { band ->
        val entry = entryById[band.id] ?: return@mapNotNull null
        CalendarPeriodBand(
            id = band.id,
            entry = entry,
            name = entry.row.eventName,
            startCol = band.startCol.toInt(),
            endCol = band.endCol.toInt(),
            roundLeading = band.roundLeading,
            roundTrailing = band.roundTrailing,
            lane = band.lane.toInt()
        )
    }
}

/** 帯リストが占めるレーン数 (0 = 帯なし)。 */
fun laneCount(bands: List<CalendarPeriodBand>): Int =
    (bands.maxOfOrNull { it.lane } ?: -1) + 1
