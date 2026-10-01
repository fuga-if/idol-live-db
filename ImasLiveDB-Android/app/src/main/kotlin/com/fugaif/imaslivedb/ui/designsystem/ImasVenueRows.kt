package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.components.CopyItem
import com.fugaif.imaslivedb.ui.components.Copyable
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasMotion
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasPenlight
import com.fugaif.imaslivedb.ui.theme.ImasPenlightSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand
import com.fugaif.imaslivedb.ui.theme.penlight
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import uniffi.imas_core.WeekdayKind
import uniffi.imas_core.ticketStubDate
import java.io.File
import kotlin.math.abs

// =============================================================================
// 会場の行と札 (docs/DESIGN_SYSTEM.md §5.4・§5.5・§6.6・§6.7)。iOS `ImasVenueRows.swift` の移植。
//
// ImasStubRow      半券の行。左の半券に日付 (月・日・曜日)、切り取り線、右に題と会場。
//                  ライブ・公演・記録の一覧の 1 行。
// ImasTicketRow    半券の形の短い行 (チケットの受付・取り込みの誘い)。左に記号、右に〆切。
// ImasPass         入場証 (担当・アカウント)。上の帯が実体の色、ストラップの穴、名前を大きく。
// ImasTicketStack  参加予定のチケットの束。いちばん上を大きく、後ろの 2 枚は端だけ見せる。
//                  横に払って次のチケットへ。
// ImasIdolHeader   アイドル詳細の頭。名札 (色の帯・名前・担当) と電光掲示板を 1 枚につなげる。
// ImasIdolCell     アイドルの名札 (格子の 1 つ)。上の帯が担当色。担当は輪が二重。
// ImasBrandPicker  ブランドを選ぶ。チップを折り返して並べる (ペンライト、ロゴを入れたブランドはロゴ)。
// =============================================================================

// MARK: - 半券の日付

/** 半券の曜日の種類 (色を分けるため)。 */
enum class ImasStubWeekday { WEEKDAY, SATURDAY, SUNDAY, UNKNOWN }

/**
 * 半券の日付欄の中身 (iOS `ImasStubDate`)。月の略号と曜日はコア (`ticketStubDate`) が決める。
 * `ImasStubDate("2026-11-07")` (年月だけ・年だけも可) で作る。
 */
@Immutable
data class ImasStubDate(
    val top: String,
    val big: String,
    val bottom: String,
    val kind: ImasStubWeekday = ImasStubWeekday.UNKNOWN
) {
    /** 曜日の色。土日だけ色、平日・不明は灰。 */
    val weekdayColor: Color
        @Composable get() = when (kind) {
            ImasStubWeekday.SATURDAY -> DS.saturday
            ImasStubWeekday.SUNDAY -> DS.sunday
            ImasStubWeekday.WEEKDAY, ImasStubWeekday.UNKNOWN -> DS.ink2
        }

    companion object {
        /** 日付ごとのメモ (一覧の行が組まれるたびに FFI を跨がない。日付の種類は有界)。 */
        private val cache = HashMap<String, ImasStubDate>()

        /** `yyyy-MM-dd` (年月だけ・年だけも可) から。 */
        operator fun invoke(date: String): ImasStubDate = synchronized(cache) {
            cache.getOrPut(date) {
                val stub = ticketStubDate(date)
                ImasStubDate(
                    top = stub.top,
                    big = stub.big,
                    bottom = stub.bottom,
                    kind = when (stub.weekdayKind) {
                        WeekdayKind.WEEKDAY -> ImasStubWeekday.WEEKDAY
                        WeekdayKind.SATURDAY -> ImasStubWeekday.SATURDAY
                        WeekdayKind.SUNDAY -> ImasStubWeekday.SUNDAY
                        WeekdayKind.UNKNOWN -> ImasStubWeekday.UNKNOWN
                    }
                )
            }
        }

        /** 日付が無いとき (横棒)。 */
        val Unknown = ImasStubDate(top = "", big = "—", bottom = "")
    }
}

// MARK: - 半券の行

