package com.fugaif.imaslivedb.ui.designsystem

import android.net.Uri
import android.provider.Settings
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.common.BitMatrix
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

// =============================================================================
// P名刺 (docs/DESIGN_SYSTEM.md §6.13)。iOS `ImasProducerCard.swift` の移植。
//
// ImasProducerCard   P名刺 1 枚。名刺そのものは 91:55 の横長の紙 1 枚 (紙に刷る画像の表・裏と同じ組み、
//                    `ImasMeishiFront` / `ImasMeishiBack`)。押すと裏返って裏 (QR・参加公演数・回収曲数・日付)。
//                    デザイン (`design`) は 3 つと自作の画像 (一覧・既定・書体はコアの `cardDesigns`)。
//                    表に載せるのは名前・P歴・名刺の写真・担当 (判子か写真、ブランドごとにまとめ、多いときは数で畳む)・
//                    ハンドル 1 つ (載せる担当とハンドルはコアの `producerCardFace`)。
//                    - 自作の画像 (Face): 表は自分で作った名刺の画像。裏は裏の画像 (無ければ QR の裏)。
//                      画像が手元に無い名刺は入場証で描く (コアが決める)。
//                    名刺に収まらないもの (ひとこと・担当の一覧・リンクの一覧・記録の掲示板) は
//                    `ImasProducerCardDetails` で名刺の下の紙面に並べる。
//                    使わない場面: アイドル 1 人の顔 → `ImasIdolHeader` / 担当の入口 → `ImasPass`。
//                    状態: 裏返せる (`isFlippable`、編集画面の固定の見本は返さない)。リンク・担当は
//                          `onOpenLink` / `onOpenOshi` を渡すと詳細の行が押せる。
// ImasProducerCardDetails 名刺の下の紙面 (ひとこと・担当の写真と一覧・リンクの一覧・記録の掲示板)。
// ImasCardFace       自作の名刺の画像の小さな見本 (91:55 の枠に収める。名刺入れの行・デザインの札・編集画面)。
// ImasCardPortrait   名刺の写真の証明写真の枠 (3:4)。名刺入れの行・編集画面で同じ枠。
// ImasPortraitCropper 名刺の写真を枠に合わせて指で動かす・広げる (切り抜きの位置と拡大)。
// ImasCardDesignPicker 名刺のデザインの見本 (小さな名刺) を横に並べ、引いて (または押して) 選ぶ。
// ImasCornerAdjuster 写真に写った紙の名刺の四隅を指で直す (書類カメラの手直しと同じ感覚)。
// ImasCameraFrame    カメラの読み取り窓。面と同じ角丸で切り、縦長 (3:4) に収める。中身はカメラの View。
// ImasQRCode         QR。チケットの紙 (ダークでも明るい) に墨で刷る。誤り訂正は L (中身が長いので
//                    読み取りやすさより収まりを取る)。題 (`caption`) を下に添えられる。
// =============================================================================

/** 名刺のデザイン (iOS `ImasProducerCard.Design`)。表に載せるものは同じで、組みと線と書体が変わる。 */
@Immutable
sealed interface ImasProducerCardDesign {
    /** 入場証。左に担当色の縦の帯。 */
    data object Pass : ImasProducerCardDesign

    /** かしこまった名刺。紙のまま、担当色は名前の上の細い罫と判子だけ。 */
    data object Formal : ImasProducerCardDesign

    /** ポップ。墨の太い枠と担当色の太い帯、名前の下の太い線。 */
    data object Pop : ImasProducerCardDesign

