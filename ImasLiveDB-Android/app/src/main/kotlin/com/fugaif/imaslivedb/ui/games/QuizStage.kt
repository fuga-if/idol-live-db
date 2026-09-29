package com.fugaif.imaslivedb.ui.games

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateIntAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.ArrowDropUp
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.games.QuizStagePlay
import com.fugaif.imaslivedb.ui.components.ArtworkImage
import com.fugaif.imaslivedb.ui.navigation.BottomBarVisibility
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import uniffi.imas_core.QuizGrade
import uniffi.imas_core.QuizSessionResult

// =============================================================================
// クイズの「ステージ」見た目。iOS ImasLiveDB/Views/Games/QuizStage.swift の移植。
//
// ゲーム中の画面だけは、アプリ本体の画面ではなくライブ会場の暗いステージにする。
// 正解するたびに「セトリ」のペンライトがその問題の答えの色で 1 本ずつ灯り、
// 問題とヒントは生成り色の「チケット」に載る。数字は細長い太字、ラベルは等幅の英字。
//
// 見た目の部品だけを置き、出題・採点・グレードの規則は今まで通りコア (imas-core) が持つ。
// ステージ固定の配色なので DS トークンではなく `QS` の固定色を使う。
// =============================================================================

/** ステージ画面の配色・書体。値は iOS の `QS` と同じ。 */
object QS {
    val bg = Color(0xFF15131C)
    val panel = Color(0xFF1F1C28)
    val raised = Color(0xFF24212E)
    val line = Color(0xFF3A3547)
    val rowLine = Color(0xFF2E2A38)
    val missFill = Color(0xFF26232F)

    /** 本文 (生成り)。 */
    val ink = Color(0xFFF6F1E7)
    val dim = Color(0xFFA7A1B5)
    val faint = Color(0xFF8C8699)

    /** チケット (生成りの紙) の上の色。 */
    val paper = ink
    val paperInk = Color(0xFF1B1822)
    val paperTile = Color(0xFFEAE3D6)
    val paperHighlight = Color(0xFFEFE8DB)
    val paperSub = Color(0xFF6B6478)
    val paperMuted = Color(0xFFA49B8C)
    val paperLine = Color(0xFFE4DCCD)
    val paperDash = Color(0xFFC9C0B0)
    val stamp = Color(0xFFB42335)

    /** 答えの色が無いとき (曲など) にペンライトへ回す色。アプリアイコンの帯の色。 */
    val penlights: List<Color> = listOf(
        Color(0xFFE5484D), Color(0xFFF08C2E), Color(0xFFF2C12E), Color(0xFF3FB27F),
        Color(0xFF3A8EE6), Color(0xFF7A5AE0), Color(0xFFD65DB1)
    )

    fun penlight(index: Int): Color = penlights[index.mod(penlights.size)]

    /**
     * 細長い太字 (iOS の `.width(.compressed)` 相当)。Android 標準の condensed 書体を使い、
     * 無い端末では通常のサンセリフに落ちる。
     */
    private val condensed: FontFamily = FontFamily(
        androidx.compose.ui.text.font.Typeface(
            android.graphics.Typeface.create("sans-serif-condensed", android.graphics.Typeface.NORMAL)
        )
    )

    private val noPadding = PlatformTextStyle(includeFontPadding = false)

    /** 大きな数字 (細長い太字・等幅数字)。 */
    fun num(size: Int, weight: FontWeight = FontWeight.ExtraBold): TextStyle = TextStyle(
        fontFamily = condensed, fontSize = size.sp, fontWeight = weight,
        fontFeatureSettings = "tnum", platformStyle = noPadding
    )

    /** 英字ラベル・番号 (等幅)。 */
    fun mono(size: Int, tracking: Float = 0f): TextStyle = TextStyle(
        fontFamily = FontFamily.Monospace, fontSize = size.sp, fontWeight = FontWeight.SemiBold,
        letterSpacing = tracking.sp, platformStyle = noPadding
    )

    fun text(size: Int, weight: FontWeight = FontWeight.Normal): TextStyle =
        TextStyle(fontSize = size.sp, fontWeight = weight, platformStyle = noPadding)
}

/** hex → 色。読めなければ [default] (iOS の `Color(hexString:default:)`)。 */
internal fun qsColor(hex: String?, default: Color): Color {
    val cleaned = hex?.trim()?.trimStart('#') ?: return default
    val value = cleaned.toLongOrNull(16) ?: return default
    return when (cleaned.length) {
        6 -> Color(0xFF000000 or value)
        8 -> Color(value)
        else -> default
    }
}

/** 「正解」「+100」などの 2 桁表記 (Q.04 / M03)。 */
internal fun twoDigits(n: Int): String = "%02d".format(n)

// MARK: - 小さな部品

/**
 * 押している間だけ少し沈むクリック (iOS `QuizPressStyle`)。
 * 波紋 (リップル) は出さない: 生成りの紙やステージの面に灰色の波紋が乗ると安っぽく見えるため。
 */
@Composable
internal fun Modifier.quizPress(enabled: Boolean = true, onClick: () -> Unit): Modifier {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed && enabled) 0.97f else 1f, tween(120), label = "press")
    return this
        .graphicsLayer { scaleX = scale; scaleY = scale }
        .clickable(interactionSource = source, indication = null, enabled = enabled, onClick = onClick)
}

/** 点線の角丸枠 (SwiftUI の strokeBorder + dash)。 */
internal fun Modifier.dashedBorder(
    color: Color,
    width: Dp,
    radius: Dp,
    dash: Dp = 5.dp,
    gap: Dp = 4.dp,
    dashed: Boolean = true
): Modifier = drawBehind {
    val w = width.toPx()
    drawRoundRect(
        color = color,
        topLeft = Offset(w / 2, w / 2),
        size = Size(size.width - w, size.height - w),
        cornerRadius = CornerRadius(radius.toPx()),
        style = Stroke(
            width = w,
            pathEffect = if (dashed) PathEffect.dashPathEffect(floatArrayOf(dash.toPx(), gap.toPx())) else null
        )
    )
}

