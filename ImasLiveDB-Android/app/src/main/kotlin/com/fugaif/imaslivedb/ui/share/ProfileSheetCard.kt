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
import androidx.compose.runtime.remember
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
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
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
import uniffi.imas_core.ProfileCareerRow
import uniffi.imas_core.ProfileEntry
import uniffi.imas_core.ProfileHistoryKind
import uniffi.imas_core.ProfileHistoryRow
import uniffi.imas_core.ProfileSection
import uniffi.imas_core.ProfileSheetDensity
import uniffi.imas_core.ProfileSheetLayout
import uniffi.imas_core.ProfileSheetSize
import uniffi.imas_core.ProfileSheetStyle
import uniffi.imas_core.ProfileSlot
import uniffi.imas_core.cardNameFontInfo

// =============================================================================
// プロフィール帳 (SNS に貼る自己紹介の 1 枚絵)。iOS `ProfileSheetCard.swift` の移植。
// P を職業に見立てた事務書類の様式を、ポップに崩す。
//
// - 履歴書 (既定) / 職務経歴書。欄・行・丸・詰め方はコア (`profileSheetLayout`) が決め、ここは描くだけ。
// - 紙は生成り、線は墨の太い罫。担当色は上の帯・表の頭の罫・押印欄の判子・職務経歴の印にだけ出す
//   (面を塗らない)。ブランドの丸はブランドの色の手描きの線。
// - 題はポップな書体 (Mochiy Pop One)、設問は印字 (ゴシック)、答えと名前は P名刺で選んだ書体。
// - アプリ名の帯 (`ShareCardFooter`) を下に置く。
//
// 固定のキャンバスに焼くので、色は固定色、文字は固定の大きさ (docs/DESIGN_SYSTEM.md §13)。
// 画像は読み込み済みの Bitmap だけを使う (焼くのは今描かれているものだけで、読み込みを待たない)。
// =============================================================================

object ProfileSheetInk {
    /** 生成りの紙。 */
    val paper = Color(0xFFFBF7EE)
    val ink = ShareInk.nearBlack
    val sub = Color(0xFF5A5755)

    /** 外枠の罫 (太い)。 */
    const val FRAME = 2.5f

    /** 欄の中の罫。 */
    const val RULE = 1f

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
        val base = if (layout.size == ProfileSheetSize.STORY) 1.12f else 1f
        return steps.drop(start).map { it * base }
    }

    /** ゴシックの印字。 */
    fun sans(size: Float, weight: FontWeight, tracking: Float = 0f, tabular: Boolean = false) = TextStyle(
        fontSize = size.sp, fontWeight = weight, letterSpacing = tracking.sp,
        fontFeatureSettings = if (tabular) "tnum" else null
    )

    /** 等幅の英字の印字。 */
    fun mono(size: Float, weight: FontWeight = FontWeight.SemiBold, tracking: Float = 0f) = TextStyle(
        fontFamily = FontFamily.Monospace, fontSize = size.sp, fontWeight = weight, letterSpacing = tracking.sp
    )

    /** 同梱の書体 (P名刺で選んだ書体・題のポップ体)。引けなければゴシックの極太。 */
    fun named(family: FontFamily?, size: Float, tracking: Float = 0f) =
        family?.let { TextStyle(fontFamily = it, fontSize = size.sp, letterSpacing = tracking.sp) }
            ?: sans(size, FontWeight.ExtraBold, tracking)
}

/** 担当色 (なければ墨)。 */
@Composable
private fun profileAccent(seed: String?): Color =
    if (seed == null) ProfileSheetInk.ink else rememberShareCardPalette(seed).accent

/** 書体の段 (名前・答えの書体と、題のポップ体)。 */
private class ProfileFonts(val name: FontFamily?, val title: FontFamily?)

