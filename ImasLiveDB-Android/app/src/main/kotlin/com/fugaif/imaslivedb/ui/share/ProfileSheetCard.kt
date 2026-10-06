package com.fugaif.imaslivedb.ui.share

import android.graphics.Bitmap
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.producercard.ProfileSheetMaterials
import com.fugaif.imaslivedb.data.producercard.ProfileSheetOshi
import com.fugaif.imaslivedb.ui.designsystem.drawQr
import com.fugaif.imaslivedb.ui.designsystem.imasQrMatrix
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.rememberCardNameFamily
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import uniffi.imas_core.CardNameFont
import uniffi.imas_core.ProfileBrandCheck
import uniffi.imas_core.ProfileHandRing
import uniffi.imas_core.ProfileHistoryKind
import uniffi.imas_core.ProfileHistoryRow
import uniffi.imas_core.ProfileSection
import uniffi.imas_core.ProfileSheetDensity
import uniffi.imas_core.ProfileSheetLayout
import uniffi.imas_core.ProfileSheetSize
import uniffi.imas_core.ProfileSlot
import uniffi.imas_core.cardNameFontInfo

// =============================================================================
// プロフィール帳 (SNS に貼る自己紹介の 1 枚絵)。iOS `ProfileSheetCard.swift` の移植。P を職業に見立てた **履歴書** の様式。
//
// - 欄・行・丸・詰め方はコア (`profileSheetLayout`) が決め、ここは描くだけ。
// - 紙は生成り、線は墨。罫の太さは 2 段 (外枠 1.5 と欄の中 0.5)。担当色は押印欄の判子の 1 か所だけ
//   (面を塗らない・帯を引かない)。ブランドの丸はブランドの色の手描きの線 (中身そのものの色)。
// - 字面は事務書類の端正さに寄せる。題・名前・欄の題は明朝 (同梱の `card_name_mincho`)、本文はゴシック、
//   英字は等幅の大文字の印字だけ。太さは 2 段 (本文 = regular・見出し = semibold)、和文はかなを詰めて (palt)
//   字間を少し詰め、英字の大文字にだけ字間を足す。数字は等幅。題は大きく本文は控えめにして、大きさの比をはっきり取る。
// - 中身はすべてアプリの記録から (自分で書く欄は無い)。アプリ名の帯 (`ShareCardFooter`) を下に置く。
//
// 固定のキャンバスに焼くので、色は固定色、文字は固定の大きさ (docs/DESIGN_SYSTEM.md §13)。
// 画像は読み込み済みの Bitmap だけを使う (焼くのは今描かれているものだけで、読み込みを待たない)。画像は大きさの決まった枠を
// 先に作ってから重ねて切る (縦長の大きな画像で枠が膨らまないように)。
// =============================================================================

object ProfileSheetInk {
    /** 生成りの紙。 */
    val paper = Color(0xFFFBF7EE)
    val ink = ShareInk.nearBlack

    /** 設問・項目名の灰。 */
    val sub = Color(0xFF6A6663)

    /** 外枠の罫。 */
    const val FRAME = 1.5f

    /** 欄の中の罫。 */
    const val RULE = 0.5f

    /** QR の辺。詰め方で縮めない (焼いた画像を SNS が縮めても読めるように)。周りに紙の余白を足す。 */
    const val QR_SIDE = 52f

    fun size(size: ProfileSheetSize): ShareCardSize =
        if (size == ProfileSheetSize.STORY) ShareCardRatio.STORY.size else ShareCardRatio.PORTRAIT.size

    /**
     * 詰め方 (コアの `density`) の倍率。縦長のストーリーズは少し大きく組む。
     * 見積もりより実物が長いときは、ここから 1 段ずつ小さくして収まるものを使う ([ProfileFitFirst])。
     */
    fun scales(layout: ProfileSheetLayout): List<Float> {
        val steps = listOf(1f, 0.96f, 0.92f, 0.88f, 0.84f, 0.8f, 0.76f, 0.72f, 0.68f, 0.64f)
        val start = when (layout.density) {
            ProfileSheetDensity.REGULAR -> 0
            ProfileSheetDensity.COMPACT -> 2
            ProfileSheetDensity.TIGHT -> 4
        }
        // 9:16 は縦に余るので大きく組む (入らなければ下の段へ)。
        val base = if (layout.size == ProfileSheetSize.STORY) 1.3f else 1f
        return steps.drop(start).map { it * base }
    }
}

