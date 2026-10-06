package com.fugaif.imaslivedb.ui.designsystem

import android.graphics.Bitmap
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.SubcomposeAsyncImage
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.google.zxing.common.BitMatrix
import java.text.NumberFormat
import java.util.Locale

// =============================================================================
// 名刺の紙 (91:55) の表と裏 (docs/DESIGN_SYSTEM.md §6.13)。iOS `ImasMeishi.swift` の移植。
//
// 画面の P名刺 (`ImasProducerCard`) と紙に刷る画像 (`ProducerCardPrintFront` / `Back`) が同じ組みで描く。
// 違うのは紙と墨の色 ([ImasMeishiInk]: 画面はチケットの紙、紙に刷る画像は固定色) と、
// 画像の渡し方 ([ImasMeishiPicture]: 画面は URL を読み込み、刷る画像は読み込み済みの Bitmap。
// 焼くのは今描かれているものだけで読み込みを待たないので、刷る側は必ず Bitmap で渡す) だけ。
//
// 寸法は名刺の紙の上の寸法 ([ImasMeishi.WIDTH] × [ImasMeishi.HEIGHT] = 364×220 の紙) で決め、`scale` 倍して描く。
// 画面は幅に合わせた倍率、紙に刷る画像は 1.5 倍の紙 (546×330) を 3 倍で焼く (1638×990px)。
// 文字も紙の上の大きさで固定する (名刺は物。端末の文字の大きさに追わない。読み上げと大きな文字は名刺の下の詳細が受け持つ)。
//
// ImasMeishiFront  表。名前 (デザインの書体)・P歴・名刺の写真 (正方形の枠。X のアイコンは丸)・担当 (判子か写真を
//                  ブランドごとにまとめて小さく並べ、下に「星井美希 担当」か、ブランドが 2 つ以上なら
//                  まとまりごとにブランドの略称。並べる人・まとめ方・文言はコアの `producerCardFace`)・ハンドル 1 つ。
//                  - 入場証 (PASS): 左に担当色の縦の帯。
//                  - かしこまった名刺 (FORMAL): 細い罫と明朝、担当色は罫と判子だけ。
//                  - ポップ (POP): 墨の太い枠と担当色の太い帯、名前の下に担当色の太い線。
//                  - 担当を大きく (OSHI): 左半分に担当の画像を大きく (1 人なら 1 枚、複数なら分けて。先頭ほど
//                    大きな枠。並びはコアの `CardFace.heroIdolIds`)。画像の無い担当は大きな判子と名前。
//                    右に名前・P歴・名刺の写真・ハンドル。境目に担当色の細い縦の線。
// ImasMeishiBack   裏。QR (交換用か自分の QR)・参加公演数・回収曲数・「YYYY.MM.DD 時点」。
// ImasMeishiStamp  表に並べる担当 1 人 (写真があれば写真、無ければ判子)。
// ImasMeishiHero   担当を大きく の左の枠 (担当の画像を枠いっぱいに分けて並べる)。
// =============================================================================

object ImasMeishi {
    /** 名刺の紙の大きさ (dp)。日本の名刺の比 (91:55) で、画面の幅とほぼ同じ。 */
    const val WIDTH = 364f
    const val HEIGHT = 220f

    /** 紙の縦横比。 */
    const val ASPECT = WIDTH / HEIGHT

    /** 担当を大きく の左の担当の画像の枠の幅 (紙の半分より少し狭く、右の名前の欄を確保する)。 */
    const val HERO_WIDTH = 170f

    /**
     * 担当を大きく の人数ごとの枠 (枠全体を 1 とした割合。先頭ほど大きな枠)。iOS `ImasMeishiHero.tiles`。
     * 1 人: 1 枚 / 2 人: 左右 / 3 人: 左に先頭、右に 2 段 / 4 人: 2×2 / 5 人: 上に 2 枚、下に 3 枚。
     */
    fun heroTiles(count: Int): List<Rect> = when (count) {
        0 -> emptyList()
        1 -> listOf(Rect(0f, 0f, 1f, 1f))
        2 -> listOf(Rect(0f, 0f, 0.5f, 1f), Rect(0.5f, 0f, 1f, 1f))
        3 -> listOf(Rect(0f, 0f, 0.5f, 1f), Rect(0.5f, 0f, 1f, 0.5f), Rect(0.5f, 0.5f, 1f, 1f))
        4 -> listOf(Rect(0f, 0f, 0.5f, 0.5f), Rect(0.5f, 0f, 1f, 0.5f), Rect(0f, 0.5f, 0.5f, 1f), Rect(0.5f, 0.5f, 1f, 1f))
        else -> {
            val top = 0.55f
            val third = 1f / 3f
            listOf(Rect(0f, 0f, 0.5f, top), Rect(0.5f, 0f, 1f, top)) +
                (0 until 3).map { Rect(it * third, top, (it + 1) * third, 1f) }
        }
    }
}