/**
 * 半券の行 (iOS `ImasStubRow`)。ライブ・公演・記録 (支出) の一覧の 1 行。
 *
 * 行の間は空けて地を透かす (区切り線は出さない。一覧に置くときは上下 4・左右は画面の余白を空ける)。
 * 行を引く操作は呼び出し側で `ImasSwipe` に包む (右に引く = 参加・参加予定)。
 *
 * @param seed ペンライトの色 hex。[brand] はブランド ID。色の帯 (ペンライト) は副題の有無によらずいつも出す。
 * @param isPunched 参加した (半券に穴を開ける)。**記録の印には使わない** (§1-2。参加は札で出す)。iOS と揃えるために残す。
 * @param rainbow 合同ライブ等、単色で表せないとき、ペンライトを虹色にする。
 * @param spokenDate 読み上げの日付 (コアの `spokenDate(date)`、「2026年11月7日 土曜日」)。無ければ日付欄をそのまま読む。
 * @param showsChevron 別画面へ進む矢印 (押して詳細へ行く一覧)。
 */
@Composable
fun ImasStubRow(
    date: ImasStubDate,
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    seed: String? = null,
    brand: String? = null,
    isPunched: Boolean = false,
    badges: List<ImasBadgeSpec> = emptyList(),
    emphasis: ImasRowEmphasis = ImasRowEmphasis.NORMAL,
    rainbow: Boolean = false,
    spokenDate: String? = null,
    showsChevron: Boolean = false,
    detail: (@Composable ColumnScope.() -> Unit)? = null
) {
    // iOS の @ScaledMetric(relativeTo: .body) 62。文字の大きさに合わせて半券も広げる。
    val stubWidth = with(LocalDensity.current) { 62.sp.toDp() }
    val penlight = if (seed != null || brand != null) imasThemeForBrand(seed, brand).penlight else null
    val dimmed = emphasis == ImasRowEmphasis.DIMMED
    val perforation = DS.perforation
    val spoken = listOfNotNull(
        spokenDate ?: listOf(date.top, date.big, date.bottom).joinToString(" "),
        title,
        subtitle,
        badges.takeIf { it.isNotEmpty() }?.joinToString("、") { it.text },
        if (isPunched) "参加済み" else null
    ).joinToString("、")
    val shape = ImasTicketShape(12.dp, ImasTicketShape.Cut.VerticalFromLeading(stubWidth + 1.dp), notchRadius = 6.dp)
    Row(
        modifier
            .fillMaxWidth()
            .background(DS.surface, shape)
            .drawBehind {
                val x = (stubWidth + 1.dp).toPx()
                drawImasDash(Offset(x, 8.dp.toPx()), Offset(x, size.height - 8.dp.toPx()), perforation, 2.dp.toPx())
            }
            .semantics(mergeDescendants = true) { contentDescription = spoken },
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(stubWidth)) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                val small = ImasType.mono(9.5.sp, FontWeight.Medium).copy(letterSpacing = 0.8.sp)
                if (date.top.isNotEmpty()) Text(date.top, style = small, color = DS.ink2, maxLines = 1)
                ImasFitText(
                    date.big,
                    style = if (date.big.length > 3) ImasNumeralSize.MEDIUM.style else ImasNumeralSize.DATE.style,
                    color = if (dimmed) DS.ink3 else DS.ink,
                    minScale = 0.6f
                )
                if (date.bottom.isNotEmpty()) Text(date.bottom, style = small, color = date.weekdayColor, maxLines = 1)
            }
            if (isPunched) {
                ImasPunchHole(size = ImasPunchHoleSize.SMALL, modifier = Modifier.align(Alignment.TopEnd).padding(6.dp))
            }
        }
        // 切り取り線の分 (drawBehind で引く)。
        Spacer(Modifier.width(2.dp))
        Column(
            Modifier
                .weight(1f)
                .padding(start = 12.dp, end = 14.dp, top = 10.dp, bottom = 10.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                title,
                style = ImasType.heading(14.5.sp, FontWeight.ExtraBold),
                color = if (dimmed) DS.ink3 else DS.ink,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis
            )
            if (penlight != null || subtitle != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (penlight != null) ImasPenlight(color = penlight, size = ImasPenlightSize.SMALL, rainbow = rainbow)
                    if (subtitle != null) {
                        Text(subtitle, style = ImasType.text(12.sp), color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            if (badges.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    badges.forEach { ImasBadge(it.text, kind = it.kind, seed = it.seed) }
                }
            }
            detail?.invoke(this)
        }
        if (showsChevron) ImasRowChevron(Modifier.padding(end = 14.dp))
    }
}