/**
 * プロフィール帳の書体。題・名前・欄の題だけ明朝 (同梱の書体)、ほかはゴシック、英字は等幅の印字。
 * iOS `ProfileSheetType` と対。
 */
private object ProfileSheetType {
    /** 和文 (かなを詰める palt)。[weight] は regular / semibold の 2 段で使う。 */
    fun jp(size: Float, weight: FontWeight = FontWeight.Normal, tracking: Float = 0f) = TextStyle(
        fontSize = size.sp, fontWeight = weight, letterSpacing = tracking.sp, fontFeatureSettings = "palt, tnum"
    )

    /** 英字の印字 (等幅の大文字)。 */
    fun imprint(size: Float, tracking: Float = IMPRINT_TRACKING) = TextStyle(
        fontFamily = FontFamily.Monospace, fontSize = size.sp, fontWeight = FontWeight.Medium, letterSpacing = tracking.sp
    )

    /** 題・名前・欄の題 (明朝。引けなければ本文のゴシックの semibold)。 */
    fun display(family: FontFamily?, size: Float, tracking: Float = 0f) =
        family?.let { TextStyle(fontFamily = it, fontSize = size.sp, letterSpacing = tracking.sp, fontFeatureSettings = "palt") }
            ?: jp(size, FontWeight.SemiBold, tracking)

    const val IMPRINT_TRACKING = 2.4f

    /** 和文の字間 (少し詰める)。 */
    const val JP_TRACKING = -0.2f
}

private typealias T = ProfileSheetType
private typealias Ink = ProfileSheetInk

/** 担当色 (なければ墨)。 */
@Composable
private fun profileAccent(seed: String?): Color = if (seed == null) Ink.ink else rememberShareCardPalette(seed).accent

/** プロフィール帳 1 枚。[ShareCardCanvas] の中で、大きさは [ProfileSheetInk.size]。 */
@Composable
fun ProfileSheetCard(layout: ProfileSheetLayout, materials: ProfileSheetMaterials) {
    val scales = remember(layout.density, layout.size) { ProfileSheetInk.scales(layout) }
    val mincho = rememberCardNameFamily(remember { cardNameFontInfo(CardNameFont.MINCHO).fileStem })
    Column(
        Modifier.fillMaxSize().background(Ink.paper).padding(start = 26.dp, end = 26.dp, top = 26.dp, bottom = 18.dp)
    ) {
        ProfileSheetHeading(layout, mincho)
        // コアの詰め方から始めて、収まらなければ小さい方へ (最後の段は下を切る)。
        ProfileFitFirst(scales, Modifier.weight(1f).fillMaxWidth().padding(top = 12.dp)) { s ->
            ProfileResumeBody(layout, materials, mincho, s)
        }
        Box(Modifier.padding(top = 8.dp)) {
            ShareCardFooter(ink = Ink.ink.copy(alpha = 0.7f), rule = Ink.ink.copy(alpha = 0.25f))
        }
    }
}

/**
 * [scales] の順に組んでみて、縦に収まる最初のものを置く (iOS `ViewThatFits(in: .vertical)`)。
 * どれも収まらなければ最後の段を置いて下を切る。
 */
@Composable
private fun ProfileFitFirst(scales: List<Float>, modifier: Modifier, content: @Composable (Float) -> Unit) {
    SubcomposeLayout(modifier.clipToBounds()) { constraints ->
        val loose = Constraints(
            minWidth = constraints.maxWidth, maxWidth = constraints.maxWidth,
            minHeight = 0, maxHeight = Constraints.Infinity
        )
        var chosen: List<Placeable> = emptyList()
        for ((index, s) in scales.withIndex()) {
            chosen = subcompose(index) { content(s) }.map { it.measure(loose) }
            if ((chosen.maxOfOrNull { it.height } ?: 0) <= constraints.maxHeight) break
        }
        layout(constraints.maxWidth, constraints.maxHeight) { chosen.forEach { it.place(0, 0) } }
    }
}

