package com.fugaif.imaslivedb.ui.timeline

import androidx.compose.ui.graphics.Color
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import uniffi.imas_core.TimelineBarLane
import uniffi.imas_core.TimelineBarPeriod
import uniffi.imas_core.TimelineBarRecord
import uniffi.imas_core.TimelineSpan
import uniffi.imas_core.ThemeRgb
import uniffi.imas_core.themeDeriveForCategoryKey
import uniffi.imas_core.themeVariantHex
import uniffi.imas_core.timelinePackRows
import uniffi.imas_core.timelineX
import uniffi.imas_core.timelineXPositions
import uniffi.imas_core.timelineYearBoundaries
import uniffi.imas_core.timelineYearRange

// =============================================================================
// 年表 1 回ぶんのレイアウト計算。
//
// **座標の規則はすべて共有コア (domain::timeline_layout) が持つ**。ここがやるのは
// 「コアに何をどの順で聞くか」と、コアが関与しない見え方の判断 (ラベルを出すズームか、
// ラベルの想定幅、行の高さ) だけ。日付 → x、行詰め、年境界を Kotlin で書き直すと
// iOS と黙ってズレるので、必ずコアの関数を通すこと。
//
// 座標系はキャンバス左上を原点とした dp 相当の実数 (pt)。
// =============================================================================

/** 現在のズームでのレイアウト全体。 */
data class TimelinePlan(
    /** キャンバス x = 0 に対応する日付 (epoch 秒)。 */
    val originEpochSeconds: Long,
    val pointsPerDay: Double,
    val totalDays: Double,
    val canvasWidth: Float,
    val canvasHeight: Float,
    /** 現在のズームでの 1 段の高さ。 */
    val rowHeight: Float,
    val years: List<YearTick>,
    val lanes: List<LaneBlock>,
    val placed: List<PlacedBar>,
    /** 「今」の x。年表の範囲外なら null。 */
    val todayX: Float?
) {
    data class YearTick(val year: Int, val x: Float, val width: Float)
    data class LaneBlock(val lane: TimelineBarLane, val y: Float, val height: Float)

    /**
     * 年ラベルを何年おきに出すか。1 年ぶんの幅に "2004" が入らないズームでは間引く。
     * 潰して "20…" にする代わりに間引くのは、罫線は毎年引いたままで密度感が失われないため。
     */
    val yearLabelStride: Int
        get() {
            val width = years.firstOrNull()?.width ?: 0f
            return when {
                width >= 36f -> 1
                width >= 16f -> 5
                else -> 10
            }
        }
}

/** キャンバス上に配置が確定した 1 本の帯。 */
data class PlacedBar(
    val bar: TimelineBarRecord,
    /** 帯の左端 (pt)。 */
    val x: Float,
    /** 帯そのものの幅 (pt)。タップ領域でもある。 */
    val barWidth: Float,
    /** ラベルの想定幅 (pt)。ラベルは帯からはみ出して右に伸びる。 */
    val labelWidth: Float,
    /** この帯にラベルを出すか (同じ段で重なるものは間引かれる)。 */
    val showsLabel: Boolean,
    /**
     * ラベルの左端をここまで右へずらしてよい、という上限 (キャンバス座標)。
     * 画面左で切れた帯のラベルを画面内へ貼り付けるときの止め位置。
     */
    val labelLimitX: Float,
    /** キャンバス上の絶対 y (pt)。 */
    val y: Float,
    /** 帯に打つ点 (公演日 / リリース日) の、帯の左端を 0 とした x。 */
    val markOffsets: List<Float>,
    val accent: Color,
    val labelColor: Color
) {
    /** 帯に出す文字列 (タイトル + バッジ)。 */
    val label: String get() = bar.badge?.let { "${bar.title}  $it" } ?: bar.title
}

/** 年表の見え方の寸法。iOS `BrandTimelineView.Metrics` と同じ値。 */
object TimelineMetrics {
    /** 既定のズーム (1 年あたりの pt)。縦持ちで 4 年弱が視野に入る密度。 */
    const val DEFAULT_POINTS_PER_YEAR = 100.0
    const val MIN_POINTS_PER_YEAR = 24.0
    const val MAX_POINTS_PER_YEAR = 2400.0
    const val DAYS_PER_YEAR = 365.25