/** 名刺の紙と墨の色。 */
@Immutable
data class ImasMeishiInk(
    val paper: Color,
    val ink: Color,
    val sub: Color,
    /** 細い罫・写真の縁。 */
    val line: Color,
    /** 担当の色 (帯・罫・下線)。担当がいなければ墨。 */
    val accent: Color,
    /** 担当の色の帯の上の文字。 */
    val onAccent: Color
) {
    companion object {
        /**
         * 画面の名刺。ダークでも紙は明るいチケットの紙 (QR を読めるように・紙の名刺に見えるように)。
         * 担当の色は明るい紙の上の色で引く。
         */
        @Composable
        fun screen(seed: String?, brand: String?): ImasMeishiInk {
            val theme = ImasTheme.derive(seed = seed, brand = brand, dark = false)
            return ImasMeishiInk(
                paper = DS.ticket, ink = DS.ticketInk, sub = DS.ticketSub, line = DS.ticketDash,
                accent = if (theme.isNeutral) DS.ticketInk else theme.accent,
                onAccent = if (theme.isNeutral) DS.ticket else theme.onAccent
            )
        }

        /** 担当の判子の色 (明るい紙の上の担当の色)。 */
        fun stampColor(seed: String?, brand: String?, ink: Color): Color {
            val theme = ImasTheme.derive(seed = seed, brand = brand, dark = false)
            return if (theme.isNeutral) ink else theme.accent
        }
    }
}

/** 名刺に載せる画像。画面は URL (読み込みながら出す)、紙に刷る画像は読み込み済みの Bitmap。 */
@Immutable
sealed interface ImasMeishiPicture {
    data class Url(val url: String) : ImasMeishiPicture
    data class Image(val bitmap: Bitmap) : ImasMeishiPicture
}

/** 名刺の表に並べる担当 1 人。 */
@Immutable
data class ImasMeishiOshi(
    val id: String,
    val name: String,
    /** 判子の略称。 */
    val shortName: String,
    /** 判子の色 (担当の色)。 */
    val color: Color,
    val picture: ImasMeishiPicture? = null
)

/** 名刺の表で 1 つのブランドにまとめて並べる担当 (コアの `CardFaceOshiGroup`)。 */
@Immutable
data class ImasMeishiOshiGroup(
    /** ブランドの略称 (「765AS」)。名前の行が無いときだけ判子の下に刷る。空なら刷らない。 */
    val label: String,
    val oshi: List<ImasMeishiOshi>
)

/** 表の組み (名刺のデザイン。自作の画像は画像そのもの)。 */
enum class ImasMeishiLook { PASS, FORMAL, POP, OSHI }

/** 紙の上の寸法を倍率で描くための換算 (文字は端末の文字の大きさに追わない)。 */
private class MeishiScale(val scale: Float, private val fontScale: Float) {
    fun dp(v: Float): Dp = (v * scale).dp
    fun sp(v: Float): TextUnit = (v * scale / fontScale).sp

    /** 細い線は 0.5 を割らない。 */
    fun hair(v: Float): Dp = maxOf(v * scale, 0.5f).dp
}

@Composable
private fun rememberMeishiScale(scale: Float): MeishiScale {
    val fontScale = LocalDensity.current.fontScale
    return remember(scale, fontScale) { MeishiScale(scale, fontScale) }
}

/** 等幅・明朝・丸ゴシック (iOS の `.monospaced` / `.serif` / `.rounded`)。 */
private enum class MeishiFace(val family: FontFamily) {
    MONO(FontFamily.Monospace), SERIF(FontFamily.Serif), ROUNDED(FontFamily.SansSerif)
}

