package com.fugaif.imaslivedb.ui.share

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.designsystem.ImasMeishi
import com.fugaif.imaslivedb.ui.designsystem.ImasMeishiBack
import com.fugaif.imaslivedb.ui.designsystem.ImasMeishiFront
import com.fugaif.imaslivedb.ui.designsystem.ImasMeishiInk
import com.fugaif.imaslivedb.ui.designsystem.ImasMeishiLook
import com.fugaif.imaslivedb.ui.designsystem.ImasMeishiOshi
import com.fugaif.imaslivedb.ui.designsystem.ImasMeishiOshiGroup
import com.fugaif.imaslivedb.ui.designsystem.ImasMeishiPicture
import com.fugaif.imaslivedb.ui.designsystem.imasQrMatrix
import com.fugaif.imaslivedb.ui.theme.DS

// =============================================================================
// 紙に刷る P名刺 (91×55mm、日本の名刺の大きさ)。iOS `ProducerCardPrintCard.swift` の移植。
//
// 表・裏の組みは画面の P名刺と同じ部品 (`ImasMeishiFront` / `ImasMeishiBack`、docs/DESIGN_SYSTEM.md §6.13)。
// 違うのは色 (固定色の紙と墨) と画像の渡し方だけ: 焼くのは今描かれているものだけで画像の読み込みを待たないので、
// 担当の写真・名刺の写真は書き出す前に Bitmap に読んでから渡す (URL を渡すと焼かれない)。
// 表 = デザインごとの組み。名前・P歴・担当 (写真か判子、ブランドごとにまとめ、多いときは数で畳む)・ハンドル・名刺の写真。
//      自作の画像の名刺は、その画像をそのまま刷る (`ProducerCardPrintImage`)。
// 裏 = QR (既定はアプリの交換と同じ中身。自分の QR も選べる)・参加公演数と回収曲数・「YYYY.MM.DD 時点」。
// =============================================================================

object ProducerCardPrint {
    /** 紙の寸法の倍率。91:55 の紙 (364×220) を 1.5 倍の 546×330 で組み、3 倍で焼いて 1638×990px (350dpi 相当)。 */
    const val PAPER_SCALE = 1.5f
    val size = ShareCardSize((ImasMeishi.WIDTH * PAPER_SCALE).toInt(), (ImasMeishi.HEIGHT * PAPER_SCALE).toInt())
    const val RENDER_SCALE = 3f

    val ink = ShareInk.nearBlack
    val paper = ShareInk.offWhite
    val sub = Color(0xFF5A5755)

    /** 紙と墨 (固定色)。担当の色は帯・罫・判子の縁だけ。 */
    @Composable
    fun colors(seed: String?): ImasMeishiInk {
        val accent = rememberShareCardPalette(seed).accent
        return ImasMeishiInk(
            paper = paper, ink = ink, sub = sub, line = sub.copy(alpha = 0.35f),
            accent = if (seed == null) ink else accent,
            onAccent = if (seed == null) paper else ink
        )
    }
}

/** 紙に刷る担当 1 人 (写真は読み込み済みのものだけ)。 */
data class ProducerCardPrintOshi(
    val id: String,
    val name: String,
    val shortName: String,
    val seed: String? = null,
    val image: Bitmap? = null
)

/** 紙に刷る担当のブランドごとのまとまり (コアの `CardFaceOshiGroup`)。 */
data class ProducerCardPrintOshiGroup(val label: String, val oshi: List<ProducerCardPrintOshi>)

/** 表。デザイン (入場証・かしこまった名刺・ポップ) ごとに組みを変える。載せるものは画面の名刺と同じ。 */
@Composable
fun ProducerCardPrintFront(
    name: String,
    look: ImasMeishiLook = ImasMeishiLook.PASS,
    /** 「SINCE 2014」(コアの `CardFace.sinceImprint`)。 */
    sinceImprint: String? = null,
    /** 表に並べる担当のまとまり (コアの `CardFace.oshiGroups` の順)。 */
    groups: List<ProducerCardPrintOshiGroup> = emptyList(),
    /** 判子の下の 1 行 (コアの `CardFace.oshiCaption`)。 */
    caption: String? = null,
    moreOshi: Int = 0,
    /** 担当の色 (帯・罫)。先頭の担当の色。 */
    seed: String? = null,
    /** 右下に刷るハンドル (「@fuga_p」)。 */
    handle: String? = null,
    /** 名前の書体 (コアのデザインの書体から引いたもの)。 */
    nameFamily: FontFamily? = null,
    /** 名刺の写真 (右に正方形の枠で刷る)。 */
    portrait: Bitmap? = null,
    /** 名刺の写真を丸く切る (X のアイコン)。 */
    portraitRound: Boolean = false
) {
    val colors = ProducerCardPrint.colors(seed)
    ImasMeishiFront(
        name = name, ink = colors, look = look, sinceImprint = sinceImprint,
        oshiGroups = groups.map { group ->
            ImasMeishiOshiGroup(group.label, group.oshi.map {
                ImasMeishiOshi(
                    id = it.id, name = it.name, shortName = it.shortName,
                    color = stampColor(it.seed),
                    picture = it.image?.let { image -> ImasMeishiPicture.Image(image) }
                )
            })
        },
        oshiCaption = caption, moreOshi = moreOshi, handle = handle, nameFamily = nameFamily,
        portrait = portrait?.let { ImasMeishiPicture.Image(it) },
        portraitRound = portraitRound,
        scale = ProducerCardPrint.PAPER_SCALE
    )
}

/** 担当の判子の色。 */
@Composable
private fun stampColor(seed: String?): Color =
    if (seed == null) ProducerCardPrint.ink else rememberShareCardPalette(seed).accent

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

/** 裏。 */
@Composable
fun ProducerCardPrintBack(
    /** QR にする中身 (交換用の名刺の URL か、自分の QR の URL)。 */
    url: String,
    /** QR の横に刷る案内。 */
    note: String = "読み取るとアプリの名刺入れに入ります。アプリが無ければ Web で開きます。",
    showCount: Long? = null,
    songCount: Long? = null,
    /** 「2026.10.06 時点」(コアの `CardFace.issuedLabel`)。 */
    issuedLabel: String
) {
    val matrix = remember(url) { imasQrMatrix(url) }
    ImasMeishiBack(
        qr = matrix, note = note, issuedLabel = issuedLabel, ink = ProducerCardPrint.colors(null),
        showCount = showCount, songCount = songCount, scale = ProducerCardPrint.PAPER_SCALE
    )
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