    /** 帯 1 本分の行の高さ (ラベル + バー)。 */
    const val ROW_HEIGHT = 30f
    /** ラベルを描かないズームでの行の高さ (バーだけ)。 */
    const val COMPACT_ROW_HEIGHT = 13f
    const val LANE_PADDING = 9f
    /** 左に貼り付くレーン名の幅。 */
    const val RAIL_WIDTH = 54f
    /** 上に貼り付く年ルーラーの高さ。 */
    const val RULER_HEIGHT = 26f
    /** 単日の出来事でも最低これだけの幅を持たせる。タップ領域も兼ねる。 */
    const val MIN_BAR_WIDTH = 18.0
    /**
     * 俯瞰ズーム (ラベル非表示) での最低幅。ここを 18 のままにすると、時間軸を縮めても
     * 帯だけ縮まないので重なりが増え、全体表示にするほど段数が増えるという逆転が起きる。
     */
    const val COMPACT_MIN_BAR_WIDTH = 4.0
    /** タップ判定を横方向にだけ広げる遊び。広げすぎると隣の帯を誤爆する。 */
    const val TAP_SLOP = 6.0
    /** 帯とラベルの間、隣の帯との最低距離。 */
    const val PACK_GAP = 8.0
    const val COMPACT_PACK_GAP = 2.0
    /**
     * ラベルが占有できる最大幅。長いライブ名をそのまま占有幅に入れると行詰めが破綻して
     * 段数が爆発するので、ここで頭打ちにして重なりは省略記号に委ねる。
     */
    const val MAX_LABEL_WIDTH = 150.0
    /** これより粗いズームではラベルを描かない (団子になるだけで読めない)。 */
    const val LABEL_VISIBLE_POINTS_PER_YEAR = 64.0
    const val LABEL_FONT_SIZE = 10.5f
    const val BAR_THICKNESS = 7f

    fun clampPointsPerDay(value: Double): Double =
        value.coerceIn(MIN_POINTS_PER_YEAR / DAYS_PER_YEAR, MAX_POINTS_PER_YEAR / DAYS_PER_YEAR)
}

/** レーンの表示名 (左のレールに出す)。 */
val TimelineBarLane.title: String
    get() = when (this) {
        TimelineBarLane.MILESTONE -> "節目"
        TimelineBarLane.LIVE -> "ライブ"
        TimelineBarLane.MUSIC -> "楽曲"
        TimelineBarLane.OTHER -> "その他"
    }

private const val SECONDS_PER_DAY = 86_400.0

/**
 * 帯 → 配置済みキャンバスへの変換。倍率が変わるたびに作り直す。帯が 1 本も無ければ null。
 *
 * 日付 → x の変換は 1 本ずつではなく [timelineXPositions] の一括版に寄せる
 * (帯が 1,000 本を超えるブランドがあり、要素ごとに FFI を跨ぐと目に見えて遅くなる)。
 */
