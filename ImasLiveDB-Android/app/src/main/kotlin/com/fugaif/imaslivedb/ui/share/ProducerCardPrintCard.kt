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
// 表 = 担当色の縦の帯・選んだ書体の名前・担当・ハンドル・名刺の写真 (あれば右に証明写真)。
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

/** 表。 */
@Composable
fun ProducerCardPrintFront(
    name: String,
    sinceYear: Int? = null,
    /** 担当の名前 (「天海春香・如月千早」)。 */
    oshiNames: List<String> = emptyList(),
    /** 担当の色 (帯)。 */
    seed: String? = null,
    /** 右下に刷るハンドル (「@fuga_p」)。 */
    handle: String? = null,
    /** 名前の書体 (コアの書体の一覧から引いたもの)。 */
    nameFamily: FontFamily? = null,
    /** 名刺の写真 (右に証明写真の大きさで刷る)。 */
    portrait: Bitmap? = null
) {
    val palette = rememberShareCardPalette(seed)
    Row(Modifier.fillMaxSize().background(ProducerCardPrint.paper)) {
        Box(
            Modifier
                .width(30.dp)
                .fillMaxHeight()
                .background(if (seed == null) ProducerCardPrint.ink else palette.accent)
        )
        Row(
            Modifier.fillMaxSize().padding(horizontal = 30.dp, vertical = 26.dp),
            horizontalArrangement = Arrangement.spacedBy(22.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            FrontInfo(name, sinceYear, oshiNames, handle, nameFamily, Modifier.weight(1f).fillMaxHeight())
            if (portrait != null) {
                val shape = RoundedCornerShape(3.dp)
                Image(
                    bitmap = portrait.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(width = 114.dp, height = 152.dp)
                        .clip(shape)
                        .border(0.5.dp, ProducerCardPrint.sub.copy(alpha = 0.35f), shape)
                )
            }
        }
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
