package com.fugaif.imaslivedb.ui.share

import android.graphics.Bitmap
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.ui.draw.rotate
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.designsystem.ImasFitText
import com.fugaif.imaslivedb.ui.designsystem.drawQr
import com.fugaif.imaslivedb.ui.designsystem.imasQrMatrix
import com.fugaif.imaslivedb.ui.theme.DS

// =============================================================================
// 紙に刷る P名刺 (91×55mm、日本の名刺の大きさ)。iOS `ProducerCardPrintCard.swift` の移植。
//
// 表 = 名刺のデザインごとの組み (入場証は担当色の縦の帯、かしこまった名刺は明朝と細い罫、
//      ポップは墨の太い枠と担当色の太い帯)。名前・担当・ハンドル・名刺の写真 (あれば右に証明写真)。
//      自作の画像の名刺は、その画像をそのまま刷る (`ProducerCardPrintImage`)。
//      印刷所の名刺テンプレにそのまま載る余白を残す。
// 裏 = QR (既定はアプリの交換と同じ中身。自分の QR も選べる)・参加公演数と回収曲数・「YYYY.MM.DD 時点」。
//
// 固定のキャンバスに焼くので、色は固定色 (ShareInk / ShareCardPalette)、文字は固定の大きさ。
// =============================================================================

object ProducerCardPrint {
    /** 91:55 の論理サイズ。3 倍で焼いて 1638×990px (350dpi 相当)。 */
    val size = ShareCardSize(546, 330)
    const val RENDER_SCALE = 3f

    val ink = ShareInk.nearBlack
    val paper = ShareInk.offWhite
    val sub = Color(0xFF5A5755)

    fun mono(size: Float, weight: FontWeight = FontWeight.Medium, tracking: Float = 0f) = TextStyle(
        fontFamily = FontFamily.Monospace, fontWeight = weight, fontSize = size.sp, letterSpacing = tracking.sp
    )

    fun serif(size: Float, weight: FontWeight = FontWeight.Normal) =
        TextStyle(fontFamily = FontFamily.Serif, fontWeight = weight, fontSize = size.sp)

    fun sans(size: Float, weight: FontWeight = FontWeight.Normal) = TextStyle(fontWeight = weight, fontSize = size.sp)

    /** 名前の書体 (選んだ書体。引けなければ明朝の太字)。 */
    fun name(family: FontFamily?, size: Float) =
        family?.let { TextStyle(fontFamily = it, fontSize = size.sp) } ?: serif(size, FontWeight.SemiBold)
}

/** 表の組み (名刺のデザイン。自作の画像は [ProducerCardPrintImage])。 */
enum class ProducerCardPrintLook { PASS, FORMAL, POP }

/** 表。デザイン (入場証・かしこまった名刺・ポップ) ごとに組みを変える。載せるものは同じ。 */
@Composable
fun ProducerCardPrintFront(
    name: String,
    look: ProducerCardPrintLook = ProducerCardPrintLook.PASS,
    sinceYear: Int? = null,
    /** 担当の名前 (「天海春香・如月千早」)。 */
    oshiNames: List<String> = emptyList(),
    /** 担当の色 (帯・罫)。 */
    seed: String? = null,
    /** 右下に刷るハンドル (「@fuga_p」)。 */
    handle: String? = null,
    /** 名前の書体 (コアのデザインの書体から引いたもの)。 */
    nameFamily: FontFamily? = null,
    /** 名刺の写真 (右に証明写真の大きさで刷る)。 */
    portrait: Bitmap? = null
) {
    val palette = rememberShareCardPalette(seed)
    val accent = if (seed == null) ProducerCardPrint.ink else palette.accent
    Box(Modifier.fillMaxSize().background(ProducerCardPrint.paper)) {
        when (look) {
            ProducerCardPrintLook.PASS -> PassFront(name, sinceYear, oshiNames, handle, nameFamily, portrait, accent)
            ProducerCardPrintLook.FORMAL -> FormalFront(name, sinceYear, oshiNames, handle, nameFamily, portrait, accent)
            ProducerCardPrintLook.POP -> PopFront(name, sinceYear, oshiNames, handle, nameFamily, portrait, accent, seed == null)
        }
    }
}

