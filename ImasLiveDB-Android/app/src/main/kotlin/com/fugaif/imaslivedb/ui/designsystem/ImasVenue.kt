package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasColorsLight
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.LocalImasColors
import com.fugaif.imaslivedb.ui.theme.imasPress

// =============================================================================
// 会場とチケットの部品 (docs/DESIGN_SYSTEM.md §1・§6.7)。iOS `ImasVenue.swift` の移植。
//
// ImasTicketShape   切り取り線の両端に半円の切り欠きがある紙の形。
// ImasPerforation   切り取り線 (点線)。
// ImasTicket        紙のチケット。次のライブ・次の出演。右の半券に「あと 37 DAYS」。
// ImasBoard         電光掲示板。記録や出演の数を暗い板に細長い数字で。
// ImasMasthead      画面の頭の印字の行 (「PRODUCE · 2026.10.01 THU」)。
//
// チケットの紙 (`DS.ticket`) はダークでも明るいまま。暗い客席で手元のチケットだけが白く見える。
// =============================================================================

// MARK: - 紙の形

/**
 * チケットの形。角丸の四角に、切り取り線の両端の半円の切り欠き (iOS `ImasTicketShape`)。
 * 背景の形 (`Modifier.background(color, shape)`) や影の形に使う。
 */
@Immutable
class ImasTicketShape(
    private val cornerRadius: Dp,
    private val cut: Cut,
    private val notchRadius: Dp = 10.dp
) : Shape {

    /** 切り取り線の位置。 */
    @Immutable
    sealed interface Cut {
        /** 縦の切り取り線。右端からの距離 (半券の幅)。 */
        data class Vertical(val fromTrailing: Dp) : Cut

        /** 横の切り取り線。上端からの距離。 */
        data class Horizontal(val fromTop: Dp) : Cut

        /** 縦の切り取り線。左端からの距離 (半券の行の日付の幅)。 */
        data class VerticalFromLeading(val fromLeading: Dp) : Cut

        /** 切り欠き無し (ただの角丸)。 */
        data object None : Cut
    }

    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val r = with(density) { cornerRadius.toPx() }
        val n = with(density) { notchRadius.toPx() }
        val base = Path().apply {
            addRoundRect(RoundRect(0f, 0f, size.width, size.height, CornerRadius(r)))
        }
        val rtl = layoutDirection == LayoutDirection.Rtl
        val notches = Path()
        when (val c = cut) {
            Cut.None -> return Outline.Generic(base)
            is Cut.Vertical -> {
                val d = with(density) { c.fromTrailing.toPx() }
                val x = if (rtl) d else size.width - d
                notches.addOval(Rect(center = Offset(x, 0f), radius = n))
                notches.addOval(Rect(center = Offset(x, size.height), radius = n))
            }
            is Cut.VerticalFromLeading -> {
                val d = with(density) { c.fromLeading.toPx() }
                val x = if (rtl) size.width - d else d
                notches.addOval(Rect(center = Offset(x, 0f), radius = n))
                notches.addOval(Rect(center = Offset(x, size.height), radius = n))
            }
            is Cut.Horizontal -> {
                val y = with(density) { c.fromTop.toPx() }
                notches.addOval(Rect(center = Offset(0f, y), radius = n))
                notches.addOval(Rect(center = Offset(size.width, y), radius = n))
            }
        }
        val result = Path().apply { op(base, notches, PathOperation.Difference) }
        return Outline.Generic(result)
    }

    override fun equals(other: Any?): Boolean =
        other is ImasTicketShape && other.cornerRadius == cornerRadius && other.cut == cut &&
            other.notchRadius == notchRadius

    override fun hashCode(): Int = (cornerRadius.hashCode() * 31 + cut.hashCode()) * 31 + notchRadius.hashCode()
}

// MARK: - 切り取り線

/** 切り取り線の向き。 */
enum class ImasPerforationAxis { HORIZONTAL, VERTICAL }

/**
 * 切り取り線 (点線)。チケットの半券の境目・セトリや申込書の欄の区切り (iOS `ImasPerforation`)。
 *
 * 横は幅いっぱい、縦は高さいっぱいに引く (縦のときは親の高さが決まっていること)。
 * 読み上げには出さない (飾り)。
 *
 * @param color 線の色。チケットの紙の上は `DS.ticketDash`、面の上は `DS.perforation` (既定)。
 */
@Composable
fun ImasPerforation(
    modifier: Modifier = Modifier,
    axis: ImasPerforationAxis = ImasPerforationAxis.HORIZONTAL,
    color: Color = DS.perforation,
    lineWidth: Dp = 1.dp
) {
    val thickness = maxOf(lineWidth, 1.dp)
    val sized = when (axis) {
        ImasPerforationAxis.HORIZONTAL -> modifier.fillMaxWidth().height(thickness)
        ImasPerforationAxis.VERTICAL -> modifier.fillMaxHeight().width(thickness)
    }
    Canvas(sized.clearAndSetSemantics { }) {
        val w = lineWidth.toPx()
        when (axis) {
            ImasPerforationAxis.HORIZONTAL ->
                drawImasDash(Offset(0f, size.height / 2), Offset(size.width, size.height / 2), color, w)
            ImasPerforationAxis.VERTICAL ->
                drawImasDash(Offset(size.width / 2, 0f), Offset(size.width / 2, size.height), color, w)
        }
    }
}