/** 横一本の点線 (チケットの切り取り線・判定カードの区切り)。 */
@Composable
internal fun QuizDashedRule(color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxWidth().height(1.5.dp)) {
        drawLine(
            color = color,
            start = Offset(0f, size.height / 2),
            end = Offset(size.width, size.height / 2),
            strokeWidth = 1.5.dp.toPx(),
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))
        )
    }
}

/**
 * 入りきらないときだけ文字を縮めるテキスト (iOS の `minimumScaleFactor`)。
 * Compose 1.7 には autoSize が無いので、はみ出したら 1 割ずつ縮めて測り直す。
 * 測り終わるまでは描かない (縮む途中のちらつきを見せない)。
 */
@Composable
internal fun QSFitText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    maxLines: Int = 1,
    minScale: Float = 0.6f,
    textAlign: TextAlign? = null,
    textDecoration: TextDecoration? = null
) {
    var scale by remember(text, style.fontSize) { mutableFloatStateOf(1f) }
    var ready by remember(text, style.fontSize) { mutableStateOf(false) }
    val size: TextUnit = style.fontSize * scale
    Text(
        text,
        style = style.copy(fontSize = size),
        color = color,
        maxLines = maxLines,
        softWrap = maxLines > 1,
        overflow = if (ready) TextOverflow.Ellipsis else TextOverflow.Clip,
        textAlign = textAlign,
        textDecoration = textDecoration,
        modifier = modifier.drawWithContent { if (ready) drawContent() },
        onTextLayout = { r ->
            if (!ready) {
                if (r.hasVisualOverflow && scale > minScale) {
                    scale = maxOf(minScale, scale * 0.9f)
                } else {
                    ready = true
                }
            }
        }
    )
}

/** ステージ上の丸いボタン (× / シェア)。 */
@Composable
fun QuizStageRoundButton(icon: ImageVector, label: String, busy: Boolean = false, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(40.dp)
            .clip(CircleShape)
            .background(QS.raised)
            .quizPress(enabled = !busy, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center
    ) {
        if (busy) {
            CircularProgressIndicator(color = QS.ink, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
        } else {
            Icon(icon, contentDescription = null, tint = QS.ink, modifier = Modifier.size(19.dp))
        }
    }
}

// MARK: - 上部 (ゲーム名・問題番号・スコア)

/** 上部中央の「ゲーム名 / Q.04 / 10」。 */
@Composable
private fun QuizStageTitle(title: String, current: Int, total: Int) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(1.dp),
        modifier = Modifier.semantics { contentDescription = "$title 第${current}問 全${total}問" }
    ) {
        Text(title, style = QS.text(11, FontWeight.Bold).copy(letterSpacing = 0.8.sp), color = QS.dim)
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Text("Q.${twoDigits(current)}", style = QS.num(24), color = QS.ink)
            Text("/ $total", style = QS.num(14, FontWeight.Bold), color = QS.faint, modifier = Modifier.padding(bottom = 2.dp))
        }
    }
}

/** 上部右の「SCORE 300」。 */
@Composable
private fun QuizStageScore(points: Int) {
    val shown by animateIntAsState(points, tween(450), label = "score")
    Column(
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(1.dp),
        modifier = Modifier.semantics { contentDescription = "スコア $points" }
    ) {
        Text("SCORE", style = QS.mono(9, 1f), color = QS.dim)
        Text("$shown", style = QS.num(22), color = QS.ink)
    }
}

// MARK: - セトリのペンライト (進み具合)

/** 1 問分のペンライト。正解 = 答えの色で点灯 / 不正解 = 消灯 (×) / 出題中 / これから。 */
@Immutable
sealed interface QuizPenlight {
    data class Lit(val color: Color) : QuizPenlight
    data object Miss : QuizPenlight
    data object Now : QuizPenlight
    data object Next : QuizPenlight

    companion object {
        /**
         * これまでの結果 (正解はその色、不正解は null) から全問ぶんを並べる。
         * [answering] のときは次の 1 本を「出題中」にする。
         */
        fun slots(results: List<Color?>, total: Int, answering: Boolean): List<QuizPenlight> =
            (0 until maxOf(total, results.size)).map { i ->
                if (i < results.size) results[i]?.let { Lit(it) } ?: Miss
                else if (answering && i == results.size) Now else Next
            }
    }
}

/** 答えの色 (無ければ帯の色を順に)。ペンライトとシェア画像の行で同じ色にする。 */
internal fun QuizStagePlay.penlightColor(index: Int): Color = qsColor(answerHex, QS.penlight(index))

fun List<QuizStagePlay>.penlights(total: Int, answering: Boolean): List<QuizPenlight> =
    QuizPenlight.slots(
        results = mapIndexed { i, p -> if (p.isCorrect) p.penlightColor(i) else null },
        total = total, answering = answering
    )

/** 結果画面の「見直す」に並べる 1 問。 */
@Immutable
data class QuizMissItem(val id: String, val number: Int, val title: String, val hex: String?, val picked: String?)

val List<QuizStagePlay>.misses: List<QuizMissItem>
    get() = filter { !it.isCorrect }.map {
        QuizMissItem(id = "${it.number}", number = it.number, title = it.answerName, hex = it.answerHex, picked = it.pickedName)
    }

private val StickShape = RoundedCornerShape(topStart = 6.dp, topEnd = 6.dp, bottomStart = 3.dp, bottomEnd = 3.dp)