/** 入場証 (担当色の縦の帯)。 */
@Composable
private fun PassFront(
    name: String, sinceYear: Int?, oshiNames: List<String>, handle: String?, nameFamily: FontFamily?,
    portrait: Bitmap?, accent: Color
) {
    Row(Modifier.fillMaxSize()) {
        Box(Modifier.width(30.dp).fillMaxHeight().background(accent))
        Row(
            Modifier.fillMaxSize().padding(horizontal = 30.dp, vertical = 26.dp),
            horizontalArrangement = Arrangement.spacedBy(22.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            FrontInfo(name, sinceYear, oshiNames, handle, nameFamily, Modifier.weight(1f).fillMaxHeight())
            PrintPortrait(portrait, ProducerCardPrint.sub.copy(alpha = 0.35f), 0.5.dp)
        }
    }
}

/** かしこまった名刺 (担当色は名前の上の細い罫だけ)。 */
@Composable
private fun FormalFront(
    name: String, sinceYear: Int?, oshiNames: List<String>, handle: String?, nameFamily: FontFamily?,
    portrait: Bitmap?, accent: Color
) {
    Row(
        Modifier.fillMaxSize().padding(horizontal = 40.dp, vertical = 32.dp),
        horizontalArrangement = Arrangement.spacedBy(26.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f).fillMaxHeight()) {
            Text(
                listOfNotNull("PRODUCER", sinceYear?.let { "SINCE $it" }).joinToString(" · "),
                style = ProducerCardPrint.serif(9f, FontWeight.Medium).copy(letterSpacing = 2.4.sp),
                color = ProducerCardPrint.sub
            )
            Box(Modifier.padding(top = 8.dp).fillMaxWidth().height(0.75.dp).background(accent))
            Spacer(Modifier.weight(1f))
            if (oshiNames.isNotEmpty()) {
                Text(
                    "${oshiNames.joinToString("・")} 担当",
                    style = ProducerCardPrint.serif(12f),
                    color = ProducerCardPrint.sub,
                    maxLines = 2,
                    modifier = Modifier.padding(bottom = 6.dp)
                )
            }
            ImasFitText(
                name,
                style = ProducerCardPrint.name(nameFamily, 38f).copy(letterSpacing = 2.sp),
                color = ProducerCardPrint.ink,
                maxLines = 1,
                minScale = 0.5f
            )
            Spacer(Modifier.weight(1f))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                if (handle != null) Text(handle, style = ProducerCardPrint.serif(11f), color = ProducerCardPrint.ink, maxLines = 1)
                Spacer(Modifier.weight(1f).width(8.dp))
                Text(
                    "IDOL LIVE DB",
                    style = ProducerCardPrint.serif(8f).copy(letterSpacing = 1.6.sp),
                    color = ProducerCardPrint.sub
                )
            }
        }
        PrintPortrait(portrait, ProducerCardPrint.sub.copy(alpha = 0.35f), 0.5.dp)
    }
}

/** ポップ (墨の太い枠・担当色の太い帯と名前の下の太い線)。 */
@Composable
private fun PopFront(
    name: String, sinceYear: Int?, oshiNames: List<String>, handle: String?, nameFamily: FontFamily?,
    portrait: Bitmap?, accent: Color, neutral: Boolean
) {
    Column(Modifier.fillMaxSize().border(8.dp, ProducerCardPrint.ink)) {
        Box(
            Modifier.fillMaxWidth().height(44.dp).background(accent).padding(horizontal = 22.dp),
            contentAlignment = Alignment.CenterStart
        ) {
            Text(
                listOfNotNull("PRODUCER!", sinceYear?.let { "SINCE $it" }).joinToString(" · "),
                style = ProducerCardPrint.sans(11f, FontWeight.Black).copy(letterSpacing = 1.2.sp),
                color = if (neutral) ProducerCardPrint.paper else ProducerCardPrint.ink
            )
        }
        Box(Modifier.fillMaxWidth().height(4.dp).background(ProducerCardPrint.ink))
        Row(
            Modifier.fillMaxSize().padding(horizontal = 22.dp, vertical = 18.dp),
            horizontalArrangement = Arrangement.spacedBy(20.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ImasFitText(name, style = ProducerCardPrint.name(nameFamily, 42f), color = ProducerCardPrint.ink, maxLines = 1, minScale = 0.5f)
                Box(Modifier.size(width = 84.dp, height = 9.dp).background(accent))
                if (oshiNames.isNotEmpty()) {
                    Text(
                        "${oshiNames.joinToString("・")} 担当",
                        style = ProducerCardPrint.sans(13f, FontWeight.Black),
                        color = ProducerCardPrint.ink,
                        maxLines = 2
                    )
                }
                Spacer(Modifier.weight(1f))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                    if (handle != null) Text(handle, style = ProducerCardPrint.sans(12f, FontWeight.Bold), color = ProducerCardPrint.ink, maxLines = 1)
                    Spacer(Modifier.weight(1f).width(8.dp))
                    Text(
                        "IDOL LIVE DB",
                        style = ProducerCardPrint.sans(8f, FontWeight.Black).copy(letterSpacing = 1.6.sp),
                        color = ProducerCardPrint.sub
                    )
                }
            }
            PrintPortrait(portrait, ProducerCardPrint.ink, 3.dp)
        }
    }
}

@Composable
private fun PrintPortrait(portrait: Bitmap?, border: Color, width: androidx.compose.ui.unit.Dp) {
    if (portrait == null) return
    val shape = RoundedCornerShape(3.dp)
    Image(
        bitmap = portrait.asImageBitmap(),
        contentDescription = null,
        contentScale = ContentScale.Crop,
        modifier = Modifier
            .size(width = 114.dp, height = 152.dp)
            .clip(shape)
            .border(width, border, shape)
    )
}

