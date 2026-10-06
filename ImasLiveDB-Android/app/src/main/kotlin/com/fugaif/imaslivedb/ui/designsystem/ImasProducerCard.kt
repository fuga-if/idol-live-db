package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.stateDescription
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.SubcomposeAsyncImage
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.cardName
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.common.BitMatrix
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

// =============================================================================
// P名刺 (docs/DESIGN_SYSTEM.md §6.13)。iOS `ImasProducerCard.swift` の移植。
//
// ImasProducerCard   P名刺 1 枚。デザイン (`design`) は 3 つと自作の画像 (一覧・既定・書体はコアの `cardDesigns`)。
//                    並べる要素は同じ: 担当の写真、名前 (デザインの書体で大きく)、ひとこと、担当の行、
//                    リンクの行、記録の電光掲示板 (`ImasBoard`)。
//                    - 入場証 (Pass): 担当の入場証 (`ImasPass`) を 1 枚に広げた紙。上の帯が担当の色で
//                      ストラップの穴、区切りは切り取り線。
//                    - かしこまった名刺 (Formal): 角の小さい紙に細い枠。担当色は名前の上の細い罫と判子だけ、
//                      区切りは細い罫、担当の写真は名前の下に枠に入れて小さく。明朝。
//                    - ポップ (Pop): 墨の太い枠と太い区切り、担当色の太い帯と名前の下の太い線。ポップ体。
//                    - 自作の画像 (Face): 帯と名前の面の代わりに自分で作った名刺の画像 (`ImasCardFace`)。
//                      下に担当・リンク・掲示板。画像が手元に無い名刺は入場証で描く (コアが決める)。
//                    使わない場面: アイドル 1 人の顔 → `ImasIdolHeader` / 担当の入口 → `ImasPass`。
//                    種類: 担当の写真がある / 無い (写真の面を出さない。担当の行の判子は必ず出す)。
//                          名刺の写真がある (名前の横に証明写真の枠) / 無い (枠を出さない)。
//                    状態: リンク・担当は押すと開く (`onOpenLink` / `onOpenOshi`)。渡さなければ押せない。
// ImasCardFace       自作の名刺の画像 (表・任意で裏)。比率は画像のまま切らずに収め、押すと裏に返す。
//                    `thumbnail` は 91:55 の枠に収めた小さな見本 (名刺入れの行・デザインの札)。
// ImasCardPortrait   名刺の写真の証明写真の枠 (3:4)。名刺・名刺入れの行・編集画面で同じ枠。
// ImasPortraitCropper 名刺の写真を枠に合わせて指で動かす・広げる (切り抜きの位置と拡大)。
// ImasCardDesignPicker 名刺のデザインの見本 (小さな名刺) を横に並べ、引いて (または押して) 選ぶ。
// ImasCornerAdjuster 写真に写った紙の名刺の四隅を指で直す (書類カメラの手直しと同じ感覚)。
// ImasCameraFrame    カメラの読み取り窓。面と同じ角丸で切り、縦長 (3:4) に収める。中身はカメラの View。
// ImasQRCode         QR。チケットの紙 (ダークでも明るい) に墨で刷る。誤り訂正は L (中身が長いので
//                    読み取りやすさより収まりを取る)。題 (`caption`) を下に添えられる。
// =============================================================================

/** 名刺のデザイン (iOS `ImasProducerCard.Design`)。並べる要素は同じで、組みと線と書体が変わる。 */
@Immutable
sealed interface ImasProducerCardDesign {
    /** 入場証。担当色の帯・ストラップの穴・切り取り線。 */
    data object Pass : ImasProducerCardDesign

    /** かしこまった名刺。紙のまま、担当色は名前の上の細い罫と判子だけ、区切りは細い罫。 */
    data object Formal : ImasProducerCardDesign

    /** ポップ。墨の太い枠と太い区切り、担当色の太い帯と名前の下の太い線。 */
    data object Pop : ImasProducerCardDesign

    /** 自作の画像。帯・名前の面の代わりに、自分で作った名刺の画像 (押すと裏) を出す。 */
    data class Face(val front: String, val back: String? = null) : ImasProducerCardDesign
}

