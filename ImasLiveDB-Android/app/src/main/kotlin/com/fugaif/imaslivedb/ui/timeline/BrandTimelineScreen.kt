package com.fugaif.imaslivedb.ui.timeline

import android.app.Application
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.ZoomOutMap
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.ui.components.ImasChip
import com.fugaif.imaslivedb.ui.components.ImasChipStyle
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.filtered.SongFilterKind
import com.fugaif.imaslivedb.ui.theme.DS
import uniffi.imas_core.TimelineBarTarget
import uniffi.imas_core.TimelineHitBox
import uniffi.imas_core.timelineEpochAtX
import uniffi.imas_core.timelineFitPointsPerDay
import uniffi.imas_core.timelineHitIndex
import uniffi.imas_core.timelineX

// =============================================================================
// 年表 (ブランド史)。iOS `BrandTimelineView` の移植。
//
// 横軸 = 時間、縦 = スイムレーン (節目 / ライブ / 楽曲 / その他) の俯瞰チャート。
// 「いつ何が重なっていたか」を 1 枚で感じ取らせるのが目的なので、リストではなく
// 帯 + 点で密度そのものを見せる。年ルーラーは上に、レーン名は左に貼り付いたまま残る。
//
// ⚠️ スクロールに Scrollable/LazyColumn を使っていないのは意図的。貼り付くルーラー/レールは
// 本体と同じスクロール量で動かないと即座に破綻するが、スクロール量を外に出す仕組みは
// 更新のタイミングがずれ、ルーラーだけ違う年を指したまま本体が流れる。パン量を
// 自前の状態として持てば、3 者は定義上ずれない。
//
// **座標計算はコアが持つ** (TimelinePlan.kt 参照)。ここは描画とジェスチャだけ。
// =============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrandTimelineScreen(
    initialBrandId: String?,
    onBack: () -> Unit,
    onEventClick: (String) -> Unit,
    onFilteredSongsClick: (String, String) -> Unit
) {
    val app = LocalContext.current.applicationContext as Application
    val viewModel: BrandTimelineViewModel = viewModel(
        key = initialBrandId ?: "all",
        factory = BrandTimelineViewModel.Factory(app, initialBrandId)
    )
    val state by viewModel.uiState.collectAsState()
    val density = LocalDensity.current.density
    val textMeasurer = rememberTextMeasurer()

    /** 1 日あたりの pt。ピンチとズームメニューで変わる唯一の倍率。 */
    var pointsPerDay by remember {
        mutableStateOf(TimelineMetrics.DEFAULT_POINTS_PER_YEAR / TimelineMetrics.DAYS_PER_YEAR)
    }
    /** キャンバスのパン量 (pt)。正の値 = 右/下へ進んだ量。ルーラー・レール・本体が共有する唯一の真実。 */
    var panX by remember { mutableFloatStateOf(0f) }
    var panY by remember { mutableFloatStateOf(0f) }
    /** 直近に測ったプロット領域のサイズ (pt)。ジェスチャ内のクランプに使う。 */
    var plot by remember { mutableStateOf(Size.Zero) }
    var zoomMenuOpen by remember { mutableStateOf(false) }

    // レイアウトは「帯 × 倍率」から導く値。derivedStateOf に包んで **1 個の安定した State** に
    // しておくのが要点で、ジェスチャのラムダはここから毎回読み直す。composition ごとに
    // 作り直される val を捕まえると、ピンチで倍率が変わった瞬間から古いレイアウトに
    // 対して座標を計算し続けてしまう。
    val planState = remember { derivedStateOf { buildTimelinePlan(state.bars, pointsPerDay) } }
    val plan by planState

    fun clampX(value: Float, canvasWidth: Float): Float =
        value.coerceIn(0f, maxOf(canvasWidth - plot.width, 0f))

    fun clampY(value: Float, canvasHeight: Float): Float =
        value.coerceIn(0f, maxOf(canvasHeight - plot.height, 0f))

    /** 「今」が画面の中央付近に来るようにパンする。 */
    fun jumpToNow() {
        val p = planState.value ?: return
        val x = timelineX(System.currentTimeMillis() / 1000, p.originEpochSeconds, p.pointsPerDay)
        panX = clampX((x - plot.width * 0.6f).toFloat(), p.canvasWidth)
        panY = 0f
    }

    /** ズームの支点を「いま画面中央に見えている日付」に保ったまま倍率を変える。 */
    fun setPointsPerDay(target: Double) {
        val p = planState.value ?: run { pointsPerDay = TimelineMetrics.clampPointsPerDay(target); return }
        val centerEpoch = timelineEpochAtX(
            (panX + plot.width / 2f).toDouble(), p.originEpochSeconds, p.pointsPerDay
        )
        val next = TimelineMetrics.clampPointsPerDay(target)
        pointsPerDay = next
        // 倍率が変われば canvasWidth も変わる。origin は年範囲で決まりズームに依存しないので、
        // 新しい倍率で中央の日付を引き直すだけでよい。
        val nextCanvasWidth = (p.totalDays * next).toFloat()
        val x = timelineX(centerEpoch.toLong(), p.originEpochSeconds, next)
        panX = clampX((x - plot.width / 2f).toFloat(), nextCanvasWidth)
    }

    fun zoomToFit() {
        val p = planState.value ?: return
        if (p.totalDays <= 0 || plot.width <= 0f) return
        pointsPerDay = TimelineMetrics.clampPointsPerDay(
            timelineFitPointsPerDay(p.totalDays, plot.width.toDouble())
        )
        panX = 0f
    }

    /** 帯タップの遷移先。遷移先を持たない帯 (節目など) は何もしない。 */
    fun open(target: TimelineBarTarget) {
        when (target) {
            is TimelineBarTarget.Event -> onEventClick(target.id)
            is TimelineBarTarget.SeriesGroup -> onFilteredSongsClick(SongFilterKind.SERIES_GROUP, target.name)
            is TimelineBarTarget.CdSeries -> onFilteredSongsClick(SongFilterKind.CD_SERIES, target.name)
            is TimelineBarTarget.ReleaseYear -> onFilteredSongsClick(SongFilterKind.RELEASE_YEAR, target.year)
            TimelineBarTarget.None -> Unit
        }
    }

    // 年表を開いた時とブランドを切り替えた時は「今」へ寄せる。前のブランドのパン量を
    // 引き継ぐと、年範囲が違うブランドでは画面外を指したままになる。
    // プロット幅も鍵に入れるのは、初回は幅が決まる前 (onSizeChanged の前) に走るため。
    LaunchedEffect(state.selectedBrandId, plan?.originEpochSeconds, plot.width) {
        if (plan != null && plot.width > 0f) jumpToNow()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(state.selectedBrand?.let { "${it.shortName}の年表" } ?: "年表") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                actions = {
                    IconButton(onClick = { zoomMenuOpen = true }) {
                        Icon(Icons.Filled.ZoomOutMap, contentDescription = "表示倍率")
                    }
                    DropdownMenu(expanded = zoomMenuOpen, onDismissRequest = { zoomMenuOpen = false }) {
                        DropdownMenuItem(text = { Text("今へ") }, onClick = { zoomMenuOpen = false; jumpToNow() })
                        HorizontalDivider(color = DS.sep)
                        DropdownMenuItem(text = { Text("全体を表示") }, onClick = { zoomMenuOpen = false; zoomToFit() })
                        DropdownMenuItem(
                            text = { Text("標準") },
                            onClick = {
                                zoomMenuOpen = false
                                setPointsPerDay(TimelineMetrics.DEFAULT_POINTS_PER_YEAR / TimelineMetrics.DAYS_PER_YEAR)
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("拡大") },
                            onClick = { zoomMenuOpen = false; setPointsPerDay(560.0 / TimelineMetrics.DAYS_PER_YEAR) }
                        )
                    }
                }
            )
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).background(DS.bg)) {
            BrandBar(
                brands = state.brands,
                selectedBrandId = state.selectedBrandId,
                onSelect = { viewModel.select(it) }
            )
            HorizontalDivider(color = DS.sep)

            Box(Modifier.fillMaxSize()) {
                // 分岐の判定用。描画そのものは planState を直に読むので、
                // ズーム中はリコンポーズを挟まず再描画だけで済む。
                val hasPlan = plan != null
                when {
                    state.isLoading && !hasPlan ->
                        CircularProgressIndicator(Modifier.align(Alignment.Center))
                    !hasPlan -> ImasEmptyState(
                        icon = Icons.Filled.BarChart,
                        title = "年表を描けるデータがありません",
                        message = "このブランドにはまだライブ・楽曲の日付が登録されていません。"
                    )
                    else -> Canvas(
                        modifier = Modifier
                            .fillMaxSize()
                            .onSizeChanged { size ->
                                plot = Size(
                                    maxOf(size.width / density - TimelineMetrics.RAIL_WIDTH, 1f),
                                    maxOf(size.height / density - TimelineMetrics.RULER_HEIGHT, 1f)
                                )
                            }
                            // 検出器の鍵は Unit。plan や pan を鍵にすると、ピンチやドラッグの
                            // 最中に検出器ごと作り直されてジェスチャが途切れる。必要な値は
                            // すべて State 越しにその場で読むので、鍵に入れる必要がない。
                            //
                            // タップは「パンが成立しなかった操作」だけがここへ来る
                            // (detectTapGestures はスロップを超えて動いた時点で取り下げる)。
                            // 帯 1 本ずつをボタンにすると、少し滑らせただけで指を離した瞬間に開く。
                            .pointerInput(Unit) {
                                detectTapGestures { offset ->
                                    val p = planState.value ?: return@detectTapGestures
                                    hitTest(p, offset / density, panX, panY)?.let { open(it.bar.target) }
                                }
                            }
                            .pointerInput(Unit) {
                                detectTransformGestures { _, pan, zoom, _ ->
                                    if (zoom != 1f) {
                                        // ピンチは画面中央の日付を支点に保つ (指の中心ではなく画面中央なのは
                                        // iOS と揃えるため。指の中心を支点にすると帯が横へ流れて追いにくい)。
                                        setPointsPerDay(pointsPerDay * zoom)
                                    }
                                    val p = planState.value ?: return@detectTransformGestures
                                    val width = (p.totalDays * pointsPerDay).toFloat()
                                    panX = clampX(panX - pan.x / density, width)
                                    panY = clampY(panY - pan.y / density, p.canvasHeight)
                                }
                            }
                    ) {
                        val p = planState.value ?: return@Canvas
                        drawTimeline(p, panX, panY, density, textMeasurer)
                    }
                }
            }
        }
    }
}