/** ペンライトの列。 */
@Composable
fun QuizPenlightRow(slots: List<QuizPenlight>, height: Dp = 26.dp, numbered: Boolean = false) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
        slots.forEachIndexed { i, slot ->
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(2.dp),
                modifier = Modifier.weight(1f)
            ) {
                PenlightStick(slot, Modifier.fillMaxWidth().height(height))
                Box(
                    Modifier
                        .size(width = 10.dp, height = if (numbered) 8.dp else 6.dp)
                        .clip(RoundedCornerShape(bottomStart = 3.dp, bottomEnd = 3.dp))
                        .background(QS.line)
                )
                if (numbered) {
                    Text(twoDigits(i + 1), style = QS.mono(10), color = QS.faint, modifier = Modifier.padding(top = 2.dp))
                }
            }
        }
    }
}

@Composable
private fun PenlightStick(slot: QuizPenlight, modifier: Modifier) {
    val target = when (slot) {
        is QuizPenlight.Lit -> slot.color
        QuizPenlight.Miss -> QS.missFill
        QuizPenlight.Now -> QS.raised
        QuizPenlight.Next -> Color.Transparent
    }
    val fill by animateColorAsState(target, spring(dampingRatio = 0.7f, stiffness = Spring.StiffnessMediumLow), label = "penlight")
    val lit = slot is QuizPenlight.Lit
    Box(
        modifier = modifier
            .then(
                if (lit) Modifier.shadow(6.dp, StickShape, clip = false, ambientColor = fill, spotColor = fill)
                else Modifier
            )
            .clip(StickShape)
            .background(fill)
            .then(
                when (slot) {
                    QuizPenlight.Now -> Modifier.border(2.dp, QS.ink, StickShape)
                    QuizPenlight.Next -> Modifier.border(1.dp, QS.line, StickShape)
                    else -> Modifier
                }
            ),
        contentAlignment = Alignment.Center
    ) {
        if (slot == QuizPenlight.Miss) {
            Icon(Icons.Filled.Close, contentDescription = null, tint = QS.faint, modifier = Modifier.size(10.dp))
        }
    }
}

/** ヘッダ下のペンライト + 一言 (「セトリ 3 / 10 曲目まで点灯」「3 連続正解中」)。 */
@Composable
fun QuizStageProgress(slots: List<QuizPenlight>, caption: String, streak: Int, streakBrokeAt: Int? = null) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(bottom = 2.dp)) {
        QuizPenlightRow(slots)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(caption, style = QS.text(12), color = QS.dim, modifier = Modifier.weight(1f))
            if (streak >= 2) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.ArrowDropUp, contentDescription = null, tint = QS.ink, modifier = Modifier.size(18.dp))
                    Text("$streak 連続正解中", style = QS.text(12, FontWeight.Bold), color = QS.ink)
                }
            } else if (streakBrokeAt != null && streakBrokeAt >= 2) {
                Text("連続正解 $streakBrokeAt でストップ", style = QS.text(12, FontWeight.Bold), color = QS.dim)
            }
        }
    }
}

// MARK: - 正解でもらえる点

/** 「正解でもらえる点 +70 (100)」とヒントで減っていく 10 目盛り。 */
@Composable
fun QuizValueMeter(value: Int, base: Int, note: String) {
    val lit = if (base > 0) Math.round(value.toDouble() / base * 10).toInt() else 0
    val shown by animateIntAsState(value, tween(350), label = "meter")
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(QS.panel)
            .padding(horizontal = 16.dp, vertical = 10.dp)
            .semantics { contentDescription = "正解でもらえる点 ${value}点。$note" }
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("正解でもらえる点", style = QS.text(12, FontWeight.Bold), color = QS.dim)
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("+$shown", style = QS.num(42), color = QS.ink)
                if (value < base) {
                    Text(
                        "$base", style = QS.num(20, FontWeight.Bold), color = QS.faint,
                        textDecoration = TextDecoration.LineThrough, modifier = Modifier.padding(bottom = 5.dp)
                    )
                }
            }
        }
        Spacer(Modifier.weight(1f).width(8.dp))
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                repeat(10) { i ->
                    val on = i < lit
                    val alpha by animateFloatAsState(if (on) 1f else 0f, tween(250), label = "seg")
                    Box(
                        Modifier
                            .size(width = 7.dp, height = 24.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .border(1.dp, QS.line, RoundedCornerShape(2.dp))
                            .background(QS.ink.copy(alpha = alpha))
                    )
                }
            }
            Text(note, style = QS.text(11), color = QS.dim)
        }
    }
}

// MARK: - チケット (問題とヒントを載せる生成りの紙)

@Composable
fun QuizTicket(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(QS.paper),
        content = content
    )
}

/** チケットの切り取り線 (両端が [cut] 色の半円で欠ける)。 */
@Composable
fun QuizTicketNotch(cut: Color = QS.bg, line: Color = QS.paperDash, inset: Dp = 8.dp) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().height(18.dp)) {
        Box(
            Modifier.size(width = 9.dp, height = 18.dp)
                .clip(RoundedCornerShape(topEnd = 9.dp, bottomEnd = 9.dp)).background(cut)
        )
        QuizDashedRule(line, Modifier.weight(1f).padding(horizontal = inset))
        Box(
            Modifier.size(width = 9.dp, height = 18.dp)
                .clip(RoundedCornerShape(topStart = 9.dp, bottomStart = 9.dp)).background(cut)
        )
    }
}

/** チケット上部の「? / PROFILE / このアイドルはだれ？」。 */
@Composable
fun QuizTicketHeading(label: String, question: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 14.dp, bottom = 12.dp)
    ) {
        Box(
            Modifier.size(48.dp).dashedBorder(QS.paperMuted, 2.dp, 24.dp, dash = 4.dp, gap = 3.dp),
            contentAlignment = Alignment.Center
        ) { Text("?", style = QS.num(26), color = QS.paperSub) }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.weight(1f)) {
            Text(label, style = QS.mono(11, 1.4f), color = QS.paperSub)
            Text(question, style = QS.text(20, FontWeight.Black), color = QS.paperInk)
        }
    }
}