/** 名刺に載せる担当 1 人 (iOS `ImasProducerCard.Oshi`)。 */
@Immutable
data class ImasProducerCardOshi(
    val id: String,
    val name: String,
    /** 判子の略称。 */
    val shortName: String,
    val seed: String? = null,
    /** ブランド ID。 */
    val brand: String? = null,
    /** 写真の在り処。null なら [entityId] で端末に取り込んだ写真を引く (無ければ判子)。 */
    val imageUrl: String? = null,
    /** 端末に取り込んだ写真を引く id (自分の名刺)。受け取った名刺は null (相手の画像は [imageUrl])。 */
    val entityId: String? = null,
    /** 副題 (ブランド・CV)。 */
    val subtitle: String? = null,
    /** 見ている人と同じ担当 (受け取った名刺で「担当被り」を出す)。 */
    val isShared: Boolean = false
)

/** 名刺に載せるリンク 1 本 (iOS `ImasProducerCard.Link`)。 */
@Immutable
data class ImasProducerCardLink(
    /** 種類の名前 (X・Bluesky…)。 */
    val label: String,
    /** 右に出す値 (@handle)。 */
    val display: String,
    val url: String
)

/**
 * P名刺 1 枚 (iOS `ImasProducerCard`)。
 *
 * @param design 名刺のデザイン (一覧・既定・書体はコアの `cardDesigns`)。
 * @param sinceImprint 帯の右の印字 (「SINCE 2014」)。
 * @param cells 記録の数 (参加公演・回収曲・次の現場)。空なら掲示板を出さない。
 * @param boardTrailing 掲示板の右上の印字 (「2014 — 2026」)。
 * @param photoUrl 担当の写真 (入場証は帯の下に大きく、かしこまった名刺は名前の下に枠に入れて、ポップは帯の下に太い線で)。
 * @param photoEntityId 写真を端末に取り込んだ担当の id から引く (自分の名刺)。
 * @param portraitUrl 名刺の写真 (自分で選んだ写真。名前の横の証明写真の枠に出す)。
 * @param nameFamily 名前の書体 (コアの `CardDesignInfo.font` を [com.fugaif.imaslivedb.ui.theme.rememberCardNameFamily] で引いたもの)。null は見出しの書体。
 */
@Composable
fun ImasProducerCard(
    name: String,
    modifier: Modifier = Modifier,
    design: ImasProducerCardDesign = ImasProducerCardDesign.Pass,
    sinceImprint: String? = null,
    message: String? = null,
    oshi: List<ImasProducerCardOshi> = emptyList(),
    links: List<ImasProducerCardLink> = emptyList(),
    cells: List<ImasBoardCell> = emptyList(),
    boardTrailing: String? = null,
    photoUrl: String? = null,
    photoEntityId: String? = null,
    portraitUrl: String? = null,
    nameFamily: FontFamily? = null,
    onOpenLink: ((ImasProducerCardLink) -> Unit)? = null,
    onOpenOshi: ((ImasProducerCardOshi) -> Unit)? = null
) {
    val lead = oshi.firstOrNull()
    val t = imasThemeForBrand(lead?.seed, lead?.brand)
    val parts = ProducerCardParts(
        name = name, message = message, oshi = oshi, links = links, cells = cells, boardTrailing = boardTrailing,
        photo = rememberCustomImage(photoEntityId) ?: photoUrl,
        photoLabel = lead?.let { "${it.name}の写真" } ?: "担当の写真",
        portraitUrl = portraitUrl, nameFamily = nameFamily, onOpenLink = onOpenLink, onOpenOshi = onOpenOshi,
        band = if (t.isNeutral) DS.sys else t.accent,
        onBand = if (t.isNeutral) DS.onSys else t.onAccent,
        rule = if (t.isNeutral) DS.ink else t.accent
    )
    when (design) {
        ImasProducerCardDesign.Pass -> PassCard(parts, sinceImprint, modifier)
        ImasProducerCardDesign.Formal -> FormalCard(parts, sinceImprint, modifier)
        ImasProducerCardDesign.Pop -> PopCard(parts, sinceImprint, modifier)
        is ImasProducerCardDesign.Face -> FaceCard(parts, design, modifier)
    }
}