/** プロフィール帳 1 枚 (様式で出し分け)。[ShareCardCanvas] の中で、大きさは [ProfileSheetInk.size]。 */
@Composable
fun ProfileSheetCard(layout: ProfileSheetLayout, materials: ProfileSheetMaterials) {
    val accent = profileAccent(materials.seed)
    val scales = remember(layout.density, layout.size) { ProfileSheetInk.scales(layout) }
    val titleStem = remember { cardNameFontInfo(CardNameFont.POP).fileStem }
    val fonts = ProfileFonts(name = rememberCardNameFamily(materials.nameFont), title = rememberCardNameFamily(titleStem))
    Column(Modifier.fillMaxSize().background(ProfileSheetInk.paper)) {
        Box(Modifier.fillMaxWidth().height(10.dp).background(accent))
        Box(Modifier.fillMaxWidth().height(2.dp).background(ProfileSheetInk.ink))
        Column(Modifier.weight(1f).fillMaxWidth().padding(start = 26.dp, end = 26.dp, top = 14.dp, bottom = 18.dp)) {
            ProfileSheetHeading(layout, fonts, scales.first())
            // コアの詰め方から始めて、収まらなければ小さい方へ (最後の段は下を切る)。
            ProfileFitFirst(scales, Modifier.weight(1f).fillMaxWidth().padding(top = 10.dp)) { s ->
                when (layout.style) {
                    ProfileSheetStyle.RESUME -> ProfileResumeBody(layout, materials, fonts, accent, s)
                    ProfileSheetStyle.CAREER -> ProfileCareerBody(layout, materials, fonts, accent, s)
                }
            }
            Box(Modifier.padding(top = 8.dp)) {
                ShareCardFooter(ink = ProfileSheetInk.ink.copy(alpha = 0.7f), rule = ProfileSheetInk.ink.copy(alpha = 0.3f))
            }
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
private fun ProfileSheetHeading(layout: ProfileSheetLayout, fonts: ProfileFonts, s: Float) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            layout.title, style = ProfileSheetInk.named(fonts.title, 32 * s, tracking = 6f),
            color = ProfileSheetInk.ink, maxLines = 1, modifier = Modifier.alignByBaseline()
        )
        Text(
            layout.imprint, style = ProfileSheetInk.mono(9f, tracking = 2f), color = ProfileSheetInk.sub,
            maxLines = 1, modifier = Modifier.alignByBaseline()
        )
        Spacer(Modifier.weight(1f))
        Text(
            layout.asOf, style = ProfileSheetInk.sans(10.5f * s, FontWeight.SemiBold), color = ProfileSheetInk.ink,
            maxLines = 1, modifier = Modifier.alignByBaseline()
        )
    }
}

// MARK: - 履歴書

@Composable
private fun ProfileResumeBody(
    layout: ProfileSheetLayout,
    materials: ProfileSheetMaterials,
    fonts: ProfileFonts,
    accent: Color,
    s: Float
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy((8 * s).dp)) {
        ResumeIdentity(layout, materials, fonts, s)
        if (layout.brands.isNotEmpty()) ProfileBrandRange(layout.brandsTitle, layout.brands, s)
        if (layout.history.isNotEmpty() || layout.licenses.isNotEmpty()) {
            ProfileBox {
                Column {
                    if (layout.history.isNotEmpty()) {
                        ProfileTableHead("P歴（学歴・職歴）", accent, s)
                        layout.history.forEachIndexed { i, row ->
                            if (i > 0) ProfileRule()
                            ProfileHistoryLine(row, s)
                        }
                    }
                    if (layout.licenses.isNotEmpty()) {
                        if (layout.history.isNotEmpty()) ProfileRule(ProfileSheetInk.FRAME)
                        ProfileTableHead("免許・資格", accent, s)
                        layout.licenses.forEachIndexed { i, row ->
                            if (i > 0) ProfileRule()
                            ProfileHistoryLine(row, s)
                        }
                    }
                }
            }
        }
        // 志望の動機は横いっぱい、趣味・特技と本人希望記入欄は左右に並べる (様式の欄の並び)。
        layout.sections.filter { it.slot == ProfileSlot.MOTIVATION }.forEach { section ->
            ProfileBox { ProfileSectionView(section, fonts, s) }
        }
        val pair = layout.sections.filter { it.slot != ProfileSlot.MOTIVATION }
        if (pair.isNotEmpty()) {
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy((8 * s).dp)) {
                pair.forEach { section ->
                    ProfileBox(Modifier.weight(1f).fillMaxHeight()) { ProfileSectionView(section, fonts, s) }
                }
            }
        }
    }
}