// MARK: - 頭 (題・日付)

@Composable
private fun ProfileSheetHeading(layout: ProfileSheetLayout, mincho: FontFamily?) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                layout.title, style = T.display(mincho, 30f, tracking = 7f), color = Ink.ink, maxLines = 1,
                modifier = Modifier.alignByBaseline()
            )
            Text(layout.imprint, style = T.imprint(8f), color = Ink.sub, maxLines = 1, modifier = Modifier.alignByBaseline())
            Spacer(Modifier.weight(1f).width(8.dp))
            Text(layout.asOf, style = T.jp(9.5f), color = Ink.ink, maxLines = 1, modifier = Modifier.alignByBaseline())
        }
        ProfileRule(Ink.FRAME)
    }
}

// MARK: - 履歴書

@Composable
private fun ProfileResumeBody(layout: ProfileSheetLayout, materials: ProfileSheetMaterials, mincho: FontFamily?, s: Float) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy((10 * s).dp)) {
        ResumeIdentity(layout, materials, mincho, s)
        if (layout.brands.isNotEmpty()) ProfileBrandRange(layout.brandsTitle, layout.brands, s)
        if (layout.history.isNotEmpty() || layout.licenses.isNotEmpty()) {
            ProfileBox {
                Column {
                    if (layout.history.isNotEmpty()) {
                        ProfileTableHead("P歴（学歴・職歴）", s)
                        layout.history.forEachIndexed { i, row ->
                            if (i > 0) ProfileRule()
                            ProfileHistoryLine(row, s)
                        }
                    }
                    if (layout.licenses.isNotEmpty()) {
                        if (layout.history.isNotEmpty()) ProfileRule(Ink.FRAME)
                        ProfileTableHead("免許・資格", s)
                        layout.licenses.forEachIndexed { i, row ->
                            if (i > 0) ProfileRule()
                            ProfileHistoryLine(row, s)
                        }
                    }
                }
            }
        }
        // 志望の動機は横いっぱい、ほかの欄は左右に並べる (様式の欄の並び)。
        layout.sections.filter { it.slot == ProfileSlot.MOTIVATION }.forEach { section ->
            ProfileBox { ProfileSectionView(section, mincho, s) }
        }
        val pair = layout.sections.filter { it.slot != ProfileSlot.MOTIVATION }
        if (pair.isNotEmpty()) {
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy((10 * s).dp)) {
                pair.forEach { section ->
                    ProfileBox(Modifier.weight(1f).fillMaxHeight()) { ProfileSectionView(section, mincho, s) }
                }
            }
        }
    }
}

/** 氏名・押印・P歴・担当・連絡先と証明写真。 */
@Composable
private fun ResumeIdentity(layout: ProfileSheetLayout, materials: ProfileSheetMaterials, mincho: FontFamily?, s: Float) {
    ProfileBox {
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
            Column(Modifier.weight(1f)) {
                ProfileField("氏名", s) {
                    Row(
                        Modifier.fillMaxWidth().padding(vertical = (3 * s).dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        ProfileFitText(
                            layout.name, style = T.display(mincho, 24 * s, tracking = T.JP_TRACKING), color = Ink.ink,
                            maxLines = 1, minScale = 0.5f, modifier = Modifier.weight(1f)
                        )
                        val oshi = materials.oshi.firstOrNull()
                        if (layout.showOshi && oshi != null) ProfileSeal(oshi, 42 * s)
                    }
                }
                layout.sinceLabel?.let { since ->
                    ProfileRule()
                    ProfileField("P歴", s) { Text(since, style = T.jp(10 * s), color = Ink.ink, maxLines = 1) }
                }
                if (layout.showOshi && materials.oshi.isNotEmpty()) {
                    ProfileRule()
                    ProfileField("担当", s) { ProfileOshiList(materials.oshi, s) }
                }
                val qr = materials.qrUrl?.takeIf { layout.showQr && imasQrMatrix(it) != null }
                if (layout.contacts.isNotEmpty() || qr != null) {
                    ProfileRule()
                    ProfileField("連絡先", s) {
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            ProfileFitText(
                                layout.contacts.joinToString("   "), style = T.imprint(9.5f * s, tracking = 0f),
                                color = Ink.ink, maxLines = 2, minScale = 0.7f, modifier = Modifier.weight(1f)
                            )
                            if (qr != null) ProfileQR(qr)
                        }
                    }
                }
            }
            Box(Modifier.width(Ink.RULE.dp).fillMaxHeight().background(Ink.ink))
            Box(Modifier.fillMaxHeight().padding((10 * s).dp), contentAlignment = Alignment.Center) {
                ProfilePhotoBox(if (layout.showPhoto) materials.portrait else null, 88 * s)
            }
        }
    }
}