// MARK: - 表

/**
 * 名刺の表。大きさは紙の寸法 × [scale] に固定する。
 *
 * @param sinceImprint 「SINCE 2014」(コアの `CardFace.sinceImprint`)。
 * @param oshiGroups 表に並べる担当のブランドごとのまとまり (コアの `CardFace.oshiGroups` の順)。
 * @param hero 担当を大きく並べる順 (担当を大きく のデザインだけ。コアの `CardFace.heroIdolIds` の順)。
 * @param oshiCaption 判子の下の 1 行 (コアの `CardFace.oshiCaption`)。null ならまとまりごとにブランドの略称を刷る。
 * @param moreOshi 数で畳んだ担当の人数 (「+2」)。
 * @param handle 右下に刷るハンドル (「@fuga_p」)。
 * @param nameFamily 名前の書体 (デザインの書体)。null は見出しの書体の極太。
 * @param portrait 名刺の写真 (右に正方形の枠で)。
 * @param portraitRound 名刺の写真を丸く切る (X のアイコン。切り方はコアの `cardPhotoShape`)。
 */
@Composable
fun ImasMeishiFront(
    name: String,
    ink: ImasMeishiInk,
    modifier: Modifier = Modifier,
    look: ImasMeishiLook = ImasMeishiLook.PASS,
    sinceImprint: String? = null,
    oshiGroups: List<ImasMeishiOshiGroup> = emptyList(),
    hero: List<ImasMeishiOshi> = emptyList(),
    oshiCaption: String? = null,
    moreOshi: Int = 0,
    handle: String? = null,
    nameFamily: FontFamily? = null,
    portrait: ImasMeishiPicture? = null,
    portraitRound: Boolean = false,
    scale: Float = 1f
) {
    val p = rememberMeishiScale(scale)
    val parts = MeishiFrontParts(name, ink, sinceImprint, oshiGroups, hero, oshiCaption, moreOshi, handle, nameFamily, portrait, portraitRound, p)
    Box(modifier.requiredSize(p.dp(ImasMeishi.WIDTH), p.dp(ImasMeishi.HEIGHT)).background(ink.paper)) {
        when (look) {
            ImasMeishiLook.PASS -> PassFront(parts)
            ImasMeishiLook.FORMAL -> FormalFront(parts)
            ImasMeishiLook.POP -> PopFront(parts)
            ImasMeishiLook.OSHI -> OshiFront(parts)
        }
    }
}

private class MeishiFrontParts(
    val name: String,
    val ink: ImasMeishiInk,
    val sinceImprint: String?,
    val oshiGroups: List<ImasMeishiOshiGroup>,
    val hero: List<ImasMeishiOshi>,
    val oshiCaption: String?,
    val moreOshi: Int,
    val handle: String?,
    val nameFamily: FontFamily?,
    val portrait: ImasMeishiPicture?,
    val portraitRound: Boolean,
    val p: MeishiScale
)

/** 入場証 (担当色の縦の帯)。 */
@Composable
private fun PassFront(m: MeishiFrontParts) {
    val p = m.p
    Row(Modifier.fillMaxSize()) {
        Box(Modifier.width(p.dp(18f)).fillMaxHeight().background(m.ink.accent))
        Row(
            Modifier.fillMaxSize().padding(horizontal = p.dp(18f), vertical = p.dp(16f)),
            horizontalArrangement = Arrangement.spacedBy(p.dp(14f)),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f).fillMaxHeight()) {
                Imprint(m, "PRODUCER PASS", MeishiFace.MONO)
                Spacer(Modifier.weight(1f).heightIn(min = p.dp(4f)))
                NameText(m, 26f)
                OshiBlock(
                    m, stamp = 22f,
                    caption = meishiText(p, 8.5f, FontWeight.Normal, MeishiFace.SERIF),
                    label = meishiText(p, 6f, FontWeight.SemiBold, MeishiFace.MONO),
                    modifier = Modifier.padding(top = p.dp(6f))
                )
                Spacer(Modifier.weight(1f).heightIn(min = p.dp(4f)))
                Footer(m, MeishiFace.MONO, FontWeight.Medium)
            }
            Portrait(m, m.ink.line, 0.5f)
        }
    }
}