// MARK: - チケット

/** チケットの半券のカウントダウン (「あと / 37 / DAYS」)。 */
@Immutable
data class ImasTicketCountdown(
    val value: String,
    val prefix: String = "あと",
    val unit: String = "DAYS"
)

/**
 * 紙のチケット。次のライブ・次の出演・参加を記録するときの公演 (iOS `ImasTicket`)。
 *
 * 構成は [ペンライト + 印字の目印] / [題 (18 極太・詰め組み)] / [日付・会場の行] と、
 * 右の半券の「あと 37 DAYS」。紙はダークでも明るい。押すとその公演へ ([onOpen])。
 *
 * @param label 目印 (「参加予定」「次の出演」)。前の印字は [imprint] (既定 ADMIT ONE)。
 * @param metaImprint 日付・会場の行の先頭の印字 (「11.07 SAT」)。
 * @param metaIcon [meta] の前に置く小さな記号 (会場なら場所の印など)。
 * @param seed ペンライトの色の手がかり (担当の色 hex)。[brand] (ブランド ID) と合わせて、無ければペンライトを出さない。
 */
@Composable
fun ImasTicket(
    label: String,
    title: String,
    modifier: Modifier = Modifier,
    imprint: String? = "ADMIT ONE",
    metaImprint: String? = null,
    meta: String? = null,
    metaIcon: ImageVector? = null,
    seed: String? = null,
    brand: String? = null,
    countdown: ImasTicketCountdown? = null,
    onOpen: (() -> Unit)? = null
) {
    // iOS の @ScaledMetric(relativeTo: .body) 96。文字の大きさに合わせて半券も広げる。
    val stubWidth = with(LocalDensity.current) { 96.sp.toDp() }
    val shape = ImasTicketShape(
        cornerRadius = 14.dp,
        cut = if (countdown == null) ImasTicketShape.Cut.None else ImasTicketShape.Cut.Vertical(stubWidth + 1.dp)
    )
    // チケットの紙は明るいので、ダークでもライト用の色でペンライトを点ける。
    val penlight: Color? = if (seed != null || brand != null) {
        val t = ImasTheme.forBrand(seed, brand, dark = false)
        if (t.isNeutral) ImasColorsLight.ink else t.dot
    } else null
    val dash = DS.ticketDash
    val ticketSub = DS.ticketSub
    val ticketInk = DS.ticketInk

    Row(
        modifier
            .fillMaxWidth()
            // 押したときに紙ごと縮むよう、押し心地 (graphicsLayer) を紙の塗りより外に置く。
            .then(if (onOpen != null) Modifier.imasPress(onClick = onOpen) else Modifier.semantics(mergeDescendants = true) { })
            .imasSoftShadow(shape, fill = DS.ticket, color = Color.Black.copy(alpha = 0.06f), blur = 9.dp, offsetY = 4.dp)
            .drawBehind {
                if (countdown != null) {
                    // 半券の境目の切り取り線 (上下 12 空ける)。
                    val x = size.width - (stubWidth + 1.dp).toPx()
                    drawImasDash(Offset(x, 12.dp.toPx()), Offset(x, size.height - 12.dp.toPx()), dash, 2.dp.toPx())
                }
            },
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(
            Modifier
                .weight(1f)
                .padding(start = 16.dp, end = 14.dp, top = 14.dp, bottom = 14.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    listOfNotNull(imprint, label).joinToString(" · "),
                    style = ImasTextRole.IMPRINT.style,
                    color = ticketSub,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Text(title, style = ImasType.heading(18.sp, FontWeight.ExtraBold), color = ticketInk)
            if (metaImprint != null || meta != null) {
                Text(
                    buildAnnotatedString {
                        if (metaImprint != null) {
                            withStyle(SpanStyle(fontFamily = ImasType.monoFamily, fontSize = 11.sp, fontWeight = FontWeight.Medium)) {
                                append(metaImprint)
                                if (meta != null) append(" · ")
                            }
                        }
                        if (metaIcon != null) {
                            // 代わりの文字は空にできない (Compose が IllegalArgumentException で落とす)。
                            // 記号は飾りなので読み上げに残らない空白にする。
                            appendInlineContent(TicketMetaIconId, " ")
                            append(" ")
                        }
                        if (meta != null) withStyle(SpanStyle(fontSize = 13.sp)) { append(meta) }
                    },
                    color = ticketSub,
                    inlineContent = if (metaIcon == null) emptyMap() else mapOf(
                        TicketMetaIconId to InlineTextContent(
                            Placeholder(13.sp, 13.sp, PlaceholderVerticalAlign.TextCenter)
                        ) { Icon(metaIcon, contentDescription = null, tint = ticketSub) }
                    )
                )
            }
        }
        if (countdown != null) {
            // 切り取り線の分 (drawBehind で引く)。
            Spacer(Modifier.width(2.dp))
            Column(
                Modifier
                    .width(stubWidth)
                    .padding(vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(countdown.prefix, style = ImasTextRole.IMPRINT.style, color = ticketSub, maxLines = 1)
                ImasFitText(countdown.value, style = ImasNumeralSize.COUNTDOWN.style, color = ticketInk, minScale = 0.6f)
                Text(countdown.unit, style = ImasTextRole.IMPRINT.style, color = ticketSub, maxLines = 1)
            }
        }
    }
}

/** チケットの日付・会場の行の記号の置き場の名前 (`appendInlineContent` の鍵)。 */
private const val TicketMetaIconId = "ticketMetaIcon"

// MARK: - 電光掲示板

/** 電光掲示板の数 1 つ。 */
@Immutable
data class ImasBoardCell(
    val value: String,
    val label: String,
    val unit: String? = null
)

/**
 * 電光掲示板 (iOS `ImasBoard`)。記録や出演の数を、暗い板に細長い太字の数字で並べる。
 *
 * 上の行は印字 (「STATS」「2005 — 2026」)。数は 2〜4 個。ライトでもダークでも板は暗い。
 * [onSelect] を渡すと、数を押してその記録の一覧へ進める。
 *
 * @param shape 板の形。名札の下につなげるとき (`ImasIdolHeader`) は下の角だけ丸める。
 */
@Composable
fun ImasBoard(
    cells: List<ImasBoardCell>,
    modifier: Modifier = Modifier,
    title: String? = null,
    trailing: String? = null,
    onSelect: ((ImasBoardCell) -> Unit)? = null,
    shape: Shape = RoundedCornerShape(18.dp)
) {
    val boardDim = DS.boardDim
    val boardLine = DS.boardLine
    Column(
        modifier
            .fillMaxWidth()
            .background(DS.board, shape)
    ) {
        if (title != null || trailing != null) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(start = 14.dp, end = 14.dp, top = 12.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (title != null) Text(title, style = ImasTextRole.IMPRINT.style, color = boardDim, maxLines = 1)
                Spacer(Modifier.weight(1f))
                if (trailing != null) {
                    Text(
                        trailing,
                        style = ImasTextRole.IMPRINT.style,
                        color = boardDim,
                        maxLines = 1,
                        modifier = Modifier.padding(start = 8.dp)
                    )
                }
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(boardLine))
        }
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
            cells.forEachIndexed { index, cell ->
                if (index > 0) {
                    Box(
                        Modifier
                            .padding(vertical = 10.dp)
                            .width(1.dp)
                            .fillMaxHeight()
                            .background(boardLine)
                    )
                }
                ImasBoardCellView(cell, Modifier.weight(1f), onSelect)
            }
        }
    }
}