    /** 自作の画像。表は自分で作った名刺の画像、裏は裏の画像 (無ければ QR の裏)。 */
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

/** 名刺の表で 1 つのブランドにまとめて並べる担当 (コアの `CardFaceOshiGroup`)。 */
@Immutable
data class ImasProducerCardFaceGroup(
    /** ブランドの略称。名前の行が無いときだけ判子の下に刷る。 */
    val label: String,
    val oshi: List<ImasProducerCardOshi>
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

/** 名刺の裏 (紙に刷る裏と同じ: QR・参加公演数・回収曲数・日付)。iOS `ImasProducerCard.Back`。 */
@Immutable
data class ImasProducerCardBack(
    /** QR にする中身 (交換用の名刺の URL か、自分の QR の URL)。 */
    val qr: String,
    /** 「2026.10.06 時点」。 */
    val issuedLabel: String,
    /** QR の読み上げ (「交換用の QR コード」)。 */
    val qrLabel: String = "交換用の QR コード",
    /** QR の横の案内。 */
    val note: String = "読み取るとアプリの名刺入れに入ります。アプリが無ければ Web で開きます。",
    val showCount: Long? = null,
    val songCount: Long? = null
)

/**
 * P名刺 1 枚に載せるもの (名刺と、名刺の下の詳細で同じもの)。iOS `ImasProducerCard` の値。
 *
 * @param oshi 担当の全員 (名刺の下の担当の一覧)。
 * @param faceGroups 名刺の表に並べる担当 (コアの `producerCardFace` のブランドごとのまとまり)。
 * @param oshiCaption 判子の下の 1 行 (コアの `CardFace.oshiCaption`)。
 * @param moreOshi 表で数で畳んだ担当の人数。
 * @param handle 表に刷るハンドル 1 つ。
 * @param cells 記録の数 (参加公演・回収曲・次の現場)。空なら掲示板を出さない。
 * @param boardTrailing 掲示板の右上の印字 (「2014 — 2026」)。
 * @param photoUrl 担当の写真 (名刺の下の担当の一覧の上に広げる)。
 * @param photoEntityId 写真を端末に取り込んだ担当の id から引く (自分の名刺)。
 * @param portraitUrl 名刺の写真 (自分で選んだ写真。表の右の証明写真の枠に出す)。
 * @param nameFamily 名前の書体。null は見出しの書体。
 * @param back 裏。null なら返さない (自作の画像に裏の画像があればそれを裏にする)。
 */
@Immutable
data class ImasProducerCardContent(
    val name: String,
    val design: ImasProducerCardDesign = ImasProducerCardDesign.Pass,
    val sinceImprint: String? = null,
    val message: String? = null,
    val oshi: List<ImasProducerCardOshi> = emptyList(),
    val faceGroups: List<ImasProducerCardFaceGroup> = emptyList(),
    val oshiCaption: String? = null,
    val moreOshi: Int = 0,
    val handle: String? = null,
    val links: List<ImasProducerCardLink> = emptyList(),
    val cells: List<ImasBoardCell> = emptyList(),
    val boardTrailing: String? = null,
    val photoUrl: String? = null,
    val photoEntityId: String? = null,
    val portraitUrl: String? = null,
    val nameFamily: FontFamily? = null,
    val back: ImasProducerCardBack? = null
) {
    /** 裏があるか (自作の画像の裏、または QR の裏)。 */
    val hasBack: Boolean get() = (design as? ImasProducerCardDesign.Face)?.back != null || back != null
}

/** 名刺の幅の上限 (広い画面で紙が大きくなりすぎないように)。 */
private const val CARD_MAX_WIDTH = 480f

/** 端末の「動きを減らす」(アニメーションの倍率が 0)。回さずに入れ替える。 */
@Composable
private fun rememberReduceMotion(): Boolean {
    val resolver = LocalContext.current.contentResolver
    return remember(resolver) {
        runCatching { Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }.getOrDefault(false)
    }
}

/**
 * P名刺 1 枚 (91:55 の紙)。押すと y 軸で裏返る (動きを減らす設定では回さず入れ替える)。下に「表 裏」の印字。
 * 読み上げは 1 つの要素にし、押して (操作で) 返せる。角丸と縁は面ごとに付けて面と一緒に回す。
 *
 * @param isFlippable 押して裏返せる (編集画面の固定の見本は返さない)。返せない名刺は QR を描かない。
 */
@Composable
fun ImasProducerCard(content: ImasProducerCardContent, modifier: Modifier = Modifier, isFlippable: Boolean = true) {
    val canFlip = isFlippable && content.hasBack
    var showingBack by remember(content.design, content.back) { mutableStateOf(false) }
    val flipped = showingBack && canFlip
    val reduceMotion = rememberReduceMotion()
    val haptics = rememberImasHaptics()
    val angle by animateFloatAsState(if (flipped && !reduceMotion) 180f else 0f, label = "meishi_flip")
    val density = LocalDensity.current.density
    val lead = content.oshi.firstOrNull()
    val ink = ImasMeishiInk.screen(lead?.seed, lead?.brand)
    // 返せない名刺 (編集画面の見本) は裏を出さないので QR を描かない。
    val qr = remember(canFlip, content.back?.qr) { if (canFlip) content.back?.qr?.let(::imasQrMatrix) else null }
    // 角丸と縁は面ごと (外に付けると回る途中で枠だけ残る)。
    val shape = RoundedCornerShape(DS.rTag)

    fun flip() {
        if (!canFlip) return
        haptics.selection()
        showingBack = !showingBack
    }

    val frontLabel = remember(content) { frontLabel(content) }
    val backLabel = remember(content) { backLabel(content) }
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        BoxWithConstraints(
            Modifier
                .widthIn(max = CARD_MAX_WIDTH.dp)
                .fillMaxWidth()
                .aspectRatio(ImasMeishi.ASPECT)
                .then(if (canFlip) Modifier.imasRowPress(onClick = ::flip) else Modifier)
                .clearAndSetSemantics {
                    contentDescription = if (flipped) backLabel else frontLabel
                    if (canFlip) {
                        role = Role.Button
                        stateDescription = if (flipped) "押すと表を見せます" else "押すと裏を見せます"
                        onClick(label = if (flipped) "表を見せる" else "裏を見せる") { flip(); true }
                    }
                }
        ) {
            val scale = maxWidth.value / ImasMeishi.WIDTH
            val showBackFace = if (reduceMotion) flipped else angle > 90f
            Box(
                Modifier.fillMaxSize().graphicsLayer {
                    rotationY = angle
                    cameraDistance = 12f * density
                }
            ) {
                if (!showBackFace) {
                    Box(Modifier.fillMaxSize().imasSurfaceEdge(shape, fill = ink.paper).clip(shape)) {
                        MeishiFrontSide(content, ink, scale)
                    }
                } else {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .graphicsLayer { rotationY = if (reduceMotion) 0f else 180f }
                            .imasSurfaceEdge(shape, fill = ink.paper)
                            .clip(shape)
                    ) { MeishiBackSide(content, ink, qr, scale) }
                }
            }
        }
        if (canFlip) {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), modifier = Modifier.clearAndSetSemantics { }) {
                Text("表", style = ImasTextRole.IMPRINT.style, color = if (flipped) DS.ink3 else DS.ink)
                Text("裏", style = ImasTextRole.IMPRINT.style, color = if (flipped) DS.ink else DS.ink3)
            }
        }
    }
}