/** ブランド切替のチップ列。 */
@Composable
private fun BrandBar(
    brands: List<Brand>,
    selectedBrandId: String?,
    onSelect: (String?) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(DS.surface)
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        ImasChip(
            text = "全ブランド",
            style = if (selectedBrandId == null) ImasChipStyle.SELECTED else ImasChipStyle.NEUTRAL,
            onClick = { onSelect(null) }
        )
        brands.forEach { brand ->
            ImasChip(
                text = brand.shortName,
                style = if (selectedBrandId == brand.id) ImasChipStyle.SELECTED else ImasChipStyle.NEUTRAL,
                seed = brand.color,
                onClick = { onSelect(brand.id) }
            )
        }
    }
}

/**
 * 画面上の点 (pt) → その位置にある帯。ルーラー/レールの領域は対象外。
 * 当たり判定そのものはコア (`timelineHitIndex`) が持つ。
 */
private fun hitTest(plan: TimelinePlan, point: Offset, panX: Float, panY: Float): PlacedBar? {
    if (point.x < TimelineMetrics.RAIL_WIDTH || point.y < TimelineMetrics.RULER_HEIGHT) return null
    // 画面座標 → キャンバス座標 (貼り付くヘッダーぶんを引いて、パン量を足す)。
    val x = (point.x - TimelineMetrics.RAIL_WIDTH + panX).toDouble()
    val y = (point.y - TimelineMetrics.RULER_HEIGHT + panY).toDouble()
    val targets = plan.placed.filter { it.bar.target != TimelineBarTarget.None }
    val boxes = targets.map {
        TimelineHitBox(it.x.toDouble(), it.barWidth.toDouble(), it.y.toDouble(), plan.rowHeight.toDouble())
    }
    val index = timelineHitIndex(x, y, boxes, TimelineMetrics.TAP_SLOP) ?: return null
    return targets.getOrNull(index.toInt())
}