/** 氏名・ふりがな・押印・P歴・担当・連絡先と証明写真。 */
@Composable
private fun ResumeIdentity(layout: ProfileSheetLayout, materials: ProfileSheetMaterials, fonts: ProfileFonts, s: Float) {
    ProfileBox {
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
            Column(Modifier.weight(1f)) {
                ProfileField("ふりがな", s) {
                    Text(
                        layout.furigana.ifEmpty { " " }, style = ProfileSheetInk.sans(10.5f * s, FontWeight.Medium),
                        color = ProfileSheetInk.ink, maxLines = 1
                    )
                }
                ProfileRule()
                ProfileField("氏名", s) {
                    Row(
                        Modifier.fillMaxWidth().padding(vertical = (2 * s).dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        ProfileFitText(
                            layout.name, style = ProfileSheetInk.named(fonts.name, 30 * s), color = ProfileSheetInk.ink,
                            maxLines = 1, minScale = 0.5f, modifier = Modifier.weight(1f)
                        )
                        val oshi = materials.oshi.firstOrNull()
                        if (layout.showOshi && oshi != null) ProfileSeal(oshi, 46 * s)
                    }
                }
                layout.sinceLabel?.let { since ->
                    ProfileRule()
                    ProfileField("P歴", s) {
                        Text(since, style = ProfileSheetInk.sans(10.5f * s, FontWeight.Bold), color = ProfileSheetInk.ink, maxLines = 1)
                    }
                }
                if (layout.showOshi && materials.oshi.isNotEmpty()) {
                    ProfileRule()
                    ProfileField("担当", s) { ProfileOshiList(materials.oshi, s) }
                }
                val qr = materials.qrUrl?.takeIf { layout.showQr }
                if (layout.contacts.isNotEmpty() || qr != null) {
                    ProfileRule()
                    ProfileField("連絡先", s) {
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            ProfileFitText(
                                layout.contacts.joinToString("　"), style = ProfileSheetInk.mono(10.5f * s),
                                color = ProfileSheetInk.ink, maxLines = 2, minScale = 0.7f, modifier = Modifier.weight(1f)
                            )
                            if (qr != null) ProfileQR(qr)
                        }
                    }
                }
            }
            Box(Modifier.width(ProfileSheetInk.FRAME.dp).fillMaxHeight().background(ProfileSheetInk.ink))
            Box(Modifier.fillMaxHeight().padding((8 * s).dp), contentAlignment = Alignment.Center) {
                ProfilePhotoBox(if (layout.showPhoto) materials.portrait else null, 92 * s)
            }
        }
    }
}

// MARK: - 職務経歴書

@Composable
private fun ProfileCareerBody(
    layout: ProfileSheetLayout,
    materials: ProfileSheetMaterials,
    fonts: ProfileFonts,
    accent: Color,
    s: Float
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy((8 * s).dp)) {
        CareerIdentity(layout, materials, fonts, s)
        layout.sections.filter { it.slot == ProfileSlot.SUMMARY }.forEach { section ->
            ProfileHeadline(section.title, section.imprint, accent, s)
            ProfileEntries(section.entries, fonts, s)
        }
        if (layout.career.isNotEmpty()) {
            ProfileHeadline("職務経歴", "CAREER", accent, s)
            CareerTable(layout, accent, s)
        }
        val showOshi = layout.showOshi && materials.oshi.isNotEmpty()
        if (showOshi || layout.brands.isNotEmpty()) {
            ProfileHeadline("担当・ブランド", "IN CHARGE", accent, s)
            if (showOshi) ProfileOshiList(materials.oshi, s)
            if (layout.brands.isNotEmpty()) ProfileBrandRange(layout.brandsTitle, layout.brands, s)
        }
        layout.sections.filter { it.slot != ProfileSlot.SUMMARY }.forEach { section ->
            ProfileHeadline(section.title, section.imprint, accent, s)
            ProfileEntries(section.entries, fonts, s)
        }
        Text(
            "以上", style = ProfileSheetInk.sans(11 * s, FontWeight.Bold), color = ProfileSheetInk.ink,
            textAlign = TextAlign.End, modifier = Modifier.fillMaxWidth()
        )
    }
}