/** デザインをまたいで同じ、名刺に並べるもの。 */
private class ProducerCardParts(
    val name: String,
    val message: String?,
    val oshi: List<ImasProducerCardOshi>,
    val links: List<ImasProducerCardLink>,
    val cells: List<ImasBoardCell>,
    val boardTrailing: String?,
    val photo: Any?,
    val photoLabel: String,
    val portraitUrl: String?,
    val nameFamily: FontFamily?,
    val onOpenLink: ((ImasProducerCardLink) -> Unit)?,
    val onOpenOshi: ((ImasProducerCardOshi) -> Unit)?,
    /** 帯の色 (担当がいなければ墨)。 */
    val band: Color,
    val onBand: Color,
    /** かしこまった名刺の罫の色 (担当がいなければ墨)。 */
    val rule: Color
)

/** ポップの太い線。 */
private val PopLine = 3.dp

// MARK: 入場証

@Composable
private fun PassCard(p: ProducerCardParts, sinceImprint: String?, modifier: Modifier) {
    val shape = RoundedCornerShape(DS.rCard)
    Column(modifier.fillMaxWidth().imasSurface(shape).clip(shape)) {
        Box(
            Modifier.fillMaxWidth().height(44.dp).background(p.band),
            contentAlignment = Alignment.Center
        ) {
            ImprintRow("PRODUCER PASS", sinceImprint, p.onBand.copy(alpha = 0.9f))
            // ストラップを通す穴 (地の色を透かす)。
            Box(
                Modifier
                    .size(width = 44.dp, height = 10.dp)
                    .background(DS.bg, CircleShape)
                    .border(1.dp, DS.line, CircleShape)
                    .clearAndSetSemantics { }
            )
        }
        if (p.photo != null) OshiPhoto(p, Modifier.fillMaxWidth().height(scaled(220f)))
        NameBlock(p, 28f)
        CardRows(p) { ImasPerforation(Modifier.padding(horizontal = DS.Space.card)) }
        CardBoard(p)
    }
}

// MARK: かしこまった名刺

@Composable
private fun FormalCard(p: ProducerCardParts, sinceImprint: String?, modifier: Modifier) {
    val shape = RoundedCornerShape(DS.rTag)
    Column(modifier.fillMaxWidth().background(DS.surface, shape).clip(shape).border(1.dp, DS.line, shape)) {
        Box(Modifier.padding(top = DS.Space.card)) { ImprintRow("PRODUCER", sinceImprint, DS.ink2) }
        Box(
            Modifier
                .padding(horizontal = DS.Space.card)
                .padding(top = DS.Space.gapTight)
                .fillMaxWidth()
                .height(1.dp)
                .background(p.rule)
                .clearAndSetSemantics { }
        )
        NameBlock(p, 28f)
        if (p.photo != null) {
            val photoShape = RoundedCornerShape(DS.rTag)
            OshiPhoto(
                p,
                Modifier
                    .padding(horizontal = DS.Space.card)
                    .padding(bottom = DS.Space.gapLoose)
                    .fillMaxWidth()
                    .height(scaled(220f * 0.72f))
                    .clip(photoShape)
                    .border(1.dp, DS.line, photoShape)
            )
        }
        CardRows(p) {
            Box(Modifier.padding(horizontal = DS.Space.card).fillMaxWidth().height(1.dp).background(DS.line))
        }
        CardBoard(p)
    }
}

// MARK: ポップ