/** チケットに最初から見えている事実 (血液型 A型 など) のタイル。 */
@Composable
fun QuizTicketFactTile(label: String, value: String, modifier: Modifier = Modifier) {
    Column(
        verticalArrangement = Arrangement.spacedBy(1.dp),
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(QS.paperTile)
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        Text(label, style = QS.text(11, FontWeight.Bold), color = QS.paperSub)
        QSFitText(value, QS.text(18, FontWeight.Black), QS.paperInk, maxLines = 2, minScale = 0.7f)
    }
}

/** ヒント欄の見出し「ヒント — 開くほど点が下がる   1 / 3」。 */
@Composable
fun QuizTicketHintHeader(opened: Int, total: Int) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 4.dp, bottom = 2.dp)
    ) {
        Text("ヒント — 開くほど点が下がる", style = QS.text(11, FontWeight.Bold), color = QS.paperSub, modifier = Modifier.weight(1f))
        Text("$opened / $total", style = QS.mono(11), color = QS.paperSub)
    }
}

/** ヒント 1 行。未開封は「••• / 開く −10」、開封後は中身と差し引いた点。 */
@Composable
fun QuizTicketHintRow(
    number: Int,
    label: String,
    cost: Int,
    isOpen: Boolean,
    isNew: Boolean = false,
    isFirst: Boolean = false,
    onOpen: () -> Unit,
    revealed: @Composable () -> Unit
) {
    Box(Modifier.fillMaxWidth().background(if (isNew) QS.paperHighlight else Color.Transparent)) {
        if (!isFirst) Box(Modifier.fillMaxWidth().height(1.dp).background(QS.paperLine))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 52.dp)
                .padding(start = 18.dp, end = if (isOpen) 18.dp else 10.dp, top = 4.dp, bottom = 4.dp)
        ) {
            Text(twoDigits(number), style = QS.mono(11), color = QS.paperSub)
            Column(verticalArrangement = Arrangement.spacedBy(1.dp), modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(label, style = QS.text(11, FontWeight.Bold), color = QS.paperSub)
                    if (isNew) {
                        Text(
                            "NEW", style = QS.mono(9), color = QS.paperInk,
                            modifier = Modifier.border(1.dp, QS.paperInk, RoundedCornerShape(4.dp)).padding(horizontal = 4.dp)
                        )
                    }
                }
                if (isOpen) {
                    revealed()
                } else {
                    Text(
                        "••••••", style = QS.text(16, FontWeight.Black).copy(letterSpacing = 2.sp), color = QS.paperMuted,
                        modifier = Modifier.semantics { contentDescription = "未開封" }
                    )
                }
            }
            if (isOpen) {
                Text("−$cost", style = QS.num(18), color = QS.paperSub)
            } else {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier
                        .height(44.dp)
                        .clip(CircleShape)
                        .background(QS.paperInk)
                        .quizPress(onClick = onOpen)
                        .padding(horizontal = 16.dp)
                        .semantics { contentDescription = "${label}のヒントを開く。${cost}点下がります" }
                ) {
                    Text("開く", style = QS.text(14, FontWeight.Bold), color = QS.ink)
                    Text("−$cost", style = QS.num(18), color = QS.paperTile.copy(alpha = 0.85f))
                }
            }
        }
    }
}

/** 開いたヒントの中身 (文字)。 */
@Composable
fun QuizTicketHintValue(text: String) {
    QSFitText(text, QS.text(18, FontWeight.Black), QS.paperInk, maxLines = 2, minScale = 0.7f)
}

/** 開いたヒントの中身 (イメージカラー)。 */
@Composable
fun QuizTicketColorValue(hex: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.padding(top = 2.dp)
    ) {
        Box(
            Modifier.size(width = 44.dp, height = 16.dp).clip(RoundedCornerShape(4.dp))
                .background(qsColor(hex, QS.paperMuted))
        )
        Text(hex.uppercase(), style = QS.mono(13), color = QS.paperInk)
    }
}

// MARK: - 4 択

@Immutable
data class QuizStageChoice(val id: String, val title: String)

private val CHOICE_LETTERS = listOf("A", "B", "C", "D", "E", "F")

