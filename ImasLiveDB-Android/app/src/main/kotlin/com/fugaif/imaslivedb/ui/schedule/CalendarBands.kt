package com.fugaif.imaslivedb.ui.schedule

import com.fugaif.imaslivedb.data.model.CalendarEntry
import uniffi.imas_core.TimelineSpan
import uniffi.imas_core.timelinePackRows
import java.time.LocalDate
import java.time.temporal.ChronoUnit

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
 *
 * レーン詰めは共有コアの `timelinePackRows` に投げる。年表 (タイムライン) の帯詰めと
 * 規則がまったく同じ「開始が早い順に、空いている一番上の段へ置く貪欲法」なので、
 * 同じ計算を Kotlin と Rust に 2 本持たない。
 *
 * コアは pt 座標の区間を受けるので、列インデックスをそのまま座標として渡し、
 * 隙間 (`gap`) に 1 を与える。コアの空き判定は `行の終端 + gap <= 開始` なので、
 * gap=1 は整数の列では「終端 < 開始」= iOS の `laneEnds[lane] < startCol` と同値になる。
 *
 * iOS との違いは同時開始のときの順序だけ: iOS は元の順、コアは長い帯を上に置く。
 * どちらも重なりは起きず、見え方はコア側のほうが素直なのでそちらに合わせる。
 */
fun packPeriodBands(
    weekDays: List<LocalDate>,
    byDate: Map<LocalDate, List<CalendarEntry>>
): List<CalendarPeriodBand> {
    val weekStart = weekDays.firstOrNull() ?: return emptyList()
    val weekEnd = weekDays.last()

    val seen = HashSet<String>()
    val bands = mutableListOf<CalendarPeriodBand>()
    for (date in weekDays) {
        for (entry in byDate[date] ?: emptyList()) {
            if (entry !is CalendarEntry.TicketPeriod) continue
            if (!seen.add(entry.row.eventId)) continue
            val start = runCatching { LocalDate.parse(entry.row.start) }.getOrNull() ?: continue
            val end = runCatching { LocalDate.parse(entry.row.end) }.getOrNull() ?: continue
            val startRaw = ChronoUnit.DAYS.between(weekStart, start).toInt()
            val endRaw = ChronoUnit.DAYS.between(weekStart, end).toInt()
            // 週の外へはみ出す端は列 0〜6 に丸め込む (帯は週の縁で切れる)。
            val startCol = startRaw.coerceIn(0, 6)
            val endCol = endRaw.coerceIn(0, 6)
            if (endRaw < 0 || startRaw > 6 || endCol < startCol) continue
            bands += CalendarPeriodBand(
                id = entry.row.eventId,
                entry = entry,
                name = entry.row.eventName,
                startCol = startCol,
                endCol = endCol,
                roundLeading = !start.isBefore(weekStart),
                roundTrailing = !end.isAfter(weekEnd)
            )
        }
    }
    if (bands.isEmpty()) return emptyList()

    val lanes = timelinePackRows(
        bands.map { TimelineSpan(it.startCol.toDouble(), it.endCol.toDouble()) },
        gap = 1.0
    )
    return bands.mapIndexed { index, band -> band.copy(lane = lanes[index].toInt()) }
}

/** 帯リストが占めるレーン数 (0 = 帯なし)。 */
fun laneCount(bands: List<CalendarPeriodBand>): Int =
    (bands.maxOfOrNull { it.lane } ?: -1) + 1