@Composable
private fun PopCard(p: ProducerCardParts, sinceImprint: String?, modifier: Modifier) {
    val shape = RoundedCornerShape(DS.rCard)
    Column(modifier.fillMaxWidth().background(DS.surface, shape).clip(shape).border(PopLine, DS.ink, shape)) {
        Box(Modifier.fillMaxWidth().height(52.dp).background(p.band), contentAlignment = Alignment.Center) {
            ImprintRow("PRODUCER!", sinceImprint, p.onBand)
        }
        InkLine(PopLine)
        if (p.photo != null) {
            OshiPhoto(p, Modifier.fillMaxWidth().height(scaled(220f)))
            InkLine(PopLine)
        }
        Row(
            Modifier.padding(horizontal = DS.Space.card, vertical = DS.Space.gapLoose),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
            verticalAlignment = Alignment.Top
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                ImasFitText(p.name, style = ImasType.cardName(p.nameFamily, 30.sp), color = DS.ink, maxLines = 2, minScale = 0.6f)
                Box(Modifier.size(width = 64.dp, height = 8.dp).background(p.band).clearAndSetSemantics { })
                MessageText(p.message)
            }
            if (p.portraitUrl != null) {
                val portraitShape = RoundedCornerShape(DS.rTag)
                ImasCardPortrait(
                    url = p.portraitUrl, label = "${p.name}の写真",
                    modifier = Modifier.width(scaled(84f)).border(2.dp, DS.ink, portraitShape)
                )
            }
        }
        CardRows(p) { InkLine(2.dp) }
        CardBoard(p)
    }
}

// MARK: 自作の画像

@Composable
private fun FaceCard(p: ProducerCardParts, face: ImasProducerCardDesign.Face, modifier: Modifier) {
    val shape = RoundedCornerShape(DS.rCard)
    Column(modifier.fillMaxWidth().imasSurface(shape).clip(shape)) {
        ImasCardFace(front = face.front, back = face.back, label = "${p.name}の名刺", modifier = Modifier.padding(DS.Space.gapLoose))
        if (!p.message.isNullOrEmpty()) {
            Box(Modifier.padding(horizontal = DS.Space.card).padding(bottom = DS.Space.gapLoose)) { MessageText(p.message) }
        }
        CardRows(p) { ImasPerforation(Modifier.padding(horizontal = DS.Space.card)) }
        CardBoard(p)
    }
}

// MARK: 共通の部品

/** iOS の @ScaledMetric(relativeTo: .body)。文字の大きさに合わせて広げる。 */
@Composable
private fun scaled(value: Float) = with(LocalDensity.current) { value.sp.toDp() }

@Composable
private fun ImprintRow(leading: String, trailing: String?, color: Color) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = DS.Space.card),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(leading, style = ImasTextRole.IMPRINT.style, color = color, maxLines = 1)
        Spacer(Modifier.weight(1f).widthIn(min = 60.dp))
        if (trailing != null) Text(trailing, style = ImasTextRole.IMPRINT.style, color = color, maxLines = 1)
    }
}

@Composable
private fun InkLine(height: androidx.compose.ui.unit.Dp) {
    Box(Modifier.fillMaxWidth().height(height).background(DS.ink).clearAndSetSemantics { })
}

@Composable
private fun OshiPhoto(p: ProducerCardParts, modifier: Modifier) {
    SubcomposeAsyncImage(
        model = p.photo,
        contentDescription = p.photoLabel,
        contentScale = ContentScale.Crop,
        modifier = modifier,
        loading = { Box(Modifier.fillMaxSize().background(DS.surface2)) },
        error = { Box(Modifier.fillMaxSize().background(DS.surface2)) }
    )
}

@Composable
private fun MessageText(message: String?) {
    if (!message.isNullOrEmpty()) Text(message, style = ImasTextRole.NOTE.style, color = DS.ink2)
}

/** 名前・ひとこと・名刺の写真 (入場証とかしこまった名刺)。 */
@Composable
private fun NameBlock(p: ProducerCardParts, size: Float) {
    Row(
        Modifier.padding(horizontal = DS.Space.card, vertical = DS.Space.gapLoose),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
        verticalAlignment = Alignment.Top
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
            ImasFitText(p.name, style = ImasType.cardName(p.nameFamily, size.sp), color = DS.ink, maxLines = 2, minScale = 0.6f)
            MessageText(p.message)
        }
        if (p.portraitUrl != null) {
            ImasCardPortrait(url = p.portraitUrl, label = "${p.name}の写真", modifier = Modifier.width(scaled(84f)))
        }
    }
}