/**
 * 本体 / 年ルーラー / レーン名レールの 3 層をまとめて描く。
 *
 * 3 層は同じパン量から描かれる (ルーラーは横だけ、レールは縦だけ追従)。
 * すべて pt で計算した値を [density] 倍して px に落とす。
 */
private fun DrawScope.drawTimeline(
    plan: TimelinePlan,
    panX: Float,
    panY: Float,
    density: Float,
    textMeasurer: TextMeasurer
) {
    val rail = TimelineMetrics.RAIL_WIDTH * density
    val ruler = TimelineMetrics.RULER_HEIGHT * density

    // --- 本体 (グリッド + 帯) ---
    clipRect(left = rail, top = ruler, right = size.width, bottom = size.height) {
        translate(left = rail - panX * density, top = ruler - panY * density) {
            drawLaneBands(plan, density)
            drawYearColumns(plan, density)
            drawTodayLine(plan, density)
            drawBars(plan, panX, density, textMeasurer)
        }
    }

    // --- 上に貼り付く年ルーラー (横だけ追従) ---
    drawRect(DS.surface, topLeft = Offset(rail, 0f), size = Size(size.width - rail, ruler))
    clipRect(left = rail, top = 0f, right = size.width, bottom = ruler) {
        translate(left = rail - panX * density, top = 0f) {
            drawRuler(plan, density, textMeasurer)
        }
    }
    drawRect(DS.sep, topLeft = Offset(rail, ruler - density), size = Size(size.width - rail, density))

    // --- 左に貼り付くレーン名 (縦だけ追従) ---
    drawRect(DS.surface, topLeft = Offset(0f, ruler), size = Size(rail, size.height - ruler))
    clipRect(left = 0f, top = ruler, right = rail, bottom = size.height) {
        translate(left = 0f, top = ruler - panY * density) {
            drawRail(plan, density, textMeasurer)
        }
    }
    drawRect(DS.sep, topLeft = Offset(rail - density, ruler), size = Size(density, size.height - ruler))

    // --- 左上の角 (ルーラーとレールの交差部) ---
    drawRect(DS.surface, topLeft = Offset.Zero, size = Size(rail, ruler))
}

