package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.SubcomposeAsyncImage
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
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
// ImasProducerCard   P名刺 1 枚。担当の入場証 (`ImasPass`) を 1 枚に広げた紙。
//                    上の帯が担当の色でストラップの穴、担当の写真、名前を大きく、ひとこと、
//                    担当の行、リンクの行、下に記録の電光掲示板 (`ImasBoard`)。
//                    使わない場面: アイドル 1 人の顔 → `ImasIdolHeader` / 担当の入口 → `ImasPass`。
//                    種類: 担当の写真がある (帯の下に写真) / 無い (写真の面を出さない。担当の行の判子は必ず出す)。
//                    状態: リンク・担当は押すと開く (`onOpenLink` / `onOpenOshi`)。渡さなければ押せない。
// ImasCameraFrame    カメラの読み取り窓。面と同じ角丸で切り、縦長 (3:4) に収める。中身はカメラの View。
// ImasQRCode         QR。チケットの紙 (ダークでも明るい) に墨で刷る。誤り訂正は L (中身が長いので
//                    読み取りやすさより収まりを取る)。題 (`caption`) を下に添えられる。
// =============================================================================

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
 * @param sinceImprint 帯の右の印字 (「SINCE 2014」)。
 * @param cells 記録の数 (参加公演・回収曲・次の現場)。空なら掲示板を出さない。
 * @param boardTrailing 掲示板の右上の印字 (「2014 — 2026」)。
 * @param photoUrl 帯の下に大きく出す担当の写真。
 * @param photoEntityId 写真を端末に取り込んだ担当の id から引く (自分の名刺)。
 */
@Composable
fun ImasProducerCard(
    name: String,
    modifier: Modifier = Modifier,
    sinceImprint: String? = null,
    message: String? = null,
    oshi: List<ImasProducerCardOshi> = emptyList(),
    links: List<ImasProducerCardLink> = emptyList(),
    cells: List<ImasBoardCell> = emptyList(),
    boardTrailing: String? = null,
    photoUrl: String? = null,
    photoEntityId: String? = null,
    onOpenLink: ((ImasProducerCardLink) -> Unit)? = null,
    onOpenOshi: ((ImasProducerCardOshi) -> Unit)? = null
) {
    val lead = oshi.firstOrNull()
    val t = imasThemeForBrand(lead?.seed, lead?.brand)
    val band = if (t.isNeutral) DS.sys else t.accent
    val onBand = if (t.isNeutral) DS.onSys else t.onAccent
    val shape = RoundedCornerShape(DS.rCard)
    // iOS の @ScaledMetric(relativeTo: .body) 220。文字の大きさに合わせて写真も広げる。
    val photoHeight = with(LocalDensity.current) { 220.sp.toDp() }
    val photo: Any? = rememberCustomImage(photoEntityId) ?: photoUrl
    Column(
        modifier
            .fillMaxWidth()
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
                    .padding(horizontal = DS.Space.card),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("PRODUCER PASS", style = ImasTextRole.IMPRINT.style, color = onBand.copy(alpha = 0.9f), maxLines = 1)
                Spacer(Modifier.weight(1f).widthIn(min = 60.dp))
                if (sinceImprint != null) {
                    Text(sinceImprint, style = ImasTextRole.IMPRINT.style, color = onBand.copy(alpha = 0.9f), maxLines = 1)
                }
            }
            // ストラップを通す穴 (地の色を透かす)。
            Box(
                Modifier
                    .size(width = 44.dp, height = 10.dp)
                    .background(DS.bg, CircleShape)
                    .border(1.dp, DS.line, CircleShape)
                    .clearAndSetSemantics { }
            )
        }

        if (photo != null) {
            val photoLabel = lead?.let { "${it.name}の写真" } ?: "担当の写真"
            SubcomposeAsyncImage(
                model = photo,
                contentDescription = photoLabel,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().height(photoHeight),
                loading = { Box(Modifier.fillMaxSize().background(DS.surface2)) },
                error = { Box(Modifier.fillMaxSize().background(DS.surface2)) }
            )
        }

        Column(
            Modifier.padding(horizontal = DS.Space.card, vertical = DS.Space.gapLoose),
            verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
        ) {
            ImasFitText(name, style = ImasType.heading(28.sp, FontWeight.ExtraBold), color = DS.ink, maxLines = 2, minScale = 0.8f)
            if (!message.isNullOrEmpty()) {
                Text(message, style = ImasTextRole.NOTE.style, color = DS.ink2)
            }
        }

        if (oshi.isNotEmpty()) {
            ImasPerforation(Modifier.padding(horizontal = DS.Space.card))
            Column {
                oshi.forEachIndexed { index, item ->
                    val position = if (index == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING
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
                        position = position,
                        modifier = onOpenOshi?.let { open -> Modifier.imasRowPress(onClick = { open(item) }) } ?: Modifier
                    )
                }
            }
        }

        if (links.isNotEmpty()) {
            ImasPerforation(Modifier.padding(horizontal = DS.Space.card))
            Column {
                links.forEachIndexed { index, link ->
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

        if (cells.isNotEmpty()) {
            ImasBoard(
                cells = cells,
                title = "RECORD",
                trailing = boardTrailing,
                modifier = Modifier.padding(DS.Space.gapLoose)
            )
        }
    }
}

// MARK: - QR

/**
 * QR (iOS `ImasQRCode`)。チケットの紙 (ダークでも明るい) に墨で刷るので、どの端末のカメラでも読める。
 * 誤り訂正は L。下に題 ([caption])。
 */
@Composable
fun ImasQRCode(text: String, modifier: Modifier = Modifier, caption: String? = null) {
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
                .semantics { contentDescription = "名刺の QR コード" }
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