// MARK: - 部品 (プロフィール帳の中だけ)

/** 墨の罫で囲む欄。 */
@Composable
private fun ProfileBox(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.fillMaxWidth().border(Ink.FRAME.dp, Ink.ink)) { content() }
}

@Composable
private fun ProfileRule(width: Float = Ink.RULE) {
    Box(Modifier.fillMaxWidth().height(width.dp).background(Ink.ink))
}

/** 項目名と中身の 1 段。 */
@Composable
private fun ProfileField(label: String, s: Float, content: @Composable () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = (5 * s).dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            label, style = T.jp(7.5f * s, FontWeight.SemiBold), color = Ink.sub,
            maxLines = 1, modifier = Modifier.width((34 * s).dp)
        )
        Box(Modifier.weight(1f)) { content() }
    }
}

/** 表の頭 (年・月・内容)。下は墨の罫。 */
@Composable
private fun ProfileTableHead(title: String, s: Float) {
    val style = T.jp(7.5f * s, FontWeight.SemiBold)
    Column {
        ProfileHistoryColumns("年", "月", style, Ink.sub, s) {
            Text(title, style = style, color = Ink.sub, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        }
        ProfileRule(Ink.RULE * 2)
    }
}

@Composable
private fun ProfileHistoryLine(row: ProfileHistoryRow, s: Float) {
    val closing = row.kind == ProfileHistoryKind.CLOSING
    val style = T.jp(9.5f * s, if (closing) FontWeight.SemiBold else FontWeight.Normal, T.JP_TRACKING)
    ProfileHistoryColumns(row.year, row.month, style, Ink.ink, s) {
        Text(
            row.text, style = style, color = Ink.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
            textAlign = if (closing) TextAlign.End else TextAlign.Start, modifier = Modifier.fillMaxWidth()
        )
    }
}

/** 年 | 月 | 内容 の 3 列。 */
@Composable
private fun ProfileHistoryColumns(
    year: String,
    month: String,
    style: TextStyle,
    color: Color,
    s: Float,
    content: @Composable () -> Unit
) {
    Row(
        Modifier.fillMaxWidth().height(IntrinsicSize.Min),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            year, style = style, color = color, textAlign = TextAlign.Center, maxLines = 1,
            modifier = Modifier.width((38 * s).dp).padding(vertical = (3.5f * s).dp)
        )
        Box(Modifier.width(Ink.RULE.dp).fillMaxHeight().background(Ink.ink))
        Text(
            month, style = style, color = color, textAlign = TextAlign.Center, maxLines = 1,
            modifier = Modifier.width((24 * s).dp).padding(vertical = (3.5f * s).dp)
        )
        Box(Modifier.width(Ink.RULE.dp).fillMaxHeight().background(Ink.ink))
        Box(Modifier.weight(1f).padding(horizontal = 10.dp, vertical = (3.5f * s).dp)) { content() }
    }
}