/**
 * 自作の名刺の画像 (表・裏) を 91:55 の紙に刷る。比率が違う画像は切らずに収め、余りは紙の色。
 * 縦の名刺 (55:91) は 90° 回して横の版面に収める (入稿の版面は横に揃える)。
 */
@Composable
fun ProducerCardPrintImage(image: Bitmap) {
    val portrait = image.height > image.width
    val bitmap = remember(image) { image.asImageBitmap() }
    val w = ProducerCardPrint.size.widthUnits.dp
    val h = ProducerCardPrint.size.heightUnits.dp
    Box(Modifier.fillMaxSize().background(ProducerCardPrint.paper), contentAlignment = Alignment.Center) {
        Image(
            bitmap = bitmap,
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier
                .requiredSize(width = if (portrait) h else w, height = if (portrait) w else h)
                .rotate(if (portrait) -90f else 0f)
        )
    }
}

@Composable
private fun FrontInfo(
    name: String,
    sinceYear: Int?,
    oshiNames: List<String>,
    handle: String?,
    nameFamily: FontFamily?,
    modifier: Modifier
) {
    Column(modifier) {
        Text(
            listOfNotNull("PRODUCER PASS", sinceYear?.let { "SINCE $it" }).joinToString(" · "),
            style = ProducerCardPrint.mono(9f, tracking = 1.6f),
            color = ProducerCardPrint.sub
        )
        Spacer(Modifier.weight(1f))
        ImasFitText(
            name,
            style = ProducerCardPrint.name(nameFamily, 40f),
            color = ProducerCardPrint.ink,
            maxLines = 1,
            minScale = 0.5f
        )
        if (oshiNames.isNotEmpty()) {
            Text(
                "${oshiNames.joinToString("・")} 担当",
                style = ProducerCardPrint.serif(13f),
                color = ProducerCardPrint.ink,
                maxLines = 2,
                modifier = Modifier.padding(top = 8.dp)
            )
        }
        Spacer(Modifier.weight(1f))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
            if (handle != null) {
                Text(handle, style = ProducerCardPrint.mono(12f), color = ProducerCardPrint.ink, maxLines = 1)
            }
            Spacer(Modifier.weight(1f).width(8.dp))
            Text("IDOL LIVE DB", style = ProducerCardPrint.mono(8f, tracking = 1.6f), color = ProducerCardPrint.sub)
        }
    }
}

/** 裏。 */
@Composable
fun ProducerCardPrintBack(
    /** QR にする中身 (交換用の名刺の URL か、自分の QR の URL)。 */
    url: String,
    /** QR の横に刷る案内。 */
    note: String = "読み取るとアプリの名刺入れに入ります。アプリが無ければ Web で開きます。",
    showCount: Long? = null,
    songCount: Long? = null,
    /** 「2026.10.06 時点」(コアの `cardIssuedLabel`)。 */
    issuedLabel: String
) {
    val matrix = remember(url) { imasQrMatrix(url) }
    Row(
        Modifier.fillMaxSize().background(ProducerCardPrint.paper).padding(horizontal = 30.dp, vertical = 40.dp),
        horizontalArrangement = Arrangement.spacedBy(26.dp)
    ) {
        Canvas(Modifier.size(250.dp)) { if (matrix != null) drawQr(matrix, ProducerCardPrint.ink) }
        Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            showCount?.let { Metric("$it", "参加公演") }
            songCount?.let { Metric("$it", "回収曲") }
            Spacer(Modifier.weight(1f))
            Text(
                note,
                style = ProducerCardPrint.sans(9f),
                color = ProducerCardPrint.sub
            )
            Text(issuedLabel, style = ProducerCardPrint.mono(9f), color = ProducerCardPrint.sub)
        }
    }
}

@Composable
private fun Metric(value: String, label: String) {
    Column {
        Text(value, style = ProducerCardPrint.sans(34f, FontWeight.Black), color = ProducerCardPrint.ink, maxLines = 1)
        Text(label, style = ProducerCardPrint.sans(10f, FontWeight.SemiBold), color = ProducerCardPrint.sub)
    }
}

/** 実寸のカードを親の幅に合わせて縮めて見せる (影は付けず、細い線で縁取る)。焼くのは [capture]。 */
@Composable
fun ProducerCardPrintPreview(capture: ShareCardCapture, card: @Composable () -> Unit) {
    val shape = RoundedCornerShape(DS.rInner)
    ShareCardCanvas(
        size = ProducerCardPrint.size,
        capture = capture,
        scale = ProducerCardPrint.RENDER_SCALE,
        modifier = Modifier.clip(shape).border(1.dp, DS.line, shape),
        card = card
    )
}