/** A〜D の 4 択 ([columns] 列)。押したら確定。[eliminated] は 2 択ヒントなどで消した選択肢 (押せない)。 */
@Composable
fun QuizStageChoiceGrid(
    choices: List<QuizStageChoice>,
    columns: Int = 2,
    eliminated: Set<String> = emptySet(),
    onPick: (QuizStageChoice) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(top = 4.dp)) {
        choices.withIndex().chunked(columns).forEach { row ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min)
            ) {
                row.forEach { (i, choice) ->
                    val isOut = choice.id in eliminated
                    val alpha by animateFloatAsState(if (isOut) 0.35f else 1f, tween(200), label = "out")
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .heightIn(min = 60.dp)
                            .alpha(alpha)
                            .quizPress(enabled = !isOut) { onPick(choice) }
                            .clip(RoundedCornerShape(16.dp))
                            .background(QS.panel)
                            .border(1.dp, QS.line, RoundedCornerShape(16.dp))
                            .padding(horizontal = 14.dp, vertical = 8.dp)
                    ) {
                        Text(CHOICE_LETTERS[i % CHOICE_LETTERS.size], style = QS.mono(12), color = QS.faint)
                        QSFitText(
                            choice.title, QS.text(16, FontWeight.Bold), QS.ink,
                            maxLines = if (columns == 1) 3 else 2, minScale = 0.7f,
                            textDecoration = if (isOut) TextDecoration.LineThrough else null,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

// MARK: - 正解 / 不正解

/** 解答直後に出す大きなカードの中身。 */
@Immutable
data class QuizVerdict(
    val isCorrect: Boolean,
    val number: Int,
    /** 正解の名前 (アイドル名・曲名)。 */
    val answerName: String,
    /** 正解の色 (アイドルのイメージカラー)。曲など色が無いときは null。 */
    val answerHex: String?,
    /** 獲得点・ヒント無しの点・開いたヒント数。 */
    val earned: Int,
    val base: Int,
    val hints: Int,
    /** 不正解のとき選んだもの。 */
    val pickedName: String?,
    /** 正解の補足 (プロフィールの要約・収録CD など)。 */
    val detail: String?,
    /** 正解の横に出すジャケット (セトリ当て)。 */
    val artworkUrl: String? = null,
    /** 点の内訳 (+70 / BASE / HINT) を出すか。 */
    val showsPoints: Boolean = true
)

@Composable
fun QuizVerdictCard(verdict: QuizVerdict) {
    // 問題ごとに出し直すので、問題番号をキーにして毎回ふわっと出す。
    val appear = remember(verdict.number) { Animatable(0f) }
    LaunchedEffect(verdict.number) {
        appear.animateTo(1f, spring(dampingRatio = 0.68f, stiffness = Spring.StiffnessMediumLow))
    }
    Box(
        Modifier.graphicsLayer {
            val p = appear.value
            scaleX = 0.94f + 0.06f * p
            scaleY = 0.94f + 0.06f * p
            alpha = p.coerceIn(0f, 1f)
        }
    ) {
        if (verdict.isCorrect) VerdictCorrect(verdict) else VerdictWrong(verdict)
    }
}

@Composable
private fun HexCapsule(hex: String, fg: Color) {
    Text(
        hex.uppercase(), style = QS.mono(12), color = fg,
        modifier = Modifier.border(1.5.dp, fg, CircleShape).padding(horizontal = 10.dp, vertical = 3.dp)
    )
}

@Composable
private fun VerdictCorrect(v: QuizVerdict) {
    val cardColor = qsColor(v.answerHex, QS.ink)
    val fg = ImasTheme.onColor(cardColor)
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(cardColor)
            .padding(start = 22.dp, end = 22.dp, top = 20.dp, bottom = 22.dp)
            .semantics {
                contentDescription = if (v.showsPoints) "正解。${v.answerName}。${v.earned}点" else "正解。${v.answerName}"
            }
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Q.${twoDigits(v.number)} — CORRECT", style = QS.mono(12, 1.4f), color = fg, modifier = Modifier.weight(1f))
            Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = fg, modifier = Modifier.size(28.dp))
        }
        QSFitText("正解！", QS.text(68, FontWeight.Black), fg)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            v.artworkUrl?.let { ArtworkImage(url = it, size = 64.dp) }
            QSFitText(v.answerName, QS.text(26, FontWeight.Black), fg, maxLines = 2, modifier = Modifier.weight(1f, fill = false))
            v.answerHex?.let { HexCapsule(it, fg) }
        }
        if (v.showsPoints) {
            QuizDashedRule(fg.copy(alpha = 0.45f))
            Row(verticalAlignment = Alignment.Bottom) {
                QSFitText("+${v.earned}", QS.num(110, FontWeight.Black), fg, minScale = 0.5f)
                Spacer(Modifier.weight(1f).width(8.dp))
                Column(horizontalAlignment = Alignment.End, modifier = Modifier.padding(bottom = 10.dp)) {
                    PointsLine("BASE", "+${v.base}", fg)
                    if (v.hints > 0) PointsLine("HINT ×${v.hints}", "−${v.base - v.earned}", fg)
                }
            }
        }
    }
}

@Composable
private fun PointsLine(label: String, value: String, fg: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(label, style = QS.mono(12), color = fg)
        Text(value, style = QS.mono(12), color = fg, textAlign = TextAlign.End, modifier = Modifier.width(40.dp))
    }
}

@Composable
private fun VerdictWrong(v: QuizVerdict) {
    val cardColor = qsColor(v.answerHex, QS.ink)
    val fg = ImasTheme.onColor(cardColor)
    Column(
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(QS.panel)
            .border(1.dp, QS.line, RoundedCornerShape(24.dp))
            .padding(start = 22.dp, end = 22.dp, top = 20.dp, bottom = 22.dp)
            .semantics { contentDescription = "不正解。正解は${v.answerName}" }
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Q.${twoDigits(v.number)} — MISS", style = QS.mono(12, 1.4f), color = QS.dim, modifier = Modifier.weight(1f))
            Icon(Icons.Outlined.Cancel, contentDescription = null, tint = QS.dim, modifier = Modifier.size(28.dp))
        }
        Row(verticalAlignment = Alignment.Bottom) {
            QSFitText("不正解", QS.text(58, FontWeight.Black), QS.dim, modifier = Modifier.weight(1f))
            if (v.showsPoints) Text("+0", style = QS.num(52, FontWeight.Black), color = QS.faint)
        }
        v.pickedName?.let { picked ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("あなたの回答", style = QS.text(13, FontWeight.Bold), color = QS.dim)
                Text(
                    picked, style = QS.text(16, FontWeight.Bold), color = QS.dim, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, textDecoration = TextDecoration.LineThrough
                )
            }
        }
        QuizDashedRule(QS.line)
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("正解は", style = QS.text(13, FontWeight.Bold), color = QS.dim)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(cardColor)
                    .padding(horizontal = 16.dp, vertical = 14.dp)
            ) {
                v.artworkUrl?.let { ArtworkImage(url = it, size = 52.dp) }
                QSFitText(v.answerName, QS.text(26, FontWeight.Black), fg, maxLines = 2, modifier = Modifier.weight(1f))
                v.answerHex?.let { HexCapsule(it, fg) }
            }
            v.detail?.takeIf { it.isNotEmpty() }?.let {
                Text(it, style = QS.text(12), color = QS.dim, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** 解答後の「スコア 300 → 370」「連続正解 4」。 */
@Composable
fun QuizVerdictStats(before: Int, after: Int, streak: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
        StatTile("スコア", Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("$before", style = QS.num(20), color = QS.faint, modifier = Modifier.padding(bottom = 3.dp))
                Icon(
                    Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, tint = QS.faint,
                    modifier = Modifier.size(13.dp).padding(bottom = 1.dp).align(Alignment.CenterVertically)
                )
                Text("$after", style = QS.num(30), color = QS.ink)
            }
        }
        StatTile("連続正解", Modifier.weight(1f)) { Text("$streak", style = QS.num(30), color = QS.ink) }
    }
}