/** 担当の行・リンクの行。区切りはデザインごとの線。 */
@Composable
private fun CardRows(p: ProducerCardParts, separator: @Composable () -> Unit) {
    if (p.oshi.isNotEmpty()) {
        separator()
        Column {
            p.oshi.forEachIndexed { index, item ->
                ImasRow(
                    title = item.name,
                    subtitle = item.subtitle,
                    leading = ImasRowLeading.Avatar(
                        label = item.shortName, seed = item.seed, brand = item.brand,
                        imageUrl = item.imageUrl, isPick = true, entityId = item.entityId
                    ),
                    trailing = if (item.isShared) {
                        ImasRowTrailing.Badge("担当被り", ImasBadgeKind.NEW)
                    } else {
                        ImasRowTrailing.Badge("担当", ImasBadgeKind.LEAD)
                    },
                    density = ImasRowDensity.COMPACT,
                    position = if (index == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING,
                    modifier = p.onOpenOshi?.let { open -> Modifier.imasRowPress(onClick = { open(item) }) } ?: Modifier
                )
            }
        }
    }
    if (p.links.isNotEmpty()) {
        separator()
        Column {
            p.links.forEachIndexed { index, link ->
                ImasValueRow(
                    key = link.label,
                    value = link.display,
                    isLink = p.onOpenLink != null,
                    position = if (index == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING,
                    onClick = p.onOpenLink?.let { open -> { open(link) } }
                )
            }
        }
    }
}

@Composable
private fun CardBoard(p: ProducerCardParts) {
    if (p.cells.isNotEmpty()) {
        ImasBoard(cells = p.cells, title = "RECORD", trailing = p.boardTrailing, modifier = Modifier.padding(DS.Space.gapLoose))
    }
}

// MARK: - 自作の名刺の画像

/** 日本の名刺の比 (91:55)。読み込む前の枠と小さな見本の枠。 */
const val ImasCardFaceAspect = 91f / 55f

/**
 * 自分で作った名刺の画像 (表・任意で裏)。iOS `ImasCardFace`。比率は画像のまま (91:55 でなくても切らずに収める)。
 * 裏があれば押すと返して裏を見せる (y 軸で返す)。名刺入れの行の先頭・デザインの札は [thumbnail] (91:55 の枠に収める)。
 */
@Composable
fun ImasCardFace(
    front: String,
    modifier: Modifier = Modifier,
    back: String? = null,
    label: String = "名刺の画像",
    /** 行の先頭の小さな見本 (91:55 の枠に収め、返さない)。 */
    thumbnail: Boolean = false
) {
    val shape = RoundedCornerShape(DS.rTag)
    if (thumbnail) {
        Box(
            modifier
                .fillMaxWidth()
                .aspectRatio(ImasCardFaceAspect)
                .imasSurfaceEdge(shape, fill = DS.surface2)
                .clip(shape)
                .semantics { contentDescription = label }
        ) {
            SubcomposeAsyncImage(
                model = front, contentDescription = null, contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize(),
                loading = { Box(Modifier.fillMaxSize().background(DS.surface2)) },
                error = { Box(Modifier.fillMaxSize().background(DS.surface2)) }
            )
        }
        return
    }
    var flipped by remember(front, back) { mutableStateOf(false) }
    // 裏を外したら表に戻す (返したまま裏が無くなると何も見えなくなる)。
    val showingBack = flipped && back != null
    val haptics = rememberImasHaptics()
    val angle by animateFloatAsState(if (showingBack) 180f else 0f, label = "card_face_flip")
    val density = LocalDensity.current.density
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        Box(
            Modifier
                .fillMaxWidth()
                .graphicsLayer {
                    rotationY = angle
                    cameraDistance = 12f * density
                }
                .then(
                    if (back != null) {
                        Modifier.imasRowPress(onClick = {
                            haptics.selection()
                            flipped = !showingBack
                        })
                    } else Modifier
                )
                .clearAndSetSemantics {
                    contentDescription = if (showingBack) "${label}の裏" else label
                    if (back != null) stateDescription = if (showingBack) "押すと表を見せます" else "押すと裏を見せます"
                }
        ) {
            if (angle <= 90f || back == null) {
                CardFaceSide(front, shape)
            } else {
                CardFaceSide(back, shape, Modifier.graphicsLayer { rotationY = 180f })
            }
        }
        if (back != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), modifier = Modifier.clearAndSetSemantics { }) {
                Text("表", style = ImasTextRole.IMPRINT.style, color = if (showingBack) DS.ink3 else DS.ink)
                Text("裏", style = ImasTextRole.IMPRINT.style, color = if (showingBack) DS.ink else DS.ink3)
            }
        }
    }
}