// MARK: - 半券の形の短い行

/**
 * 半券の形の短い行 (iOS `ImasTicketRow`)。チケットの受付 (〆切)・取り込みの誘いなど「紙で持つもの」の 1 行。
 *
 * @param deadline 右の印字 (〆切の日付・時刻)。[isUrgent] なら朱。
 * @param onClick 押すと進む (矢印を出す)。
 */
@Composable
fun ImasTicketRow(
    title: String,
    modifier: Modifier = Modifier,
    icon: ImageVector = Icons.Filled.ConfirmationNumber,
    subtitle: String? = null,
    deadline: String? = null,
    isUrgent: Boolean = false,
    onClick: (() -> Unit)? = null
) {
    val iconColumn = with(LocalDensity.current) { 44.sp.toDp() }
    val dash = DS.ticketDash
    val shape = ImasTicketShape(12.dp, ImasTicketShape.Cut.VerticalFromLeading(iconColumn + 1.dp), notchRadius = 6.dp)
    val stamp = DS.stamp
    val ticketInk = DS.ticketInk
    Row(
        modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.imasPress(onClick = onClick) else Modifier.semantics(mergeDescendants = true) { })
            .background(DS.ticket, shape)
            .drawBehind {
                val x = (iconColumn + 1.dp).toPx()
                drawImasDash(Offset(x, 8.dp.toPx()), Offset(x, size.height - 8.dp.toPx()), dash, 2.dp.toPx())
            },
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(iconColumn), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = ticketInk, modifier = Modifier.size(with(LocalDensity.current) { 20.sp.toDp() }))
        }
        Spacer(Modifier.width(2.dp))
        Column(
            Modifier
                .weight(1f)
                .padding(start = 12.dp, top = 10.dp, bottom = 10.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(title, style = ImasType.heading(14.5.sp, FontWeight.Bold), color = ticketInk)
            if (subtitle != null) Text(subtitle, style = ImasType.text(12.sp), color = DS.ticketSub)
        }
        Spacer(Modifier.width(DS.Space.gap))
        if (deadline != null) {
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(fontSize = 12.sp, fontWeight = FontWeight.ExtraBold, color = stamp, fontFeatureSettings = "palt")) {
                        append("〆 ")
                    }
                    withStyle(
                        SpanStyle(
                            fontFamily = ImasType.monoFamily,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (isUrgent) stamp else ticketInk
                        )
                    ) { append(deadline) }
                },
                maxLines = 1,
                modifier = Modifier.padding(end = if (onClick == null) 14.dp else 4.dp)
            )
        }
        if (onClick != null) ImasRowChevron(Modifier.padding(end = 14.dp), tint = DS.ticketSub)
    }
}

// MARK: - 入場証

/**
 * 入場証 (iOS `ImasPass`)。担当・アカウントの顔。上の帯が実体の色で、ストラップを通す穴が開いている。
 *
 * @param leftImprint 帯の左の印字 (「PRODUCER PASS」)。[rightImprint] は右 (「担当」)。
 * @param seed 帯の色 hex。[brand] はブランド ID。どちらも無ければ墨の帯。
 * @param trailing 名前の右 (数・矢印。`ImasPassStats` など)。
 */