@Composable
private fun ImasBoardCellView(cell: ImasBoardCell, modifier: Modifier, onSelect: ((ImasBoardCell) -> Unit)?) {
    val press = if (onSelect != null) Modifier.imasPress { onSelect(cell) } else Modifier.semantics(mergeDescendants = true) { }
    Column(
        modifier
            .then(press)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            ImasFitText(
                cell.value,
                style = ImasNumeralSize.LARGE.style,
                color = DS.boardInk,
                minScale = 0.7f,
                modifier = Modifier.alignByBaseline().weight(1f, fill = false)
            )
            if (cell.unit != null) {
                Text(
                    cell.unit,
                    style = ImasType.text(11.sp, FontWeight.SemiBold),
                    color = DS.boardDim,
                    maxLines = 1,
                    modifier = Modifier.alignByBaseline()
                )
            }
        }
        Text(
            cell.label,
            style = ImasType.text(11.sp),
            color = DS.boardDim,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

// MARK: - 頭の印字

/**
 * 画面の頭の印字の行 (「PRODUCE · 2026.10.01 THU」「SETLIST · DAY2」)。大きな題の上に置く (iOS `ImasMasthead`)。
 * 日付はコアの `mastheadDate(date)` で作る。読み上げには出さない (題が言う)。
 */
@Composable
fun ImasMasthead(items: List<String>, modifier: Modifier = Modifier) {
    Text(
        items.joinToString(" · "),
        style = ImasTextRole.IMPRINT.style,
        color = ImasTextRole.IMPRINT.color,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier.clearAndSetSemantics { }
    )
}

/** [ImasMasthead] の並べ書き (`ImasMasthead("PRODUCE", mastheadDate(today))`)。 */
@Composable
fun ImasMasthead(vararg items: String) = ImasMasthead(items.toList())