fun buildTimelinePlan(bars: List<TimelineBarRecord>, pointsPerDay: Double): TimelinePlan? {
    if (bars.isEmpty()) return null
    val range = timelineYearRange(
        bars.map { TimelineBarPeriod(it.startEpochSeconds, it.endEpochSeconds) }
    ) ?: return null
    val boundaries = timelineYearBoundaries(range.firstYear, range.lastYear)
    val origin = boundaries.firstOrNull()?.epochSeconds ?: return null
    val last = boundaries.lastOrNull()?.epochSeconds ?: return null

    val totalDays = (last - origin) / SECONDS_PER_DAY
    val canvasWidth = (totalDays * pointsPerDay).toFloat()

    // 年カラムの位置と幅は「実日数 × 倍率」。うるう年でずれない。
    val boundaryXs = timelineXPositions(boundaries.map { it.epochSeconds }, origin, pointsPerDay)
    val years = (0 until boundaries.size - 1).map { i ->
        TimelinePlan.YearTick(
            year = boundaries[i].year,
            x = boundaryXs[i].toFloat(),
            width = (boundaryXs[i + 1] - boundaryXs[i]).toFloat()
        )
    }

    val showsLabels = pointsPerDay * TimelineMetrics.DAYS_PER_YEAR >= TimelineMetrics.LABEL_VISIBLE_POINTS_PER_YEAR
    val rowHeight = if (showsLabels) TimelineMetrics.ROW_HEIGHT else TimelineMetrics.COMPACT_ROW_HEIGHT
    val minBarWidth = if (showsLabels) TimelineMetrics.MIN_BAR_WIDTH else TimelineMetrics.COMPACT_MIN_BAR_WIDTH
    val packGap = if (showsLabels) TimelineMetrics.PACK_GAP else TimelineMetrics.COMPACT_PACK_GAP

    val lanes = mutableListOf<TimelinePlan.LaneBlock>()
    val placed = mutableListOf<PlacedBar>()
    var y = 0f

    for (lane in TimelineBarLane.entries) {
        val laneBars = bars.filter { it.lane == lane }
        if (laneBars.isEmpty()) continue

        val startXs = timelineXPositions(laneBars.map { it.startEpochSeconds }, origin, pointsPerDay)
        val endXs = timelineXPositions(laneBars.map { it.endEpochSeconds }, origin, pointsPerDay)
        val xs = DoubleArray(laneBars.size) { startXs[it] }
        val widths = DoubleArray(laneBars.size) { maxOf(endXs[it] - startXs[it], minBarWidth) }
        val labelWidths = DoubleArray(laneBars.size) {
            if (!showsLabels) 0.0
            else minOf(
                estimatedLabelWidth(labelOf(laneBars[it]), TimelineMetrics.LABEL_FONT_SIZE.toDouble()),
                TimelineMetrics.MAX_LABEL_WIDTH
            )
        }

        // 行詰めは **帯の幅だけ** で行う。ラベル幅まで占有させると、密な年 (1 ブランドで
        // 年 28 公演といった密度) で段数が実態の何倍にも膨らみ、レーンが縦に伸びて
        // 「1 枚で俯瞰する」という目的が壊れる。
        val rows = timelinePackRows(
            laneBars.indices.map { TimelineSpan(xs[it], xs[it] + widths[it]) },
            packGap
        ).map { it.toInt() }
        val rowCount = (rows.maxOrNull() ?: 0) + 1

        // ラベルは「同じ段で直前のラベルと重ならないもの」にだけ出す。
        // 帯そのものは全部描くので、密度は失われずラベルだけが間引かれる。
        val labelVisible = BooleanArray(laneBars.size)
        val labelLimit = DoubleArray(laneBars.size)
        if (showsLabels) {
            val lastLabelEnd = HashMap<Int, Double>()
            val previousLabeled = HashMap<Int, Int>()
            for (index in laneBars.indices.sortedBy { xs[it] }) {
                val row = rows[index]
                if (xs[index] < (lastLabelEnd[row] ?: Double.NEGATIVE_INFINITY)) continue
                labelVisible[index] = true
                // 直前にラベルを出した帯は、この帯の手前までしかずらせない。
                previousLabeled[row]?.let { previous ->
                    labelLimit[previous] =
                        minOf(labelLimit[previous], xs[index] - labelWidths[previous] - packGap)
                }
                // 自分の帯の右端は越えない (越えると帯と切り離されて浮いて見える)。
                labelLimit[index] = xs[index] + widths[index] - 8
                lastLabelEnd[row] = xs[index] + labelWidths[index] + packGap
                previousLabeled[row] = index
            }
        }

        laneBars.forEachIndexed { index, bar ->
            val theme = barColors(bar)
            placed += PlacedBar(
                bar = bar,
                x = xs[index].toFloat(),
                barWidth = widths[index].toFloat(),
                labelWidth = labelWidths[index].toFloat(),
                showsLabel = labelVisible[index],
                labelLimitX = maxOf(labelLimit[index], xs[index]).toFloat(),
                y = y + TimelineMetrics.LANE_PADDING + rows[index] * rowHeight,
                markOffsets = markOffsets(bar, widths[index], pointsPerDay),
                accent = theme.first,
                labelColor = theme.second
            )
        }

        val height = rowCount * rowHeight + TimelineMetrics.LANE_PADDING * 2
        lanes += TimelinePlan.LaneBlock(lane, y, height)
        y += height
    }

    val nowSeconds = System.currentTimeMillis() / 1000
    val todayX = if (nowSeconds in origin..last) {
        timelineX(nowSeconds, origin, pointsPerDay).toFloat()
    } else null

    return TimelinePlan(
        originEpochSeconds = origin,
        pointsPerDay = pointsPerDay,
        totalDays = totalDays,
        canvasWidth = canvasWidth,
        canvasHeight = maxOf(y, 1f),
        rowHeight = rowHeight,
        years = years,
        lanes = lanes,
        placed = placed,
        todayX = todayX
    )
}