/** かしこまった名刺 (担当色は名前の上の細い罫と判子だけ)。 */
@Composable
private fun FormalFront(m: MeishiFrontParts) {
    val p = m.p
    Row(
        Modifier.fillMaxSize().padding(horizontal = p.dp(26f), vertical = p.dp(20f)),
        horizontalArrangement = Arrangement.spacedBy(p.dp(16f)),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f).fillMaxHeight()) {
            Imprint(m, "PRODUCER", MeishiFace.SERIF, tracking = 1.6f)
            Box(Modifier.padding(top = p.dp(5f)).fillMaxWidth().height(p.hair(0.5f)).background(m.ink.accent))
            Spacer(Modifier.weight(1f).heightIn(min = p.dp(4f)))
            OshiBlock(
                m, stamp = 18f,
                caption = meishiText(p, 8f, FontWeight.Normal, MeishiFace.SERIF),
                label = meishiText(p, 6f, FontWeight.Medium, MeishiFace.SERIF),
                modifier = Modifier.padding(bottom = p.dp(5f))
            )
            NameText(m, 25f, tracking = 1.3f)
            Spacer(Modifier.weight(1f).heightIn(min = p.dp(4f)))
            Footer(m, MeishiFace.SERIF, FontWeight.Normal)
        }
        Portrait(m, m.ink.line, 0.5f)
    }
}

/** ポップ (墨の太い枠・担当色の太い帯と名前の下の太い線)。 */
@Composable
private fun PopFront(m: MeishiFrontParts) {
    val p = m.p
    Column(
        Modifier.fillMaxSize().drawWithContent {
            drawContent()
            val w = p.dp(5f).toPx()
            drawRect(m.ink.ink, Offset(w / 2, w / 2), Size(size.width - w, size.height - w), style = Stroke(w))
        }
    ) {
        Box(
            Modifier.fillMaxWidth().height(p.dp(28f)).background(m.ink.accent).padding(horizontal = p.dp(16f)),
            contentAlignment = Alignment.CenterStart
        ) {
            Text(
                imprintText(m, "PRODUCER!"),
                style = meishiText(p, 7.5f, FontWeight.Black, MeishiFace.ROUNDED, tracking = 0.8f),
                color = m.ink.onAccent, maxLines = 1
            )
        }
        Box(Modifier.fillMaxWidth().height(p.dp(3f)).background(m.ink.ink))
        Row(
            Modifier.fillMaxSize().padding(horizontal = p.dp(16f), vertical = p.dp(12f)),
            horizontalArrangement = Arrangement.spacedBy(p.dp(14f)),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(p.dp(5f))) {
                NameText(m, 27f)
                Box(Modifier.size(p.dp(56f), p.dp(6f)).background(m.ink.accent))
                OshiBlock(
                    m, stamp = 20f,
                    caption = meishiText(p, 8.5f, FontWeight.Black, MeishiFace.ROUNDED),
                    label = meishiText(p, 6f, FontWeight.Black, MeishiFace.ROUNDED)
                )
                Spacer(Modifier.weight(1f))
                Footer(m, MeishiFace.ROUNDED, FontWeight.Black)
            }
            Portrait(m, m.ink.ink, 2f)
        }
    }
}

/** 担当を大きく (左半分に担当の画像、境目に担当色の細い縦の線、右に名前・P歴・名刺の写真・ハンドル)。 */
@Composable
private fun OshiFront(m: MeishiFrontParts) {
    val p = m.p
    Row(Modifier.fillMaxSize()) {
        ImasMeishiHero(
            oshi = m.hero, paper = m.ink.paper, ink = m.ink.ink, gap = p.dp(1.5f), scale = p.scale,
            modifier = Modifier.width(p.dp(ImasMeishi.HERO_WIDTH)).fillMaxHeight()
        )
        Box(Modifier.width(p.dp(3f)).fillMaxHeight().background(m.ink.accent))
        Column(
            Modifier.fillMaxSize().padding(p.dp(14f)),
            verticalArrangement = Arrangement.spacedBy(p.dp(6f))
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(p.dp(8f)), verticalAlignment = Alignment.Top) {
                Box(Modifier.weight(1f)) { Imprint(m, "PRODUCER", MeishiFace.MONO) }
                Portrait(m, m.ink.line, 0.5f, side = 44f)
            }
            NameText(m, 24f)
            HeroCaption(m)
            Spacer(Modifier.weight(1f))
            Footer(m, MeishiFace.MONO, FontWeight.Medium)
        }
    }
}