@Composable
private fun StatTile(label: String, modifier: Modifier, value: @Composable () -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(4.dp),
        modifier = modifier
            .fillMaxHeight()
            .clip(RoundedCornerShape(16.dp))
            .background(QS.panel)
            .padding(horizontal = 14.dp, vertical = 12.dp)
    ) {
        Text(label, style = QS.text(12, FontWeight.Bold), color = QS.dim)
        value()
    }
}

/** 生成りの大きなボタン (次の問題へ / もう一度)。 */
@Composable
fun QuizStagePrimaryButton(
    title: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    trailingArrow: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 58.dp)
            .alpha(if (enabled) 1f else 0.45f)
            .quizPress(enabled = enabled, onClick = onClick)
            .clip(RoundedCornerShape(18.dp))
            .background(QS.ink)
            .padding(horizontal = 12.dp)
    ) {
        icon?.let { Icon(it, contentDescription = null, tint = QS.bg, modifier = Modifier.size(18.dp)) }
        Text(title, style = QS.text(18, FontWeight.Black), color = QS.bg, maxLines = 1)
        if (trailingArrow) {
            Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, tint = QS.bg, modifier = Modifier.size(18.dp))
        }
    }
}

/** 枠だけのボタン (一覧へ など)。 */
@Composable
fun QuizStageSecondaryButton(title: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 58.dp)
            .quizPress(onClick = onClick)
            .border(1.dp, QS.line, RoundedCornerShape(18.dp))
            .padding(horizontal = 12.dp)
    ) { Text(title, style = QS.text(15, FontWeight.Bold), color = QS.ink, maxLines = 1) }
}

/** 解答後の「次の問題へ / 結果を見る」。 */
@Composable
fun QuizStageNextButton(isLastQuestion: Boolean, onNext: () -> Unit, onFinish: () -> Unit) {
    QuizStagePrimaryButton(
        title = if (isLastQuestion) "結果を見る" else "次の問題へ",
        trailingArrow = true,
        modifier = Modifier.padding(top = 4.dp)
    ) { if (isLastQuestion) onFinish() else onNext() }
}

/** 不正解のあとに添える一言。 */
@Composable
fun QuizVerdictFootnote() {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(QS.panel)
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Icon(Icons.Filled.Refresh, contentDescription = null, tint = QS.dim, modifier = Modifier.size(20.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("この問題は結果画面から見直せます", style = QS.text(13, FontWeight.Bold), color = QS.ink)
            Text("次に正解すると連続記録がまた始まります", style = QS.text(11), color = QS.dim)
        }
    }
}

// MARK: - 結果

/** グレードのリング内とシェア文言に出す 1 文字。判定そのものはコア。 */
val QuizGrade.label: String get() = name

@Composable
fun QuizStageResultView(
    result: QuizSessionResult,
    isNewBest: Boolean,
    /** 記録する前の自己ベスト (初回は null)。 */
    previousBest: Int?,
    /** 全問ぶんのペンライト (点灯 / 消灯)。 */
    slots: List<QuizPenlight>,
    longestStreak: Int,
    misses: List<QuizMissItem>,
    onReplay: () -> Unit,
    onClose: () -> Unit
) {
    val appear = remember(result) { Animatable(0f) }
    LaunchedEffect(result) {
        kotlinx.coroutines.delay(100)
        appear.animateTo(1f, spring(dampingRatio = 0.62f, stiffness = Spring.StiffnessLow))
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ResultTicket(result, isNewBest, previousBest, longestStreak, appear.value)
        // 問題数が多いと 1 列に並びきらないので出さない。
        if (slots.isNotEmpty() && slots.size <= 20) ResultSetlist(slots)
        if (misses.isNotEmpty()) ResultMissList(misses)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
            QuizStageSecondaryButton("一覧へ", modifier = Modifier.weight(0.8f), onClick = onClose)
            QuizStagePrimaryButton("もう一度", modifier = Modifier.weight(1.2f), icon = Icons.Filled.Refresh, onClick = onReplay)
        }
    }
}

@Composable
private fun ResultTicket(result: QuizSessionResult, isNewBest: Boolean, previousBest: Int?, longestStreak: Int, p: Float) {
    QuizTicket {
        Row(
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 12.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("GRADE", style = QS.mono(11, 1.6f), color = QS.paperSub)
                Text(
                    result.grade.label, style = QS.num(140, FontWeight.Black), color = QS.paperInk, maxLines = 1,
                    modifier = Modifier.graphicsLayer {
                        val s = 1.6f - 0.6f * p
                        scaleX = s; scaleY = s
                        alpha = p.coerceIn(0f, 1f)
                    }
                )
            }
            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.weight(1f)
            ) {
                Text("SCORE", style = QS.mono(11, 1.6f), color = QS.paperSub)
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("${result.points}", style = QS.num(58, FontWeight.Black), color = QS.paperInk)
                    Text(
                        "/ ${result.maxPoints} pt", style = QS.text(13, FontWeight.Bold), color = QS.paperSub,
                        modifier = Modifier.padding(bottom = 6.dp)
                    )
                }
                Text(
                    "${result.correct} / ${result.questions} 正解 · 最大 $longestStreak 連続",
                    style = QS.text(13, FontWeight.Bold), color = QS.paperInk, textAlign = TextAlign.End
                )
                if (isNewBest) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(1.dp),
                        modifier = Modifier
                            .padding(top = 4.dp)
                            .graphicsLayer {
                                val s = 1.8f - 0.8f * p
                                scaleX = s; scaleY = s
                                alpha = p.coerceIn(0f, 1f)
                            }
                            .rotate(-5f)
                            .border(2.dp, QS.stamp, RoundedCornerShape(8.dp))
                            .padding(horizontal = 10.dp, vertical = 4.dp)
                    ) {
                        Text("自己ベスト更新", style = QS.text(13, FontWeight.Black), color = QS.stamp)
                        previousBest?.let { Text("$it → ${result.points}", style = QS.mono(11), color = QS.stamp) }
                    }
                }
                Text(result.comment, style = QS.text(12), color = QS.paperSub, textAlign = TextAlign.End)
            }
        }
        QuizTicketNotch()
        GradeLadder(result.grade)
    }
}