private fun labelOf(bar: TimelineBarRecord): String =
    bar.badge?.let { "${bar.title}  $it" } ?: bar.title

/**
 * 帯の左端を 0 とした点の x。帯の内側にクランプするので、単日の出来事で最低幅まで
 * 引き伸ばした帯でも点が外へ飛び出さない。
 */
private fun markOffsets(bar: TimelineBarRecord, barWidth: Double, pointsPerDay: Double): List<Float> {
    if (bar.markEpochSeconds.isEmpty()) return emptyList()
    val maxOffset = maxOf(barWidth - (TimelineMetrics.BAR_THICKNESS - 1), 0.0)
    return bar.markEpochSeconds.map { mark ->
        val offset = (mark - bar.startEpochSeconds) / SECONDS_PER_DAY * pointsPerDay
        offset.coerceIn(0.0, maxOffset).toFloat()
    }
}

/**
 * 帯の色 (accent, ラベル色)。**必ずブランドカラーが起点**で、楽曲レーンだけそこから
 * 振ったバリエーションを使う。
 *
 * シリーズ名の安定ハッシュから塗ると、全ブランド表示で「どれがどのブランドか」が色から
 * 読めなくなる。ブランド色を基準にすれば、全ブランドではブランドごとにまとまり、
 * 1 ブランドでもシリーズが見分けられる。
 */
private fun barColors(bar: TimelineBarRecord): Pair<Color, Color> {
    val seed = bar.seedHex
    if (seed == null) {
        // ブランド未設定 (稀) のときだけ分類キー由来の色にフォールバックする。
        // ImasTheme にこの入口が無いので、コアの導出をここで直に呼ぶ。
        val colors = themeDeriveForCategoryKey(bar.categoryKey, true)
        return colors.accent.toComposeColor() to colors.chipText.toComposeColor()
    }
    val theme = if (bar.lane == TimelineBarLane.MUSIC) {
        ImasTheme.derive(variantHex(seed, bar.categoryKey), dark = true)
    } else {
        ImasTheme.derive(seed, null, dark = true)
    }
    return theme.accent to theme.chipText
}

/**
 * バリエーション hex のメモ。ズーム 1 段ごとにレイアウトを作り直すので、
 * メモしないと帯の本数ぶん毎フレーム FFI を跨ぐ (`ImasTheme` 側のメモは
 * 導出結果にしか効かず、この変換自体は素通しになる)。
 */
private val variantCache = HashMap<Pair<String, String>, String>()

@Synchronized
private fun variantHex(hex: String, key: String): String =
    variantCache.getOrPut(hex to key) { themeVariantHex(hex, key) }

/** コアは sRGB 各成分を 0.0–1.0 にクランプ済みで返す。 */
private fun ThemeRgb.toComposeColor(): Color = Color(r.toFloat(), g.toFloat(), b.toFloat())

/**
 * 文字列の描画幅の近似。全角は 1em、半角は約 0.55em として数える。
 *
 * 正確な計測 (TextMeasurer) は帯 1,000 本ぶん走らせると重いので、行詰めにはこの近似で足りる
 * (iOS も同じ近似を使っており、両 OS で段数が揃う)。
 */
private fun estimatedLabelWidth(text: String, fontSize: Double): Double {
    var units = 0.0
    for (ch in text) units += if (ch.code > 0x2E7F) 1.0 else 0.55
    return units * fontSize
}