/** 名刺の画像の 1 面 (画像の比のまま幅いっぱいに収める。読み込む前は 91:55 の枠)。 */
@Composable
private fun CardFaceSide(url: String, shape: RoundedCornerShape, modifier: Modifier = Modifier) {
    SubcomposeAsyncImage(
        model = url,
        contentDescription = null,
        modifier = modifier.fillMaxWidth().imasSurfaceEdge(shape, fill = DS.surface2).clip(shape),
        loading = { Box(Modifier.fillMaxWidth().aspectRatio(ImasCardFaceAspect).background(DS.surface2)) },
        error = { Box(Modifier.fillMaxWidth().aspectRatio(ImasCardFaceAspect).background(DS.surface2)) },
        success = { state ->
            val size = state.painter.intrinsicSize
            val aspect = if (size.width > 0f && size.height > 0f) size.width / size.height else ImasCardFaceAspect
            Image(
                painter = state.painter, contentDescription = null, contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxWidth().aspectRatio(aspect)
            )
        }
    )
}
// MARK: - QR

/**
 * QR (iOS `ImasQRCode`)。チケットの紙 (ダークでも明るい) に墨で刷るので、どの端末のカメラでも読める。
 * 誤り訂正は L。下に題 ([caption])。
 */
@Composable
fun ImasQRCode(
    text: String,
    modifier: Modifier = Modifier,
    caption: String? = null,
    /** 読み上げの名前 (「名刺の QR コード」「自分の QR コード」)。 */
    label: String = "名刺の QR コード"
) {
    val matrix = remember(text) { imasQrMatrix(text) }
    val shape = RoundedCornerShape(DS.rCard)
    val ink = DS.ticketInk
    Column(
        modifier
            .fillMaxWidth()
            .imasSurface(shape, color = DS.ticket)
            .padding(DS.Space.section),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
    ) {
        Canvas(
            Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .semantics { contentDescription = label }
        ) {
            if (matrix != null) drawQr(matrix, ink)
        }
        if (caption != null) {
            Text(
                caption,
                style = ImasType.text(13.sp, FontWeight.SemiBold),
                color = DS.ticketSub,
                textAlign = TextAlign.Center
            )
        }
    }
}

/** QR の模様 (誤り訂正 L・余白なし)。組めなければ null。紙に刷る画像も同じ模様を使う。 */
fun imasQrMatrix(text: String): BitMatrix? = runCatching {
    QRCodeWriter().encode(
        text, BarcodeFormat.QR_CODE, 0, 0,
        mapOf(
            EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.L,
            EncodeHintType.CHARACTER_SET to "UTF-8",
            EncodeHintType.MARGIN to 0
        )
    )
}.getOrNull()

/** QR の模様を描く面いっぱいに墨で描く (模様の所だけ塗る)。 */
fun DrawScope.drawQr(matrix: BitMatrix, ink: Color) {
    val cells = matrix.width
    if (cells == 0) return
    val cell = minOf(size.width, size.height) / cells
    val origin = Offset((size.width - cell * cells) / 2f, (size.height - cell * cells) / 2f)
    val cellSize = Size(cell, cell)
    for (y in 0 until cells) {
        for (x in 0 until cells) {
            if (matrix[x, y]) {
                // 隣のマスと隙間が出ないよう、わずかに重ねて塗る。
                drawRect(ink, Offset(origin.x + x * cell, origin.y + y * cell), cellSize.copy(cell + 0.5f, cell + 0.5f))
            }
        }
    }
}

// MARK: - カメラの窓

/** カメラの読み取り窓 (iOS `ImasCameraFrame`)。面と同じ角丸で切り、縦長 (3:4) に収める。 */
@Composable
fun ImasCameraFrame(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val shape = RoundedCornerShape(DS.rCard)
    Box(
        modifier
            .fillMaxWidth()
            .aspectRatio(3f / 4f)
            .imasSurfaceEdge(shape, fill = DS.board)
            .background(DS.board, shape)
            .clip(shape)
            .semantics { contentDescription = "カメラ" },
        content = content
    )
}