@Composable
private fun MeishiFrontSide(content: ImasProducerCardContent, ink: ImasMeishiInk, scale: Float) {
    when (val design = content.design) {
        is ImasProducerCardDesign.Face -> MeishiImageSide(design.front, ink)
        else -> ImasMeishiFront(
            name = content.name,
            ink = ink,
            look = when (design) {
                ImasProducerCardDesign.Formal -> ImasMeishiLook.FORMAL
                ImasProducerCardDesign.Pop -> ImasMeishiLook.POP
                else -> ImasMeishiLook.PASS
            },
            sinceImprint = content.sinceImprint,
            oshiGroups = content.faceGroups.map { group ->
                ImasMeishiOshiGroup(group.label, group.oshi.map { item ->
                    val file = rememberCustomImage(item.entityId)
                    ImasMeishiOshi(
                        id = item.id, name = item.name, shortName = item.shortName,
                        color = ImasMeishiInk.stampColor(item.seed, item.brand, ink.ink),
                        picture = (item.imageUrl ?: file?.let { Uri.fromFile(it).toString() })?.let { ImasMeishiPicture.Url(it) }
                    )
                })
            },
            oshiCaption = content.oshiCaption,
            moreOshi = content.moreOshi,
            handle = content.handle,
            nameFamily = content.nameFamily,
            portrait = content.portraitUrl?.let { ImasMeishiPicture.Url(it) },
            scale = scale
        )
    }
}

@Composable
private fun MeishiBackSide(content: ImasProducerCardContent, ink: ImasMeishiInk, qr: BitMatrix?, scale: Float) {
    val faceBack = (content.design as? ImasProducerCardDesign.Face)?.back
    val back = content.back
    when {
        faceBack != null -> MeishiImageSide(faceBack, ink)
        back != null -> ImasMeishiBack(
            qr = qr, note = back.note, issuedLabel = back.issuedLabel, ink = ink,
            showCount = back.showCount, songCount = back.songCount, scale = scale
        )
    }
}

/** 自作の名刺の画像。紙の大きさの枠を先に作り、画像は比率のまま切らずに収める (余りは紙の色)。 */
@Composable
private fun MeishiImageSide(url: String, ink: ImasMeishiInk) {
    Box(Modifier.fillMaxSize().background(ink.paper)) {
        ImasMeishiPictureView(
            ImasMeishiPicture.Url(url), Modifier.fillMaxSize(), contentScale = ContentScale.Fit,
            fallback = { Box(Modifier.fillMaxSize().background(ink.paper)) }
        )
    }
}