/** グレードの目安 (正答率の閾値はコアの `QuizGrade::from_rate` と同じ)。 */
@Composable
private fun GradeLadder(current: QuizGrade) {
    val rungs = listOf(
        QuizGrade.S to "95%〜", QuizGrade.A to "80%〜", QuizGrade.B to "60%〜",
        QuizGrade.C to "40%〜", QuizGrade.D to "〜39%"
    )
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, top = 8.dp, bottom = 14.dp)
    ) {
        rungs.forEach { (grade, range) ->
            val on = grade == current
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(1.dp),
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (on) QS.paperInk else Color.Transparent)
                    .padding(vertical = 6.dp)
            ) {
                Text(grade.label, style = QS.num(22), color = if (on) QS.ink else QS.paperSub)
                Text(range, style = QS.mono(10), color = if (on) QS.ink else QS.paperSub)
            }
        }
    }
}

@Composable
private fun ResultSetlist(slots: List<QuizPenlight>) {
    val lit = slots.count { it is QuizPenlight.Lit }
    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(QS.panel)
            .padding(start = 14.dp, end = 14.dp, top = 12.dp, bottom = 14.dp)
            .semantics { contentDescription = "${slots.size}問中${lit}問正解" }
    ) {
        Row {
            Text("今回のセトリ", style = QS.text(12, FontWeight.Bold), color = QS.dim, modifier = Modifier.weight(1f))
            Text("$lit 本点灯", style = QS.text(12, FontWeight.Bold), color = QS.dim)
        }
        QuizPenlightRow(slots, numbered = true)
    }
}

@Composable
private fun ResultMissList(misses: List<QuizMissItem>) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(QS.panel)
            .padding(bottom = 4.dp)
    ) {
        Text(
            "見直す", style = QS.text(12, FontWeight.Bold), color = QS.dim,
            modifier = Modifier.padding(start = 14.dp, end = 14.dp, top = 12.dp, bottom = 4.dp)
        )
        misses.forEachIndexed { i, miss ->
            if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(QS.rowLine))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 14.dp, vertical = 6.dp)
            ) {
                Box(Modifier.size(22.dp).clip(CircleShape).background(qsColor(miss.hex, QS.line)))
                Text("Q.${twoDigits(miss.number)}", style = QS.mono(11), color = QS.dim)
                Column(verticalArrangement = Arrangement.spacedBy(1.dp), modifier = Modifier.weight(1f)) {
                    Text(miss.title, style = QS.text(15, FontWeight.Bold), color = QS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    miss.picked?.let {
                        Text("あなた: $it", style = QS.text(11), color = QS.faint, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

// MARK: - 画面の骨組み

/** 上部の出し分け。出題中は「ゲーム名 / Q.04 / 10」と SCORE、結果では「RESULT / ゲーム名 · 全10問」。 */
@Immutable
sealed interface QuizStageHeader {
    data class Question(val current: Int, val total: Int, val points: Int) : QuizStageHeader
    data class Result(val total: Int) : QuizStageHeader

    /** 読み込み中・出題できないとき。 */
    data object None : QuizStageHeader
}

/**
 * ステージ画面の骨組み。上部に丸い × とゲーム名・問題番号・SCORE を置き、本文はスクロールする縦並び。
 * [scrollKey] が変わるたびに先頭へ戻す (解答で判定カードに差し替わったとき、下の方を見ていても
 * 判定が目に入るように)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuizStageScaffold(
    title: String,
    header: QuizStageHeader,
    onClose: () -> Unit,
    scrollKey: Any? = null,
    trailing: @Composable RowScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit
) {
    // iOS と同じく、ステージの間は下のタブバーを隠して会場を全画面で見せる。
    BottomBarVisibility.Hide()
    val scroll = rememberScrollState()
    LaunchedEffect(scrollKey) { if (scroll.value > 0) scroll.animateScrollTo(0) }
    Scaffold(
        containerColor = QS.bg,
        topBar = {
            CenterAlignedTopAppBar(
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                    containerColor = QS.bg, scrolledContainerColor = QS.bg,
                    titleContentColor = QS.ink, navigationIconContentColor = QS.ink, actionIconContentColor = QS.ink
                ),
                navigationIcon = {
                    Box(Modifier.padding(start = 12.dp)) {
                        QuizStageRoundButton(Icons.Filled.Close, "クイズを終了", onClick = onClose)
                    }
                },
                title = {
                    when (header) {
                        is QuizStageHeader.Question -> QuizStageTitle(title, header.current, header.total)
                        is QuizStageHeader.Result -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("RESULT", style = QS.num(24).copy(letterSpacing = 1.sp), color = QS.ink)
                            Text("$title · 全${header.total}問", style = QS.text(11, FontWeight.Bold), color = QS.dim)
                        }
                        QuizStageHeader.None -> Text(title, style = QS.text(15, FontWeight.Bold), color = QS.ink)
                    }
                },
                actions = {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(end = 16.dp)
                    ) {
                        if (header is QuizStageHeader.Question) QuizStageScore(header.points) else trailing()
                    }
                }
            )
        }
    ) { padding ->
        Column(
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(scroll)
                .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 34.dp),
            content = content
        )
    }
}

/** 読み込み中 (ステージ色)。 */
@Composable
fun QuizStageLoading() {
    Box(Modifier.fillMaxWidth().padding(top = 60.dp), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(color = QS.ink)
    }
}

/** 出題できないとき (ステージ色)。 */
@Composable
fun QuizStageEmpty(icon: ImageVector, title: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.fillMaxWidth().padding(vertical = 40.dp, horizontal = 24.dp)
    ) {
        Box(
            Modifier.size(52.dp).clip(RoundedCornerShape(16.dp)).background(QS.panel),
            contentAlignment = Alignment.Center
        ) { Icon(icon, contentDescription = null, tint = QS.dim, modifier = Modifier.size(28.dp)) }
        Text(title, style = QS.text(17, FontWeight.Bold), color = QS.ink, textAlign = TextAlign.Center)
    }
}

// MARK: - 曲ものチケット (ソロ曲・セトリ当て・メンバーカラー 4 択)

/** 「SOLO SONG ・ +100 / この曲を歌っているのは？」のチケット上部。本文 (曲名など) は content に置く。 */
@Composable
fun QuizTicketTitleBlock(
    label: String,
    question: String,
    value: Int,
    base: Int,
    content: @Composable ColumnScope.() -> Unit
) {
    val shown by animateIntAsState(value, tween(350), label = "value")
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 18.dp)
    ) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(label, style = QS.mono(11, 1.4f), color = QS.paperSub, modifier = Modifier.weight(1f).padding(bottom = 3.dp))
            Row(
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier.semantics { contentDescription = "正解で${value}点" }
            ) {
                Text("+$shown", style = QS.num(22), color = QS.paperInk)
                if (value < base) {
                    Text(
                        "$base", style = QS.num(15, FontWeight.Bold), color = QS.paperSub,
                        textDecoration = TextDecoration.LineThrough, modifier = Modifier.padding(bottom = 2.dp)
                    )
                }
            }
        }
        Text(question, style = QS.text(15, FontWeight.Bold), color = QS.paperSub)
        content()
    }
}