/** 右上に氏名と押印・証明写真 (職務経歴書の頭)。 */
@Composable
private fun CareerIdentity(layout: ProfileSheetLayout, materials: ProfileSheetMaterials, fonts: ProfileFonts, s: Float) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy((12 * s).dp),
        verticalAlignment = Alignment.Bottom
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy((4 * s).dp)) {
            layout.sinceLabel?.let {
                Text(it, style = ProfileSheetInk.sans(10.5f * s, FontWeight.Bold), color = ProfileSheetInk.ink)
            }
            if (layout.contacts.isNotEmpty()) {
                ProfileFitText(
                    layout.contacts.joinToString("　"), style = ProfileSheetInk.mono(10f * s), color = ProfileSheetInk.sub,
                    maxLines = 2, minScale = 0.7f
                )
            }
        }
        Column(Modifier.width(IntrinsicSize.Max), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (layout.furigana.isNotEmpty()) {
                Text(layout.furigana, style = ProfileSheetInk.sans(9.5f * s, FontWeight.Medium), color = ProfileSheetInk.sub, maxLines = 1)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("氏名", style = ProfileSheetInk.sans(9 * s, FontWeight.Bold), color = ProfileSheetInk.sub)
                Text(layout.name, style = ProfileSheetInk.named(fonts.name, 26 * s), color = ProfileSheetInk.ink, maxLines = 1)
                val oshi = materials.oshi.firstOrNull()
                if (layout.showOshi && oshi != null) ProfileSeal(oshi, 40 * s)
            }
            Box(Modifier.fillMaxWidth().height(ProfileSheetInk.FRAME.dp).background(ProfileSheetInk.ink))
        }
        materials.qrUrl?.takeIf { layout.showQr }?.let { ProfileQR(it) }
        if (layout.showPhoto && materials.portrait != null) ProfilePhotoBox(materials.portrait, 60 * s)
    }
}

@Composable
private fun CareerTable(layout: ProfileSheetLayout, accent: Color, s: Float) {
    ProfileBox {
        Column {
            layout.career.forEachIndexed { i, year ->
                if (i > 0) ProfileRule(ProfileSheetInk.FRAME)
                Row(
                    Modifier.fillMaxWidth().accentUnderline(accent).padding(horizontal = 8.dp, vertical = (3 * s).dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(year.year, style = ProfileSheetInk.sans(12 * s, FontWeight.ExtraBold), color = ProfileSheetInk.ink)
                    Spacer(Modifier.weight(1f))
                    Text(year.countLabel, style = ProfileSheetInk.mono(10 * s, FontWeight.Bold), color = ProfileSheetInk.ink)
                }
                year.rows.forEachIndexed { j, row ->
                    if (j > 0) ProfileRule()
                    ProfileCareerLine(row, accent, s)
                }
            }
            if (layout.careerMore > 0u) {
                ProfileRule()
                Text(
                    "ほか ${layout.careerMore} 公演", style = ProfileSheetInk.sans(9.5f * s, FontWeight.SemiBold),
                    color = ProfileSheetInk.sub, textAlign = TextAlign.End,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = (3 * s).dp)
                )
            }
        }
    }
}