@Composable
fun ImasPass(
    leftImprint: String,
    title: String,
    modifier: Modifier = Modifier,
    rightImprint: String? = null,
    subtitle: String? = null,
    seed: String? = null,
    brand: String? = null,
    onOpen: (() -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null
) {
    val t = imasThemeForBrand(seed, brand)
    val band = if (t.isNeutral) DS.sys else t.accent
    val onBand = if (t.isNeutral) DS.onSys else t.onAccent
    val shape = RoundedCornerShape(DS.rCard)
    Column(
        modifier
            .fillMaxWidth()
            .then(if (onOpen != null) Modifier.imasPress(onClick = onOpen) else Modifier.semantics(mergeDescendants = true) { })
            .imasSurface(shape)
            .clip(shape)
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(44.dp)
                .background(band),
            contentAlignment = Alignment.Center
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(leftImprint, style = ImasTextRole.IMPRINT.style, color = onBand.copy(alpha = 0.9f), maxLines = 1)
                Spacer(Modifier.weight(1f).widthIn(min = 60.dp))
                if (rightImprint != null) {
                    Text(rightImprint, style = ImasTextRole.IMPRINT.style, color = onBand.copy(alpha = 0.9f), maxLines = 1)
                }
            }
            // ストラップを通す穴 (地の色を透かす)。
            Box(
                Modifier
                    .size(width = 44.dp, height = 10.dp)
                    .background(DS.bg, CircleShape)
                    .border(1.dp, Color.Black.copy(alpha = 0.18f), CircleShape)
                    .clearAndSetSemantics { }
            )
        }
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
            verticalAlignment = Alignment.Bottom
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                ImasFitText(title, style = ImasType.heading(28.sp, FontWeight.ExtraBold), color = DS.ink, maxLines = 2, minScale = 0.8f)
                if (subtitle != null) {
                    Text(subtitle, style = ImasType.text(13.sp), color = DS.ink2, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
            trailing?.invoke(this)
        }
    }
}

/** 入場証の右に並べる小さな数 (iOS `ImasPassStats`。「12 回収」「4 参加」)。 */
@Composable
fun ImasPassStats(items: List<Pair<String, String>>, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        items.forEach { (value, label) ->
            Column(
                Modifier.semantics(mergeDescendants = true) { },
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Text(value, style = ImasNumeralSize.LARGE.style, color = DS.ink, maxLines = 1)
                Text(label, style = ImasType.text(11.sp), color = DS.ink2, maxLines = 1)
            }
        }
    }
}

// MARK: - チケットの束

/**
 * チケットの束の 1 枚 (iOS `ImasTicketStack.Item`)。
 *
 * @param ticket いちばん上に来たときに出すチケット (`ImasTicket`)。
 * @param edge 後ろに回ったときに端に出す 1 行 (「11.08 SUN · 標 FINAL DAY2 · 38 DAYS」)。
 */
@Immutable
class ImasTicketStackItem(
    val id: String,
    val edge: String,
    val ticket: @Composable () -> Unit
)

/**
 * 参加予定のチケットの束 (iOS `ImasTicketStack`)。いちばん上のチケットを大きく、後ろの 2 枚は下の端だけを見せる。
 * 束を横に払うと次のチケットが上に来る (縦のスクロールは邪魔しない)。1 枚なら束にしない。
 */
@Composable
fun ImasTicketStack(items: List<ImasTicketStackItem>, modifier: Modifier = Modifier) {
    if (items.isEmpty()) return
    var front by rememberSaveable { mutableIntStateOf(0) }
    val count = items.size
    val haptics = rememberImasHaptics()
    val threshold = with(LocalDensity.current) { 50.dp.toPx() }
    fun move(step: Int) {
        if (count <= 1) return
        front = (front + step + count) % count
        haptics.selection()
    }
    val ordered = (0 until count).map { items[(it + front) % count] }
    val depthCount = minOf(count - 1, 2)
    Box(
        modifier
            .fillMaxWidth()
            .pointerInput(count) {
                var total = 0f
                detectHorizontalDragGestures(
                    onDragStart = { total = 0f },
                    onDragEnd = { if (abs(total) > threshold) move(if (total < 0) 1 else -1) },
                    onHorizontalDrag = { _, amount -> total += amount }
                )
            }
            .semantics {
                if (count > 1) {
                    customActions = listOf(CustomAccessibilityAction("次のチケット") { move(1); true })
                }
            },
        contentAlignment = Alignment.BottomCenter
    ) {
        ordered.drop(1).take(2).withIndex().reversed().forEach { (i, item) ->
            TicketStackEdge(item.edge, depth = i + 1)
        }
        AnimatedContent(
            targetState = ordered[0],
            transitionSpec = {
                (slideInVertically { it / 3 } + fadeIn()) togetherWith (slideOutHorizontally { -it } + fadeOut())
            },
            contentKey = { it.id },
            modifier = Modifier.padding(bottom = (depthCount * 20).dp),
            label = "ticketStack"
        ) { item -> item.ticket() }
    }
}