/** レーンごとの背景バンド。交互に薄く塗って行を追いやすくする。 */
private fun DrawScope.drawLaneBands(plan: TimelinePlan, density: Float) {
    plan.lanes.forEachIndexed { index, lane ->
        if (index % 2 == 1) {
            drawRect(
                DS.fill.copy(alpha = 0.4f),
                topLeft = Offset(0f, lane.y * density),
                size = Size(plan.canvasWidth * density, lane.height * density)
            )
        }
        drawRect(
            DS.sep,
            topLeft = Offset(0f, (lane.y + lane.height) * density - density),
            size = Size(plan.canvasWidth * density, density)
        )
    }
}

/** 年の区切り線。 */
private fun DrawScope.drawYearColumns(plan: TimelinePlan, density: Float) {
    plan.years.forEach { tick ->
        drawRect(
            DS.sep.copy(alpha = 0.7f),
            topLeft = Offset(tick.x * density, 0f),
            size = Size(density, plan.canvasHeight * density)
        )
    }
}

private fun DrawScope.drawTodayLine(plan: TimelinePlan, density: Float) {
    val x = plan.todayX ?: return
    drawRect(
        DS.pick.copy(alpha = 0.7f),
        topLeft = Offset(x * density, 0f),
        size = Size(1.5f * density, plan.canvasHeight * density)
    )
}