@Composable
private fun ProfileCareerLine(row: ProfileCareerRow, accent: Color, s: Float) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = (3 * s).dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            row.date, style = ProfileSheetInk.mono(10 * s, FontWeight.Bold), color = ProfileSheetInk.ink,
            maxLines = 1, modifier = Modifier.width((40 * s).dp)
        )
        val text = buildAnnotatedString {
            withStyle(SpanStyle(fontSize = (10 * s).sp, fontWeight = FontWeight.Bold, color = ProfileSheetInk.ink)) { append(row.title) }
            row.venue?.let {
                withStyle(SpanStyle(fontSize = (8.5f * s).sp, fontWeight = FontWeight.Medium, color = ProfileSheetInk.sub)) {
                    append("　$it")
                }
            }
        }
        Text(text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        if (row.planned) {
            Text(
                "予定", style = ProfileSheetInk.sans(9 * s, FontWeight.ExtraBold), color = accent,
                modifier = Modifier.rotate(-6f).border(1.5.dp, accent).padding(horizontal = 5.dp, vertical = 1.dp)
            )
        } else {
            row.brand?.let {
                Text(it, style = ProfileSheetInk.sans(9 * s, FontWeight.Bold), color = ProfileSheetInk.sub, maxLines = 1)
            }
        }
    }
}

// MARK: - 部品 (プロフィール帳の中だけ)

/** 太い墨の罫で囲む欄。 */
@Composable
private fun ProfileBox(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.fillMaxWidth().border(ProfileSheetInk.FRAME.dp, ProfileSheetInk.ink)) { content() }
}

@Composable
private fun ProfileRule(width: Float = ProfileSheetInk.RULE) {
    Box(Modifier.fillMaxWidth().height(width.dp).background(ProfileSheetInk.ink))
}

/** 下に担当色の太い罫 (表の頭)。 */
private fun Modifier.accentUnderline(accent: Color): Modifier = drawWithContent {
    drawContent()
    val h = 2.5.dp.toPx()
    drawRect(accent, topLeft = Offset(0f, size.height - h), size = Size(size.width, h))
}

/** 項目名 (印字) と中身の 1 段。 */
@Composable
private fun ProfileField(label: String, s: Float, content: @Composable () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = (4 * s).dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            label, style = ProfileSheetInk.sans(8.5f * s, FontWeight.Bold), color = ProfileSheetInk.sub,
            maxLines = 1, modifier = Modifier.width((40 * s).dp)
        )
        Box(Modifier.weight(1f)) { content() }
    }
}