private fun frontLabel(c: ImasProducerCardContent): String {
    if (c.design is ImasProducerCardDesign.Face) return "${c.name}の名刺の画像"
    val parts = mutableListOf("${c.name}の名刺")
    c.sinceImprint?.let { parts += it }
    val names = c.faceGroups.flatMap { g -> g.oshi.map { it.name } }
    if (names.isNotEmpty()) {
        val joined = names.joinToString("、")
        parts += if (c.moreOshi > 0) "担当 $joined ほか${c.moreOshi}人" else "担当 $joined"
    }
    c.handle?.let { parts += it }
    if (c.portraitUrl != null) parts += "写真あり"
    return parts.joinToString("。")
}

private fun backLabel(c: ImasProducerCardContent): String {
    if ((c.design as? ImasProducerCardDesign.Face)?.back != null) return "${c.name}の名刺の画像の裏"
    val back = c.back ?: return "${c.name}の名刺の裏"
    val parts = mutableListOf("${c.name}の名刺の裏", back.qrLabel)
    back.showCount?.let { parts += "参加公演 $it" }
    back.songCount?.let { parts += "回収曲 $it" }
    if (back.issuedLabel.isNotEmpty()) parts += back.issuedLabel
    return parts.joinToString("。")
}

// MARK: - 名刺の下の紙面

/**
 * 名刺に収まらない詳細を名刺の下に並べる: ひとこと・担当 (担当の写真と一覧)・リンクの一覧・記録の掲示板。
 * 自分の名刺・受け取った名刺・受け取りの確認で同じ組み。iOS `ImasProducerCardDetails`。
 */
@Composable
fun ImasProducerCardDetails(
    content: ImasProducerCardContent,
    modifier: Modifier = Modifier,
    onOpenLink: ((ImasProducerCardLink) -> Unit)? = null,
    onOpenOshi: ((ImasProducerCardOshi) -> Unit)? = null
) {
    val photo = rememberCustomImage(content.photoEntityId)?.let { Uri.fromFile(it).toString() } ?: content.photoUrl
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.section)) {
        val message = content.message
        if (!message.isNullOrEmpty()) {
            ImasSection("ひとこと", style = ImasSectionHeaderStyle.SMALL) {
                ImasCard { Text(message, style = ImasTextRole.BODY.style, color = DS.ink, modifier = Modifier.fillMaxWidth()) }
            }
        }
        if (content.oshi.isNotEmpty()) {
            ImasSection("担当", style = ImasSectionHeaderStyle.SMALL) {
                ImasCardList {
                    if (photo != null) {
                        // 担当の写真の帯。大きさの決まった枠を先に作り、その上に画像を重ねてから切る
                        // (縦長の写真で下の行に被さったことがある)。
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .aspectRatio(ImasMeishi.ASPECT)
                                .semantics { contentDescription = content.oshi.first().let { "${it.name}の写真" } }
                        ) { ImasMeishiPictureView(ImasMeishiPicture.Url(photo), Modifier.fillMaxSize()) }
                    }
                    content.oshi.forEachIndexed { index, item ->
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
                            position = if (index == 0 && photo == null) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING,
                            modifier = onOpenOshi?.let { open -> Modifier.imasRowPress(onClick = { open(item) }) } ?: Modifier
                        )
                    }
                }
            }
        }
        if (content.links.isNotEmpty()) {
            ImasSection("リンク", style = ImasSectionHeaderStyle.SMALL) {
                ImasCardList {
                    content.links.forEachIndexed { index, link ->
                        ImasValueRow(
                            key = link.label,
                            value = link.display,
                            isLink = onOpenLink != null,
                            position = if (index == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING,
                            onClick = onOpenLink?.let { open -> { open(link) } }
                        )
                    }
                }
            }
        }
        if (content.cells.isNotEmpty()) {
            ImasBoard(cells = content.cells, title = "RECORD", trailing = content.boardTrailing)
        }
    }
}

// MARK: - 自作の名刺の画像

/** 日本の名刺の比 (91:55)。 */
const val ImasCardFaceAspect = ImasMeishi.ASPECT

/**
 * 自作の名刺の画像の小さな見本 (91:55 の枠に収める。比率の違う画像も切らずに収める)。iOS `ImasCardFace`。
 * 名刺入れの行の先頭・デザインの札・編集画面。名刺そのものは [ImasProducerCard] の [ImasProducerCardDesign.Face]。
 */
@Composable
fun ImasCardFace(front: String, modifier: Modifier = Modifier, label: String = "名刺の画像") {
    val shape = RoundedCornerShape(DS.rTag)
    Box(
        modifier
            .fillMaxWidth()
            .aspectRatio(ImasCardFaceAspect)
            .imasSurfaceEdge(shape, fill = DS.surface2)
            .clip(shape)
            .semantics { contentDescription = label }
    ) {
        ImasMeishiPictureView(ImasMeishiPicture.Url(front), Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
    }
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