/**
 * 帯。見えている x 範囲に掛かるものだけ描く。
 * 判定に使う panX は自前の状態なので、描画とズレることがない。
 */
private fun DrawScope.drawBars(
    plan: TimelinePlan,
    panX: Float,
    density: Float,
    textMeasurer: TextMeasurer
) {
    val viewWidth = size.width / density
    val minX = panX - viewWidth
    val maxX = panX + viewWidth * 2
    // 点が団子になるだけのズームでは省いて描画コストを下げる。
    val showsMarks = plan.pointsPerDay * 30 > 6
    val thickness = TimelineMetrics.BAR_THICKNESS * density
    val markRadius = (TimelineMetrics.BAR_THICKNESS - 1) * density / 2f

    for (placed in plan.placed) {
        if (placed.x + placed.barWidth + placed.labelWidth < minX || placed.x > maxX) continue

        // バーは行の下端に置き、ラベルはその上に出す (iOS と同じ縦の並び)。
        val barTop = (placed.y + plan.rowHeight - 3f) * density - thickness
        drawRoundRect(
            color = placed.accent.copy(alpha = 0.3f),
            topLeft = Offset(placed.x * density, barTop),
            size = Size(placed.barWidth * density, thickness),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(thickness / 2f)
        )
        if (showsMarks) {
            placed.markOffsets.forEach { offset ->
                drawCircle(
                    color = placed.accent,
                    radius = markRadius,
                    center = Offset((placed.x + offset) * density + markRadius, barTop + thickness / 2f)
                )
            }
        }

        if (placed.showsLabel) {
            // 左端で切れている帯は、ラベルを画面内へ引き寄せて何の帯かを見せる。
            // 次のラベルと自分の帯の右端を越えない範囲に収める。
            val wanted = panX + 4f - placed.x
            val shift = wanted.coerceIn(0f, maxOf(placed.labelLimitX - placed.x, 0f))
            val layout = textMeasurer.measure(
                text = placed.label,
                style = TextStyle(
                    fontSize = TimelineMetrics.LABEL_FONT_SIZE.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = placed.labelColor
                ),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                constraints = androidx.compose.ui.unit.Constraints(
                    maxWidth = maxOf((placed.labelWidth * density).toInt(), 1)
                )
            )
            drawText(
                textLayoutResult = layout,
                topLeft = Offset((placed.x + shift) * density, placed.y * density)
            )
        }
    }
}

/** 年ルーラー。年の幅が狭いとラベルは間引く (罫線は毎年引いたまま)。 */
private fun DrawScope.drawRuler(plan: TimelinePlan, density: Float, textMeasurer: TextMeasurer) {
    val stride = plan.yearLabelStride
    val height = TimelineMetrics.RULER_HEIGHT * density
    plan.years.forEach { tick ->
        drawRect(DS.sep, topLeft = Offset(tick.x * density, 0f), size = Size(density, height))
        if (tick.year % stride != 0) return@forEach
        val layout = textMeasurer.measure(
            text = tick.year.toString(),
            style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
        )
        drawText(
            textLayoutResult = layout,
            topLeft = Offset(tick.x * density + 4f * density, (height - layout.size.height) / 2f)
        )
    }
}

/**
 * 左のレーン名。アイコンは置かず名前だけ (Canvas にベクタアイコンを流し込む口が無く、
 * ここだけ Composable を重ねると貼り付きの計算が 2 系統に割れるため)。
 */
private fun DrawScope.drawRail(plan: TimelinePlan, density: Float, textMeasurer: TextMeasurer) {
    plan.lanes.forEach { lane ->
        val layout = textMeasurer.measure(
            text = lane.lane.title,
            style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
        )
        drawText(
            textLayoutResult = layout,
            topLeft = Offset(
                (TimelineMetrics.RAIL_WIDTH * density - layout.size.width) / 2f,
                (lane.y + TimelineMetrics.LANE_PADDING) * density
            )
        )
    }
}