/** 表の頭 (年・月・内容)。下の罫だけ担当色で太く。 */
@Composable
private fun ProfileTableHead(title: String, accent: Color, s: Float) {
    val style = ProfileSheetInk.sans(9 * s, FontWeight.ExtraBold)
    ProfileHistoryColumns("年", "月", style, s, Modifier.accentUnderline(accent)) {
        Text(title, style = style, color = ProfileSheetInk.ink, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun ProfileHistoryLine(row: ProfileHistoryRow, s: Float) {
    val closing = row.kind == ProfileHistoryKind.CLOSING
    val style = ProfileSheetInk.sans(10 * s, if (closing) FontWeight.Bold else FontWeight.Medium, tabular = true)
    ProfileHistoryColumns(row.year, row.month, style, s) {
        Text(
            row.text, style = style, color = ProfileSheetInk.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
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
    s: Float,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Row(
        modifier.fillMaxWidth().padding(vertical = (2.5f * s).dp).height(IntrinsicSize.Min),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(year, style = style, color = ProfileSheetInk.ink, textAlign = TextAlign.Center, maxLines = 1, modifier = Modifier.width((40 * s).dp))
        Box(Modifier.width(ProfileSheetInk.RULE.dp).fillMaxHeight().background(ProfileSheetInk.ink))
        Text(month, style = style, color = ProfileSheetInk.ink, textAlign = TextAlign.Center, maxLines = 1, modifier = Modifier.width((26 * s).dp))
        Box(Modifier.width(ProfileSheetInk.RULE.dp).fillMaxHeight().background(ProfileSheetInk.ink))
        Box(Modifier.weight(1f).padding(horizontal = 8.dp)) { content() }
    }
}

/** 欄 (題と、質問・答えの並び)。 */
@Composable
private fun ProfileSectionView(section: ProfileSection, fonts: ProfileFonts, s: Float) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = (6 * s).dp),
        verticalArrangement = Arrangement.spacedBy((4 * s).dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(section.title, style = ProfileSheetInk.sans(10.5f * s, FontWeight.ExtraBold), color = ProfileSheetInk.ink, modifier = Modifier.alignByBaseline())
            Text(
                section.imprint, style = ProfileSheetInk.mono(8f, tracking = 1.5f), color = ProfileSheetInk.sub,
                maxLines = 1, modifier = Modifier.alignByBaseline()
            )
        }
        ProfileEntries(section.entries, fonts, s)
    }
}

/** 質問 (印字の小さな字) と答え (P名刺の書体)。自動の項目は印字で。 */
@Composable
private fun ProfileEntries(entries: List<ProfileEntry>, fonts: ProfileFonts, s: Float) {
    Column(verticalArrangement = Arrangement.spacedBy((4 * s).dp)) {
        entries.forEach { entry ->
            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                if (entry.label.isNotEmpty()) {
                    Text(entry.label, style = ProfileSheetInk.sans(8.5f * s, FontWeight.Bold), color = ProfileSheetInk.sub)
                }
                Text(
                    entry.text,
                    style = if (entry.isAuto) ProfileSheetInk.sans(11 * s, FontWeight.SemiBold)
                    else ProfileSheetInk.named(fonts.name, 12.5f * s),
                    color = ProfileSheetInk.ink
                )
            }
        }
    }
}

/** 職務経歴書の見出し (担当色の四角 + 題 + 英字の印字)。 */
@Composable
private fun ProfileHeadline(title: String, imprint: String, accent: Color, s: Float) {
    Row(
        Modifier.fillMaxWidth().padding(top = (2 * s).dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size((9 * s).dp).background(accent))
        Text(title, style = ProfileSheetInk.sans(12 * s, FontWeight.ExtraBold), color = ProfileSheetInk.ink, maxLines = 1)
        Text(imprint, style = ProfileSheetInk.mono(8f, tracking = 1.5f), color = ProfileSheetInk.sub, maxLines = 1)
        Box(Modifier.weight(1f).height(ProfileSheetInk.RULE.dp).background(ProfileSheetInk.ink))
    }
}

/** 担当ブランド: 刷ってあるブランドの名前に、担当しているものだけ手描きの丸。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ProfileBrandRange(title: String, brands: List<ProfileBrandCheck>, s: Float) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = (2 * s).dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, style = ProfileSheetInk.sans(9 * s, FontWeight.ExtraBold), color = ProfileSheetInk.ink, maxLines = 1)
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy((16 * s).dp),
            verticalArrangement = Arrangement.spacedBy((8 * s).dp)
        ) {
            brands.forEach { brand ->
                val circle = if (brand.checked) profileAccent(brand.color) else null
                Text(
                    brand.label,
                    style = ProfileSheetInk.sans(10.5f * s, FontWeight.Bold),
                    color = if (brand.checked) ProfileSheetInk.ink else ProfileSheetInk.sub,
                    maxLines = 1,
                    modifier = Modifier
                        .padding(horizontal = 4.dp, vertical = 2.dp)
                        .drawBehind {
                            if (circle != null) drawHandCircle(brand, circle, padX = 4.dp.toPx() + 3.dp.toPx(), padY = 2.dp.toPx() + 4.dp.toPx())
                        }
                )
            }
        }
    }
}

/**
 * 手描きの丸 (iOS `ProfileHandCircle`)。少し傾け、横に伸び縮みさせ、書き終わりを行き過ぎて重ねる。
 * 揺らぎはコアが id から決める。[padX] / [padY] だけ文字の外に広げて描く。
 */
private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawHandCircle(
    brand: ProfileBrandCheck,
    color: Color,
    padX: Float,
    padY: Float
) {
    val w = size.width + padX * 2
    val h = size.height + padY * 2
    val cx = size.width / 2
    val cy = size.height / 2
    val rx = w / 2 * brand.stretch
    val ry = h / 2.0
    val a0 = brand.startDegrees * PI / 180
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
    rotate(brand.tiltDegrees.toFloat(), pivot = Offset(cx, cy)) {
        drawPath(path, color, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** 押印欄の判子 (担当の名前を担当色の二重の丸に。少し傾けて押す)。 */
@Composable
private fun ProfileSeal(oshi: ProfileSheetOshi, diameter: Float) {
    val color = profileAccent(oshi.color ?: oshi.brandColor)
    val chars = oshi.shortName.codePoints().toArray().map { String(Character.toChars(it)) }
    Box(
        Modifier
            .size(diameter.dp)
            .rotate(-12f)
            .border(2.5.dp, color, CircleShape)
            .padding(4.dp)
            .border(1.dp, color, CircleShape),
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
                modifier = Modifier.padding(horizontal = (diameter * 0.14f - 4).coerceAtLeast(0f).dp)
            )
        }
    }
}

/** 担当の並び (写真か判子 + 名前)。 */
@Composable
private fun ProfileOshiList(oshi: List<ProfileSheetOshi>, s: Float) {
    Row(horizontalArrangement = Arrangement.spacedBy((10 * s).dp), verticalAlignment = Alignment.CenterVertically) {
        oshi.forEach { idol ->
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                ProfileOshiIcon(idol, 24 * s)
                ProfileFitText(
                    idol.name, style = ProfileSheetInk.sans(10.5f * s, FontWeight.Bold), color = ProfileSheetInk.ink,
                    maxLines = 1, minScale = 0.6f
                )
            }
        }
    }
}

/** 担当のアイコン (写真が無ければ判子)。 */
@Composable
private fun ProfileOshiIcon(oshi: ProfileSheetOshi, size: Float) {
    val color = profileAccent(oshi.color ?: oshi.brandColor)
    Box(
        Modifier.size(size.dp).clip(CircleShape).background(ProfileSheetInk.paper).border(1.5.dp, color, CircleShape),
        contentAlignment = Alignment.Center
    ) {
        val image = oshi.image
        if (image != null) {
            Image(image.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
            ProfileFitText(
                oshi.shortName, style = ProfileSheetInk.sans(size * 0.34f, FontWeight.Bold), color = color,
                maxLines = 1, minScale = 0.5f, textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = (size * 0.1f).dp)
            )
        }
    }
}

/** 証明写真の欄。写真が無ければ履歴書の「写真をはる位置」を刷っておく。 */
@Composable
private fun ProfilePhotoBox(image: Bitmap?, width: Float) {
    val height = width * 4 / 3
    Box(
        Modifier
            .size(width.dp, height.dp)
            .clipToBounds()
            .drawWithContent {
                drawContent()
                val stroke = 1.dp.toPx()
                drawRect(
                    ProfileSheetInk.ink, topLeft = Offset(stroke / 2, stroke / 2),
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
            Image(image.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("写真をはる位置", style = ProfileSheetInk.sans(8f, FontWeight.Bold), color = ProfileSheetInk.sub, textAlign = TextAlign.Center)
                Text(
                    "縦 36〜40mm\n横 24〜30mm", style = ProfileSheetInk.sans(7f, FontWeight.Medium),
                    color = ProfileSheetInk.sub, textAlign = TextAlign.Center
                )
            }
        }
    }
}

@Composable
private fun ProfileQR(url: String) {
    val matrix = remember(url) { imasQrMatrix(url) }
    Box(Modifier.background(ProfileSheetInk.paper).padding(4.dp)) {
        Canvas(Modifier.size(ProfileSheetInk.QR_SIDE.dp)) { if (matrix != null) drawQr(matrix, ProfileSheetInk.ink) }
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
    val holder = remember { arrayOfNulls<TextLayoutResult>(1) }
    val base = style.copy(color = color, textAlign = textAlign ?: style.textAlign)
    Layout(
        content = {},
        modifier = modifier.drawBehind { holder[0]?.let { drawText(it) } }
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
        holder[0] = result
        val w = result.size.width
        layout(w.coerceIn(constraints.minWidth, constraints.maxWidth), result.size.height.coerceIn(constraints.minHeight, constraints.maxHeight)) {}
    }
}