/** 欄 (題と、項目の並び)。 */
@Composable
private fun ProfileSectionView(section: ProfileSection, mincho: FontFamily?, s: Float) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = (9 * s).dp),
        verticalArrangement = Arrangement.spacedBy((6 * s).dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                section.title, style = T.display(mincho, 10.5f * s, T.JP_TRACKING), color = Ink.ink,
                modifier = Modifier.alignByBaseline()
            )
            Text(section.imprint, style = T.imprint(7f), color = Ink.sub, maxLines = 1, modifier = Modifier.alignByBaseline())
        }
        Column(verticalArrangement = Arrangement.spacedBy((6 * s).dp)) {
            section.entries.forEach { entry ->
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    if (entry.label.isNotEmpty()) {
                        Text(entry.label, style = T.jp(7.5f * s, FontWeight.SemiBold), color = Ink.sub)
                    }
                    Text(
                        entry.text,
                        style = T.jp(10.5f * s, tracking = T.JP_TRACKING).copy(lineHeight = (10.5f * s + 2 * s).sp * 1.25f),
                        color = Ink.ink
                    )
                }
            }
        }
    }
}

/** 担当ブランド: 刷ってあるブランドの名前に、担当しているものだけ手描きの丸 (メインは二重丸、いくつでも)。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ProfileBrandRange(title: String, brands: List<ProfileBrandCheck>, s: Float) {
    // 名前が 2 段に折り返しても、欄の名前は 1 段目の高さに置く。
    Row(
        Modifier.fillMaxWidth().padding(vertical = (4 * s).dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top
    ) {
        Text(
            title, style = T.jp(7.5f * s, FontWeight.SemiBold), color = Ink.sub,
            maxLines = 1, softWrap = false, modifier = Modifier.padding(top = (5 * s).dp)
        )
        // 丸 (二重丸の外側) が欄の名前に掛からないよう、名前の列から少し離す。
        FlowRow(
            modifier = Modifier.padding(start = (6 * s).dp),
            horizontalArrangement = Arrangement.spacedBy((17 * s).dp),
            verticalArrangement = Arrangement.spacedBy((10 * s).dp)
        ) {
            brands.forEach { brand ->
                val circle = if (brand.rings.isNotEmpty()) profileAccent(brand.color) else null
                Text(
                    brand.label,
                    style = T.jp(10 * s, if (brand.checked) FontWeight.SemiBold else FontWeight.Normal, T.JP_TRACKING),
                    color = if (brand.checked) Ink.ink else Ink.sub,
                    maxLines = 1,
                    modifier = Modifier
                        .padding(horizontal = 4.dp, vertical = 2.dp)
                        .drawBehind {
                            if (circle != null) brand.rings.forEachIndexed { i, ring ->
                                drawHandRing(
                                    ring, circle, width = (if (i == 0) 1.6f else 1.2f).dp.toPx(),
                                    padX = 4.dp.toPx() + 3.dp.toPx(), padY = 2.dp.toPx() + 4.dp.toPx()
                                )
                            }
                        }
                )
            }
        }
    }
}

/**
 * 手描きの楕円 1 本 (iOS `ProfileHandCircle`)。少し傾け、横に伸び縮みさせ、書き終わりを行き過ぎて重ねる。
 * 揺らぎ・大きさ・中心のずれはコアが id から決める (メインは 2 本で二重丸)。[padX] / [padY] だけ文字の外に広げて描く。
 */