/** ヒントタイルの状態。 */
@Immutable
sealed interface QuizHintPhase {
    data class Available(val cost: Int, val onOpen: () -> Unit) : QuizHintPhase
    data class Open(val value: String) : QuizHintPhase

    /** 開いた色ヒント (イメージカラーなど)。色の帯と名前を出す。 */
    data class OpenSwatch(val hex: String, val label: String) : QuizHintPhase

    /** まだ開けない (前のヒントを開くと開ける)。 */
    data class Locked(val cost: Int) : QuizHintPhase
}

@Immutable
data class QuizHintTileSpec(val key: String, val title: String, val phase: QuizHintPhase)

/** 横に並ぶヒントのタイル。未開封は点線枠の「収録CD −10」、開封済みは中身、まだ開けないものは薄く。 */
@Composable
fun QuizTicketHintTile(title: String, phase: QuizHintPhase, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(14.dp)
    val base = modifier.fillMaxWidth().heightIn(min = 56.dp)
    when (phase) {
        is QuizHintPhase.Available -> Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = base
                .quizPress(onClick = phase.onOpen)
                .dashedBorder(QS.paperMuted, 1.5.dp, 14.dp)
                .padding(horizontal = 4.dp, vertical = 6.dp)
                .semantics { contentDescription = "${title}のヒントを開く。${phase.cost}点下がります" }
        ) {
            Text(title, style = QS.text(13, FontWeight.Bold), color = QS.paperInk, maxLines = 2, textAlign = TextAlign.Center)
            Text("−${phase.cost}", style = QS.num(16), color = QS.paperSub)
        }
        is QuizHintPhase.Open -> Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = base.clip(shape).background(QS.paperTile).padding(horizontal = 6.dp, vertical = 6.dp)
        ) {
            Text(title, style = QS.text(11, FontWeight.Bold), color = QS.paperSub, maxLines = 1)
            QSFitText(phase.value, QS.text(15, FontWeight.Black), QS.paperInk, textAlign = TextAlign.Center)
        }
        is QuizHintPhase.OpenSwatch -> Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
            modifier = base.clip(shape).background(QS.paperTile).padding(horizontal = 6.dp, vertical = 6.dp)
                .semantics { contentDescription = "$title: ${phase.label}" }
        ) {
            Text(title, style = QS.text(11, FontWeight.Bold), color = QS.paperSub, maxLines = 1)
            Box(
                Modifier.size(width = 44.dp, height = 14.dp).clip(RoundedCornerShape(4.dp))
                    .background(qsColor(phase.hex, QS.paperMuted))
                    .border(1.dp, QS.paperLine, RoundedCornerShape(4.dp))
            )
        }
        is QuizHintPhase.Locked -> Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = base.dashedBorder(QS.paperLine, 1.5.dp, 14.dp).padding(horizontal = 4.dp, vertical = 6.dp)
                .semantics { contentDescription = "${title}のヒント (前のヒントを開くと開けます)" }
        ) {
            Text(title, style = QS.text(13, FontWeight.Bold), color = QS.paperMuted, maxLines = 2, textAlign = TextAlign.Center)
            Text("−${phase.cost}", style = QS.num(16), color = QS.paperMuted)
        }
    }
}

/** ヒントタイルの並び (見出し付き)。[columns] を渡すとその列数で折り返す (ヒントが多いクイズ用)。 */
@Composable
fun QuizTicketHintTiles(tiles: List<QuizHintTileSpec>, showsHeading: Boolean = true, columns: Int? = null) {
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 8.dp, bottom = 14.dp)
    ) {
        if (showsHeading) {
            Text(
                "ヒント — 開くほど点が下がる", style = QS.text(11, FontWeight.Bold), color = QS.paperSub,
                modifier = Modifier.padding(start = 8.dp)
            )
        }
        val perRow = columns ?: tiles.size.coerceAtLeast(1)
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            tiles.chunked(perRow).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
                    row.forEach { spec ->
                        QuizTicketHintTile(spec.title, spec.phase, Modifier.weight(1f).fillMaxHeight())
                    }
                    if (columns != null) repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}