/** 担当を大きく の名前の下の 1 行 (「星井美希 担当」、無ければブランドの略称、畳んだ数)。 */
@Composable
private fun HeroCaption(m: MeishiFrontParts) {
    val labels = m.oshiGroups.map { it.label }.filter { it.isNotEmpty() }
    val line = m.oshiCaption ?: labels.takeIf { it.isNotEmpty() }?.joinToString("・")
    val more = if (m.moreOshi > 0) "+${m.moreOshi}" else null
    val text = listOfNotNull(line, more).joinToString("  ")
    if (text.isEmpty()) return
    ImasFitText(
        text, style = TextStyle(fontSize = m.p.sp(8f), fontWeight = FontWeight.Medium),
        color = m.ink.ink, maxLines = 2, minScale = 0.6f
    )
}

// MARK: 共通

private fun meishiText(p: MeishiScale, size: Float, weight: FontWeight, face: MeishiFace, tracking: Float = 0f) =
    TextStyle(fontFamily = face.family, fontSize = p.sp(size), fontWeight = weight, letterSpacing = p.sp(tracking))

private fun imprintText(m: MeishiFrontParts, head: String) = listOfNotNull(head, m.sinceImprint).joinToString(" · ")

@Composable
private fun Imprint(m: MeishiFrontParts, head: String, face: MeishiFace, tracking: Float = 1.1f) {
    Text(imprintText(m, head), style = meishiText(m.p, 6.5f, FontWeight.Medium, face, tracking), color = m.ink.sub, maxLines = 1)
}

@Composable
private fun NameText(m: MeishiFrontParts, size: Float, tracking: Float = 0f) {
    val style = m.nameFamily?.let { TextStyle(fontFamily = it, fontSize = m.p.sp(size), letterSpacing = m.p.sp(tracking)) }
        ?: TextStyle(fontSize = m.p.sp(size), fontWeight = FontWeight.ExtraBold, letterSpacing = m.p.sp(tracking))
    ImasFitText(m.name, style = style, color = m.ink.ink, maxLines = 2, minScale = 0.45f)
}

/**
 * 担当の判子 (写真) をブランドごとにまとめた並びと、その下の 1 行 (「星井美希 担当」) か
 * まとまりごとのブランドの略称。名刺に載る担当が全員、名前・写真と重ならずに並ぶ大きさ。
 */
@Composable
private fun OshiBlock(m: MeishiFrontParts, stamp: Float, caption: TextStyle, label: TextStyle, modifier: Modifier = Modifier) {
    if (m.oshiGroups.isEmpty()) return
    val p = m.p
    Column(modifier, verticalArrangement = Arrangement.spacedBy(p.dp(3f))) {
        Row(horizontalArrangement = Arrangement.spacedBy(p.dp(7f)), verticalAlignment = Alignment.Top) {
            m.oshiGroups.forEach { group ->
                Column(verticalArrangement = Arrangement.spacedBy(p.dp(2f))) {
                    Row(horizontalArrangement = Arrangement.spacedBy(p.dp(3f))) {
                        group.oshi.forEach { ImasMeishiStamp(it, p.dp(stamp), m.ink.paper) }
                    }
                    if (m.oshiCaption == null && group.label.isNotEmpty()) {
                        Text(group.label, style = label, color = m.ink.sub, maxLines = 1, softWrap = false)
                    }
                }
            }
            if (m.moreOshi > 0) {
                Box(
                    Modifier.size(p.dp(stamp)).border(p.hair(0.75f), m.ink.line, CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        "+${m.moreOshi}",
                        style = meishiText(p, stamp * 0.36f, FontWeight.Bold, MeishiFace.ROUNDED).copy(fontFeatureSettings = "tnum"),
                        color = m.ink.ink, maxLines = 1
                    )
                }
            }
        }
        m.oshiCaption?.let { ImasFitText(it, style = caption, color = m.ink.ink, maxLines = 1, minScale = 0.6f) }
    }
}