/** 束の後ろのチケットの端。奥ほど狭く、少し暗い紙。 */
@Composable
private fun TicketStackEdge(text: String, depth: Int) {
    val shape = RoundedCornerShape(14.dp)
    val paper = lerp(DS.ticket, Color.Black, if (depth == 1) 0.02f else 0.05f)
    Box(
        Modifier
            .padding(horizontal = (depth * 8).dp)
            .padding(bottom = ((2 - depth) * 20).dp)
            .fillMaxWidth()
            .height(70.dp)
            .imasSoftShadow(shape, fill = paper, color = Color.Black.copy(alpha = 0.05f), blur = 6.dp, offsetY = 3.dp)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.BottomStart
    ) {
        Text(
            text,
            style = ImasType.mono(10.sp, FontWeight.Medium),
            color = DS.ticketSub,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 6.dp)
        )
    }
}

// MARK: - アイドル詳細の頭

/**
 * アイドル詳細の頭 (iOS `ImasIdolHeader`)。名札 (色の帯・アイコン・名前・よみと CV・担当の印) と、
 * その下につなげた電光掲示板。アイコンはいつも出す (写真があれば写真、無ければ判子)。
 * 右下には写真を選ぶ口 ([iconAccessory]、`ImasIconBadge`) などを重ねる。
 *
 * @param imprint 名札の上の印字 (ブランド名)。[onImprintTap] を渡すと押せる (ブランドで絞った一覧へ)。
 * @param iconLabel 判子に入れる短い名前。null なら [name]。
 * @param entityId 渡すと端末に取り込んだ写真を引く。
 * @param onTogglePick 担当の印を押したとき。null なら担当の欄を出さない。
 * @param copyItems 名前を長押ししたときのコピー (名前・よみ・CV)。
 */