private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawHandRing(
    ring: ProfileHandRing,
    color: Color,
    width: Float,
    padX: Float,
    padY: Float
) {
    val w = (size.width + padX * 2) * ring.scale
    val h = (size.height + padY * 2) * ring.scale
    // ずれは丸を描く枠 (文字の外に広げた枠) の幅・高さに対する割合。
    val cx = (size.width / 2 + (size.width + padX * 2) * ring.offsetX).toFloat()
    val cy = (size.height / 2 + (size.height + padY * 2) * ring.offsetY).toFloat()
    val rx = w / 2 * ring.stretch
    val ry = h / 2.0
    val a0 = ring.startDegrees * PI / 180
    val sweep = 2 * PI + 0.5
    val steps = 72
    val path = Path()
    for (i in 0..steps) {
        val t = i.toDouble() / steps
        val a = a0 + sweep * t
        // 少しいびつに (3 つ山の揺らぎ) し、書き終わりは外へ逃がす。
        val r = 1 + 0.035 * sin(3 * a + a0) + 0.07 * t
        val x = (cx + rx * r * cos(a)).toFloat()
        val y = (cy + ry * r * sin(a)).toFloat()
        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
    }
    rotate(ring.tiltDegrees.toFloat(), pivot = Offset(cx, cy)) {
        drawPath(path, color, style = Stroke(width = width, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** 押印欄の判子 (担当の名前を担当色の二重の丸に。少し傾けて押す)。プロフィール帳で担当色を使う唯一の所。 */
@Composable
private fun ProfileSeal(oshi: ProfileSheetOshi, diameter: Float) {
    val color = profileAccent(oshi.color ?: oshi.brandColor)
    val chars = oshi.shortName.codePoints().toArray().map { String(Character.toChars(it)) }
    Box(
        Modifier
            .size(diameter.dp)
            .rotate(-12f)
            .border(2.dp, color, CircleShape)
            .padding(3.5.dp)
            .border(0.8.dp, color, CircleShape),
        contentAlignment = Alignment.Center
    ) {
        // 2〜3 文字は縦書き、長い名前は横に縮めて入れる。
        if (chars.size <= 3) {
            val size = diameter * (if (chars.size == 3) 0.22f else 0.28f)
            Text(
                chars.joinToString("\n"), color = color, textAlign = TextAlign.Center,
                style = TextStyle(fontFamily = FontFamily.Serif, fontWeight = FontWeight.ExtraBold, fontSize = size.sp, lineHeight = 0.96.em)
            )
        } else {
            ProfileFitText(
                oshi.shortName,
                style = TextStyle(fontFamily = FontFamily.Serif, fontWeight = FontWeight.ExtraBold, fontSize = (diameter * 0.24f).sp),
                color = color, maxLines = 1, minScale = 0.4f, textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = (diameter * 0.14f - 3.5f).coerceAtLeast(0f).dp)
            )
        }
    }
}

/** 担当の並び (写真か判子 + 名前)。 */
@Composable
private fun ProfileOshiList(oshi: List<ProfileSheetOshi>, s: Float) {
    Row(horizontalArrangement = Arrangement.spacedBy((12 * s).dp), verticalAlignment = Alignment.CenterVertically) {
        oshi.forEach { idol ->
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                ProfileOshiIcon(idol, 22 * s)
                ProfileFitText(idol.name, style = T.jp(10 * s, tracking = T.JP_TRACKING), color = Ink.ink, maxLines = 1, minScale = 0.6f)
            }
        }
    }
}

/** 担当のアイコン (写真が無ければ判子)。枠を先に決めてから写真を重ねて丸く切る。 */
@Composable
private fun ProfileOshiIcon(oshi: ProfileSheetOshi, size: Float) {
    val color = profileAccent(oshi.color ?: oshi.brandColor)
    Box(
        Modifier.size(size.dp).clip(CircleShape).background(Ink.paper).border(1.2.dp, color, CircleShape),
        contentAlignment = Alignment.Center
    ) {
        val image = oshi.image
        if (image != null) {
            Image(image.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
            ProfileFitText(
                oshi.shortName, style = TextStyle(fontSize = (size * 0.34f).sp, fontWeight = FontWeight.Bold), color = color,
                maxLines = 1, minScale = 0.5f, textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = (size * 0.1f).dp)
            )
        }
    }
}

/** 証明写真の欄 (3:4)。枠を先に決めてから写真を重ねて切る。写真が無ければ「写真をはる位置」を刷っておく。 */
@Composable
private fun ProfilePhotoBox(image: Bitmap?, width: Float) {
    val height = width * 4 / 3
    Box(
        Modifier
            .size(width.dp, height.dp)
            .clipToBounds()
            .drawWithContent {
                drawContent()
                val stroke = Ink.RULE.dp.toPx()
                drawRect(
                    Ink.ink, topLeft = Offset(stroke / 2, stroke / 2),
                    size = Size(size.width - stroke, size.height - stroke),
                    style = Stroke(
                        width = stroke,
                        pathEffect = if (image == null) PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 2.dp.toPx())) else null
                    )
                )
            },
        contentAlignment = Alignment.Center
    ) {
        if (image != null) {
            val bitmap = remember(image) { image.asImageBitmap() }
            Image(bitmap, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("写真をはる位置", style = T.jp(7.5f, FontWeight.SemiBold), color = Ink.sub, textAlign = TextAlign.Center)
                Text("縦 36〜40mm\n横 24〜30mm", style = T.jp(6.5f), color = Ink.sub, textAlign = TextAlign.Center)
            }
        }
    }
}