@Composable
private fun Footer(m: MeishiFrontParts, face: MeishiFace, weight: FontWeight) {
    val p = m.p
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
        // ハンドルは左、アプリの名前は右に寄せる (間は空ける)。
        Box(Modifier.weight(1f).padding(end = p.dp(6f))) {
            if (m.handle != null) {
                ImasFitText(m.handle, style = meishiText(p, 8f, weight, face), color = m.ink.ink, maxLines = 1, minScale = 0.6f)
            }
        }
        Text("IDOL LIVE DB", style = meishiText(p, 5.5f, weight, face, tracking = 1.1f), color = m.ink.sub, maxLines = 1)
    }
}

/**
 * 名刺の写真の正方形の枠 (X のアイコンは枠に内接する丸)。枠の大きさを先に決め、写真はその上に重ねて切る
 * (写真の比率で枠が膨らまないように。縦長の写真ではみ出したことがある)。
 */
@Composable
private fun Portrait(m: MeishiFrontParts, border: Color, width: Float, side: Float = 84f) {
    val picture = m.portrait ?: return
    val p = m.p
    val shape = if (m.portraitRound) CircleShape else RoundedCornerShape(p.dp(2f))
    Box(
        Modifier.size(p.dp(side)).clip(shape).border(p.hair(width), border, shape)
    ) { ImasMeishiPictureView(picture, Modifier.fillMaxSize()) }
}

// MARK: - 裏

/**
 * 名刺の裏。QR・参加公演数・回収曲数・「YYYY.MM.DD 時点」。
 *
 * @param qr QR の模様 ([imasQrMatrix])。null なら紙のまま (返せない見本は QR を描かない)。
 * @param note QR の横に刷る案内。
 * @param issuedLabel 「2026.10.06 時点」(コアの `CardFace.issuedLabel`)。
 */
@Composable
fun ImasMeishiBack(
    qr: BitMatrix?,
    note: String,
    issuedLabel: String,
    ink: ImasMeishiInk,
    modifier: Modifier = Modifier,
    showCount: Long? = null,
    songCount: Long? = null,
    scale: Float = 1f
) {
    val p = rememberMeishiScale(scale)
    Row(
        modifier
            .requiredSize(p.dp(ImasMeishi.WIDTH), p.dp(ImasMeishi.HEIGHT))
            .background(ink.paper)
            .padding(horizontal = p.dp(20f), vertical = p.dp(24f)),
        horizontalArrangement = Arrangement.spacedBy(p.dp(18f))
    ) {
        Canvas(Modifier.size(p.dp(164f))) { if (qr != null) drawQr(qr, ink.ink) }
        Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(p.dp(8f))) {
            showCount?.let { BackMetric(p, ink, it, "参加公演") }
            songCount?.let { BackMetric(p, ink, it, "回収曲") }
            Spacer(Modifier.weight(1f))
            Text(note, style = TextStyle(fontSize = p.sp(6.5f)), color = ink.sub)
            Text(issuedLabel, style = meishiText(p, 6.5f, FontWeight.Medium, MeishiFace.MONO), color = ink.sub, maxLines = 1)
        }
    }
}

@Composable
private fun BackMetric(p: MeishiScale, ink: ImasMeishiInk, value: Long, label: String) {
    Column {
        Text(
            NumberFormat.getIntegerInstance(Locale.JAPAN).format(value),
            style = TextStyle(fontSize = p.sp(23f), fontWeight = FontWeight.Black, fontFeatureSettings = "tnum", letterSpacing = p.sp(-0.6f)),
            color = ink.ink, maxLines = 1
        )
        Text(label, style = TextStyle(fontSize = p.sp(7f), fontWeight = FontWeight.SemiBold), color = ink.sub, maxLines = 1)
    }
}

// MARK: - 担当の判子