@Composable
fun ImasIdolHeader(
    imprint: String,
    name: String,
    isPick: Boolean,
    modifier: Modifier = Modifier,
    onImprintTap: (() -> Unit)? = null,
    subtitle: String? = null,
    seed: String? = null,
    brand: String? = null,
    iconLabel: String? = null,
    imageUrl: String? = null,
    entityId: String? = null,
    onTogglePick: (() -> Unit)? = null,
    copyItems: List<CopyItem> = emptyList(),
    stats: List<ImasBoardCell> = emptyList(),
    iconAccessory: (@Composable BoxScope.() -> Unit)? = null
) {
    val t = imasThemeForBrand(seed, brand)
    val color = if (t.isNeutral) DS.ink else t.penlight
    val shape = RoundedCornerShape(DS.rCard)
    val haptics = rememberImasHaptics()
    Column(
        modifier
            .fillMaxWidth()
            .imasSurfaceEdge(shape)
            .clip(shape)
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .height(IntrinsicSize.Min)
                .background(DS.surface)
        ) {
            Box(
                Modifier
                    .width(8.dp)
                    .fillMaxHeight()
                    .background(if (t.isNeutral) DS.sys else t.accent)
            )
            Row(
                Modifier
                    .weight(1f)
                    .padding(14.dp),
                horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box {
                    ImasAvatar(
                        label = iconLabel ?: name,
                        seed = seed,
                        brand = brand,
                        size = 72.dp,
                        isPick = isPick,
                        imageUrl = imageUrl,
                        entityId = entityId
                    )
                    iconAccessory?.let { Box(Modifier.align(Alignment.BottomEnd)) { it() } }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (onImprintTap != null) {
                        Text(
                            imprint,
                            style = ImasTextRole.IMPRINT.style,
                            color = DS.ink2,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.clickable(onClickLabel = "このブランドのアイドルを見る", onClick = onImprintTap)
                        )
                    } else {
                        Text(imprint, style = ImasTextRole.IMPRINT.style, color = DS.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Copyable(items = copyItems) {
                        ImasFitText(name, style = ImasType.heading(28.sp, FontWeight.ExtraBold), color = DS.ink, maxLines = 2, minScale = 0.7f)
                    }
                    if (subtitle != null) {
                        Text(subtitle, style = ImasType.text(12.sp), color = DS.ink2, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            if (onTogglePick != null) {
                ImasPerforation(Modifier.padding(vertical = 12.dp), axis = ImasPerforationAxis.VERTICAL, color = DS.perforation)
                PickColumn(isPick, color) {
                    haptics.impactMedium()
                    onTogglePick()
                }
            }
        }
        if (stats.isNotEmpty()) {
            ImasBoard(
                cells = stats,
                shape = RoundedCornerShape(bottomStart = DS.rCard, bottomEnd = DS.rCard)
            )
        }
    }
}

/** 名札の右の担当の印 (♥ + 担当)。 */
@Composable
private fun PickColumn(isPick: Boolean, color: Color, onClick: () -> Unit) {
    val bounce = remember { Animatable(1f) }
    var first by remember { mutableStateOf(true) }
    LaunchedEffect(isPick) {
        if (first) first = false else {
            bounce.snapTo(1.25f)
            bounce.animateTo(1f, ImasMotion.standard())
        }
    }
    val tint = if (isPick) color else DS.ink3
    Column(
        Modifier
            .width(64.dp)
            .fillMaxHeight()
            .imasPress(onClickLabel = if (isPick) "担当から外す" else "担当にする", onClick = onClick)
            .clearAndSetSemantics { contentDescription = if (isPick) "担当から外す" else "担当にする" },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically)
    ) {
        Icon(
            if (isPick) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
            contentDescription = null,
            tint = tint,
            modifier = Modifier
                .size(with(LocalDensity.current) { 22.sp.toDp() })
                .scale(bounce.value)
        )
        Text("担当", style = ImasType.text(11.sp, FontWeight.ExtraBold), color = tint, maxLines = 1)
    }
}

// MARK: - アイドルの名札 (格子)

/**
 * アイドルの名札 (iOS `ImasIdolCell`)。格子に並べる (iPhone は 4 列)。上の帯が担当色、その下にアイコン (写真か判子)・
 * 名前・並べ替えの値。担当はアイコンの輪が二重になる。選ぶ格子 (ピッカー) では枠が点き、右上に選択の印。
 *
 * @param metric 並べ替えの値 (「158cm」「17歳」)。何順に並んでいるかを名札から読めるようにする。null なら出さない。
 * @param isSelected 選ぶ格子 (ピッカー) のときの選択。null なら選択の印を出さない。
 * @param entityId 渡すと端末に取り込んだ写真を引く。
 */
@Composable
fun ImasIdolCell(
    name: String,
    modifier: Modifier = Modifier,
    kana: String? = null,
    seed: String? = null,
    brand: String? = null,
    iconLabel: String? = null,
    imageUrl: String? = null,
    entityId: String? = null,
    isPick: Boolean = false,
    metric: String? = null,
    isSelected: Boolean? = null,
    iconSize: Dp = 52.dp
) {
    val t = imasThemeForBrand(seed, brand)
    val band = if (t.isNeutral) DS.sys else t.accent
    val shape = RoundedCornerShape(10.dp)
    val spoken = listOfNotNull(name, if (isPick) "担当" else null, metric).joinToString("、")
    Box(
        modifier
            .imasSurface(shape)
            .clip(shape)
            .then(if (isSelected == true) Modifier.border(2.dp, if (t.isNeutral) DS.ink else t.penlight, shape) else Modifier)
            .semantics(mergeDescendants = true) {
                contentDescription = spoken
                if (isSelected != null) selected = isSelected
            }
    ) {
        Column(Modifier.fillMaxWidth()) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(5.dp)
                    .background(band)
            )
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(start = 6.dp, end = 6.dp, top = 7.dp, bottom = 9.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                ImasAvatar(
                    label = iconLabel ?: name,
                    seed = seed,
                    brand = brand,
                    size = iconSize,
                    isPick = isPick,
                    imageUrl = imageUrl,
                    entityId = entityId
                )
                ImasFitText(name, style = ImasType.heading(12.5.sp, FontWeight.ExtraBold), color = DS.ink, minScale = 0.6f)
                if (kana != null) ImasFitText(kana, style = ImasType.text(11.sp), color = DS.ink3, minScale = 0.7f)
                if (metric != null) {
                    ImasFitText(metric, style = ImasType.mono(10.5.sp, FontWeight.SemiBold), color = DS.ink3, minScale = 0.8f)
                }
            }
        }
        if (isSelected != null) {
            ImasSelectionMark(
                isSelected = isSelected,
                seed = seed,
                brand = brand,
                size = 18.dp,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 9.dp, end = 5.dp)
            )
        }
    }
}

/**
 * 名札の格子 (iOS `ImasIdolGrid`。iPhone は 4 列、タブレットは画面で 6 列を渡す)。
 * Lazy にしない (区画の中に置く短い格子)。数百人の一覧は画面が LazyVerticalGrid で組む。
 */
@Composable
fun ImasIdolGrid(modifier: Modifier = Modifier, columns: Int = 4, content: @Composable () -> Unit) {
    ImasGridLayout(columns = columns, spacing = DS.Space.gap, modifier = modifier, content = content)
}

/** 格子に並べる (列の幅は等分、行の高さはその行でいちばん高いもの)。部品の中で使う。 */
@Composable
internal fun ImasGridLayout(columns: Int, spacing: Dp, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Layout(content = content, modifier = modifier.fillMaxWidth()) { measurables, constraints ->
        val cols = columns.coerceAtLeast(1)
        val gap = spacing.roundToPx()
        val width = constraints.maxWidth
        val cellWidth = ((width - gap * (cols - 1)) / cols).coerceAtLeast(0)
        val placeables = measurables.map { it.measure(Constraints.fixedWidth(cellWidth)) }
        val rows = placeables.chunked(cols)
        val heights = rows.map { row -> row.maxOf { it.height } }
        val total = heights.sum() + gap * (rows.size - 1).coerceAtLeast(0)
        layout(width, total) {
            var y = 0
            rows.forEachIndexed { r, row ->
                row.forEachIndexed { c, p -> p.placeRelative(c * (cellWidth + gap), y) }
                y += heights[r] + gap
            }
        }
    }
}

// MARK: - ブランドを選ぶ

/**
 * ブランドの選択肢 1 つ (iOS `ImasBrandPicker.Option`)。
 *
 * @param color ブランドの色 (hex)。
 * @param logo 読み込んだロゴ (端末の中のファイル)。あればペンライトの代わりにロゴ。
 */
@Immutable
data class ImasBrandOption(
    val id: String,
    val label: String,
    val color: String? = null,
    val logo: File? = null
)

/**
 * ブランドを選ぶ (iOS `ImasBrandPicker`)。チップを折り返して並べる。先頭はペンライト、ロゴを読み込んだブランドはロゴ。
 * [includesAll] で先頭に「すべて」(何も選ばない = 全部) を置く。格子 (ブランドの四角) にはしない。
 *
 * @param allLabel 「全部選んでいない」チップの文言。画面ごとの言葉づかいに合わせて渡せる (既定「すべて」)。
 */
@Composable
fun ImasBrandPicker(
    options: List<ImasBrandOption>,
    selection: Set<String>,
    onSelectionChange: (Set<String>) -> Unit,
    modifier: Modifier = Modifier,
    includesAll: Boolean = true,
    allLabel: String = "すべて",
    allowsMultiple: Boolean = true
) {
    fun toggle(id: String) {
        val next = if (allowsMultiple) {
            if (id in selection) selection - id else selection + id
        } else {
            if (id in selection && includesAll) emptySet() else setOf(id)
        }
        onSelectionChange(next)
    }
    ImasChipFlow(modifier) {
        if (includesAll) {
            ImasFilterChip(label = allLabel, selected = selection.isEmpty(), onClick = { onSelectionChange(emptySet()) })
        }
        options.forEach { option ->
            ImasFilterChip(
                label = option.label,
                selected = option.id in selection,
                onClick = { toggle(option.id) },
                seed = option.color,
                leading = option.logo?.let { ImasChipLeading.Logo(it) } ?: ImasChipLeading.Dot
            )
        }
    }
}