@Composable
private fun ProfileQR(url: String) {
    val matrix = remember(url) { imasQrMatrix(url) }
    Box(Modifier.background(Ink.paper).padding(4.dp)) {
        Canvas(Modifier.size(Ink.QR_SIDE.dp)) { if (matrix != null) drawQr(matrix, Ink.ink) }
    }
}

/**
 * 実寸のプロフィール帳を親の幅に合わせて縮めて見せる (影は付けず、細い線で縁取る)。焼くのは [capture]。
 * iOS `ShareCardPreview` の役。
 */
@Composable
fun ProfileSheetPreview(
    layout: ProfileSheetLayout,
    materials: ProfileSheetMaterials,
    capture: ShareCardCapture,
    modifier: Modifier = Modifier
) {
    val shape = RoundedCornerShape(DS.rInner)
    ShareCardCanvas(
        size = ProfileSheetInk.size(layout.size),
        capture = capture,
        modifier = modifier.clip(shape).border(1.dp, DS.line, shape)
    ) { ProfileSheetCard(layout, materials) }
}

/**
 * 幅に収まらなければ [minScale] まで字を小さくする 1 枚の文字 (iOS `minimumScaleFactor`)。
 * 測ったその場で大きさを決めて描く (状態を持たないので、[ProfileFitFirst] で試し組みしても焼き上がりが揃う)。
 */
@Composable
private fun ProfileFitText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    maxLines: Int = 1,
    minScale: Float = 0.6f,
    textAlign: TextAlign? = null
) {
    val measurer = rememberTextMeasurer()
    // 描く文字は配置のときにだけ決める (大きさの問い合わせ (intrinsics) は配置をしないので上書きしない)。
    var drawn by remember { mutableStateOf<TextLayoutResult?>(null) }
    val base = style.copy(color = color, textAlign = textAlign ?: style.textAlign)
    Layout(
        content = {},
        modifier = modifier.drawBehind { drawn?.let { drawText(it) } }
    ) { _, constraints ->
        val width = if (constraints.hasBoundedWidth) constraints.maxWidth else Constraints.Infinity
        val aligned = textAlign != null && constraints.hasBoundedWidth
        fun measure(scale: Float, overflow: TextOverflow) = measurer.measure(
            text, base.copy(fontSize = base.fontSize * scale), overflow = overflow,
            softWrap = maxLines > 1, maxLines = maxLines,
            constraints = Constraints(minWidth = if (aligned) width else 0, maxWidth = width)
        )
        var scale = 1f
        var result = measure(scale, TextOverflow.Clip)
        while ((result.didOverflowWidth || result.didOverflowHeight) && scale > minScale) {
            scale = (scale - 0.05f).coerceAtLeast(minScale)
            result = measure(scale, TextOverflow.Clip)
        }
        if (result.didOverflowWidth || result.didOverflowHeight) result = measure(scale, TextOverflow.Ellipsis)
        val w = result.size.width
        layout(w.coerceIn(constraints.minWidth, constraints.maxWidth), result.size.height.coerceIn(constraints.minHeight, constraints.maxHeight)) {
            drawn = result
        }
    }
}