/** 表に並べる担当 1 人。写真があれば写真、無ければ紙に担当色の略称 (判子)。縁は担当色。 */
@Composable
fun ImasMeishiStamp(oshi: ImasMeishiOshi, size: Dp, paper: Color) {
    val density = LocalDensity.current
    val stamp: @Composable () -> Unit = {
        Box(Modifier.fillMaxSize().background(paper), contentAlignment = Alignment.Center) {
            val fontSize = with(density) { (size * 0.34f).toSp() }
            ImasFitText(
                oshi.shortName, style = TextStyle(fontSize = fontSize, fontWeight = FontWeight.Bold), color = oshi.color,
                maxLines = 1, minScale = 0.5f, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = size * 0.1f)
            )
        }
    }
    Box(
        Modifier.size(size).clip(CircleShape).border(maxOf(size * 0.07f, 0.75.dp), oshi.color, CircleShape)
    ) {
        val picture = oshi.picture
        if (picture == null) stamp() else ImasMeishiPictureView(picture, Modifier.fillMaxSize(), fallback = stamp)
    }
}

/**
 * 担当を大きく のデザインの左の枠。担当の画像を枠いっぱいに分けて並べる (先頭ほど大きな枠。並びは [ImasMeishi.heroTiles])。
 * 画像は枠の上に重ねて上寄せで切る (縦長の担当の画像で顔が切れにくいように)。画像の無い担当は大きな判子と名前。
 * iOS `ImasMeishiHero`。
 *
 * @param gap 枠と枠の間の紙の幅。
 */
@Composable
fun ImasMeishiHero(
    oshi: List<ImasMeishiOshi>,
    paper: Color,
    ink: Color,
    gap: Dp,
    modifier: Modifier = Modifier,
    scale: Float = 1f
) {
    BoxWithConstraints(modifier.background(paper).clipToBounds()) {
        val w = maxWidth
        val h = maxHeight
        ImasMeishi.heroTiles(oshi.size).forEachIndexed { index, tile ->
            val x = w * tile.left + gap / 2
            val y = h * tile.top + gap / 2
            val tw = (w * tile.width - gap).coerceAtLeast(0.dp)
            val th = (h * tile.height - gap).coerceAtLeast(0.dp)
            Box(Modifier.offset(x, y).size(tw, th).clipToBounds()) {
                HeroTile(oshi[index], paper, ink, scale, tw, th)
            }
        }
    }
}

/** 担当を大きく の枠 1 つ。画像は上寄せで枠いっぱい、無ければ判子と名前。 */
@Composable
private fun HeroTile(oshi: ImasMeishiOshi, paper: Color, ink: Color, scale: Float, width: Dp, height: Dp) {
    val side = minOf(width, height) * 0.62f
    val stamp: @Composable () -> Unit = {
        Column(
            Modifier.fillMaxSize().background(paper),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(side * 0.08f, Alignment.CenterVertically)
        ) {
            ImasMeishiStamp(oshi, side, paper)
            if (height > side * 1.5f) {
                val fontSize = with(LocalDensity.current) { maxOf(side * 0.14f, (6f * scale).dp).toSp() }
                ImasFitText(
                    oshi.name, style = TextStyle(fontSize = fontSize, fontWeight = FontWeight.SemiBold), color = ink,
                    maxLines = 1, minScale = 0.5f, textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = side * 0.1f)
                )
            }
        }
    }
    val picture = oshi.picture
    if (picture == null) stamp()
    else ImasMeishiPictureView(picture, Modifier.fillMaxSize(), alignment = Alignment.TopCenter, fallback = stamp)
}

/**
 * 名刺の画像 1 枚。置いた枠いっぱいに広げる (枠で切るのは置いた側)。
 * URL は読み込みながら出し、読めないあいだは [fallback] (判子など) か紙の地。
 * [alignment] は切るときに寄せる側 (担当を大きく は上寄せ)。
 */
@Composable
fun ImasMeishiPictureView(
    picture: ImasMeishiPicture,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
    alignment: Alignment = Alignment.Center,
    fallback: @Composable () -> Unit = { Box(Modifier.fillMaxSize().background(DS.surface2)) }
) {
    when (picture) {
        is ImasMeishiPicture.Image -> {
            val bitmap = remember(picture.bitmap) { picture.bitmap.asImageBitmap() }
            Image(bitmap, contentDescription = null, contentScale = contentScale, alignment = alignment, modifier = modifier)
        }
        is ImasMeishiPicture.Url -> SubcomposeAsyncImage(
            model = picture.url, contentDescription = null, contentScale = contentScale, alignment = alignment,
            modifier = modifier, loading = { fallback() }, error = { fallback() }
        )
    }
}
