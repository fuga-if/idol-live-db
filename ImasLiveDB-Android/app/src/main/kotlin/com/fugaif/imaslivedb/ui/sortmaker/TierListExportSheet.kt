package com.fugaif.imaslivedb.ui.sortmaker

import androidx.compose.runtime.staticCompositionLocalOf
import com.fugaif.imaslivedb.di.AppModule
import android.content.Context
import android.graphics.Bitmap
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
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.ImageBitmap
import com.fugaif.imaslivedb.data.games.TierDef
import com.fugaif.imaslivedb.data.games.TierListBoard
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.share.PosterShareScaffold
import com.fugaif.imaslivedb.ui.share.SHARE_CARD_SCALE
import com.fugaif.imaslivedb.ui.share.ShareCardArtwork
import com.fugaif.imaslivedb.ui.share.ShareCardFiles
import com.fugaif.imaslivedb.ui.share.ShareCardSaveResult
import com.fugaif.imaslivedb.ui.share.SocialShare
import com.fugaif.imaslivedb.ui.share.rememberShareCardCapture
import com.fugaif.imaslivedb.ui.share.rememberShareCardPalette
import com.fugaif.imaslivedb.ui.theme.BrandColors
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasAlwaysDark
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.android.awaitFrame
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import uniffi.imas_core.TierListShareTier
import uniffi.imas_core.tierListShareText
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.request.allowHardware
import coil3.toBitmap

// =============================================================================
// 並べ終えたティアー表を「全部入りの 1 枚」にして、写真に保存 / シェアする。
// iOS TierListExport.swift の移植。
//
// 画像は段ごとに、ジャケ (曲) かメンバーカラーのモノグラム (アイドル) を全部並べる。
// 件数で縦に伸びる (横幅は SNS で縮んでも読める 1080px 固定)。
// 焼き込みは画像の非同期読み込みを待たないので、ジャケは先に小さく読んでから焼く。
// =============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TierListExportSheet(
    board: TierListBoard,
    items: Map<String, SortMakerItem>,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var thumbnails by remember { mutableStateOf<Map<String, ImageBitmap>?>(null) }
    var bitmap by remember { mutableStateOf<Bitmap?>(null) }
    var saveMessage by remember { mutableStateOf<String?>(null) }
    val capture = rememberShareCardCapture()

    LaunchedEffect(board.id) {
        thumbnails = loadThumbnails(context, board, items)
    }

    val loadedThumbnails = thumbnails
    if (loadedThumbnails != null && bitmap == null) {
        // 見えない位置で 1 回だけ組んで焼く (画面に出す前に完成させる)。
        HiddenCapture(capture = capture) {
            TierListBoardImage(board = board, items = items, thumbnails = loadedThumbnails)
        }
        LaunchedEffect(board.id, loadedThumbnails) {
            // 2 フレーム待って確実に描画させてから焼く。
            awaitFrame()
            awaitFrame()
            bitmap = capture.toBitmap()
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = DS.bg) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = DS.Space.screen).padding(bottom = DS.sp7), verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
            ImasSheetToolbar(ImasSheetToolbarKind.Read(onClose = onDismiss), title = "画像にする")

            val bmp = bitmap
            if (bmp != null) {
                Image(
                    bitmap = bmp.asImageBitmap(), contentDescription = null, contentScale = ContentScale.FillWidth,
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(DS.rMD))
                )
            } else {
                Column(
                    modifier = Modifier.fillMaxWidth().height(320.dp),
                    verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    ImasInlineLoading()
                    ImasText("画像を作っています…", role = ImasTextRole.META)
                }
            }

            if (board.unplacedIds.isNotEmpty()) {
                ImasNote("未分類の ${board.unplacedIds.size} 件は画像に入りません。")
            }

            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose), modifier = Modifier.fillMaxWidth()) {
                ImasButton(
                    title = "写真に保存",
                    onClick = {
                        scope.launch {
                            val b = bitmap ?: return@launch
                            when (ShareCardFiles.saveToPictures(context, b, "tier_list")) {
                                ShareCardSaveResult.Saved -> saveMessage = "写真に保存しました"
                                ShareCardSaveResult.Failed -> saveMessage = "保存できませんでした。もう一度試してください。"
                                ShareCardSaveResult.NeedsDocumentPicker -> saveMessage = "写真に保存しました"
                            }
                        }
                    },
                    icon = Icons.Filled.Download,
                    role = ImasButtonRole.PRIMARY,
                    size = ImasButtonSize.LARGE,
                    enabled = bmp != null,
                    modifier = Modifier.weight(1f)
                )
                ImasButton(
                    title = "シェア",
                    onClick = { scope.launch { bitmap?.let { ShareCardFiles.share(context, it, "tier_list") } } },
                    icon = Icons.Filled.Share,
                    role = ImasButtonRole.SECONDARY,
                    size = ImasButtonSize.LARGE,
                    enabled = bmp != null,
                    modifier = Modifier.weight(1f)
                )
            }

            ImasButton(
                title = "テキストでシェア",
                onClick = { SocialShare.shareText(context, shareText(board, items)) },
                role = ImasButtonRole.PLAIN,
                size = ImasButtonSize.MEDIUM
            )
        }
    }

    if (saveMessage != null) {
        AlertDialog(
            onDismissRequest = { saveMessage = null },
            title = { Text(saveMessage ?: "") },
            confirmButton = { TextButton(onClick = { saveMessage = null }) { Text("OK") } }
        )
    }
}

/** 文面はコアが組む (空の段を飛ばす・1 段 5 件まで)。 */
private fun shareText(board: TierListBoard, items: Map<String, SortMakerItem>): String = tierListShareText(
    title = board.displayTitle, scopeLabel = board.scopeLabel,
    tiers = board.tiers.map { t -> TierListShareTier(label = t.label, names = board.idsInTier(t.id).mapNotNull { items[it]?.title }) }
)

/** 段に載っている曲のジャケを小さく読む (数百枚でも重くならない大きさ、同時 8 枚まで)。 */
/**
 * 段に載っているものの絵を小さく読む。曲はジャケ、アイドルはアプリ内で出しているのと
 * 同じアイコン (利用者が取り込んだ画像)。アイコンが無いアイドルはモノグラムのまま。
 */
private suspend fun loadThumbnails(context: Context, board: TierListBoard, items: Map<String, SortMakerItem>): Map<String, ImageBitmap> {
    val imageStore = AppModule.from(context).customImageStore
    val targets: List<Pair<String, Any>> = board.itemIds.mapNotNull { id ->
        if (board.tierIndexOf(id) == null) return@mapNotNull null
        when (val item = items[id]) {
            is SortMakerItem.SongItem ->
                item.song.artworkUrl?.takeIf { it.isNotBlank() }?.let { id to ShareCardArtwork.highResolution(it) }
            is SortMakerItem.IdolItem -> imageStore.primaryImageFile(item.idol.id)?.let { id to it }
            else -> null
        }
    }
    if (targets.isEmpty()) return emptyMap()
    val semaphore = Semaphore(8)
    return coroutineScope {
        targets.map { (id, url) ->
            async {
                semaphore.withPermit { loadThumbnail(context, url)?.let { id to it } }
            }
        }.awaitAll().filterNotNull().toMap()
    }
}

private suspend fun loadThumbnail(context: Context, data: Any): ImageBitmap? {
    val request = ImageRequest.Builder(context)
        .data(data)
        .size(144, 144)
        .allowHardware(false)
        .build()
    val result = runCatching { SingletonImageLoader.get(context).execute(request) }.getOrNull()
    return (result as? SuccessResult)?.image?.toBitmap()?.asImageBitmap()
}

/** 見えない位置に組んで、描いた内容だけ [capture] に録る (画面には出さない)。 */
@Composable
private fun HiddenCapture(capture: com.fugaif.imaslivedb.ui.share.ShareCardCapture, content: @Composable () -> Unit) {
    Box(Modifier.size(0.dp).clipToBounds()) {
        CompositionLocalProvider(LocalDensity provides Density(density = SHARE_CARD_SCALE, fontScale = 1f)) {
            Box(
                Modifier
                    .width(540.dp)
                    .wrapContentHeight()
                    .drawWithContent {
                        capture.layer.record { this@drawWithContent.drawContent() }
                        drawLayer(capture.layer)
                    }
            ) {
                // 書き出す 1 枚の地はほぼ黒。端末がライトでも中の部品はダーク側の色で組む。
                ImasAlwaysDark(content)
            }
        }
    }
}

// =============================================================================
// 書き出す 1 枚。near-black の地に、見出し → 段ごとの行 → フッター。
// 色は固定色、文字は固定 sp (端末の文字サイズ倍率がかかると枠からあふれるため)。
// アイドルはアプリ内と同じアイコン (取り込んだ画像) を、無ければメンバーカラーのモノグラムを載せる。
// =============================================================================

private val LABEL_WIDTH = 76.dp
private val GAP = 6.dp

/** 1 枚の一辺。段に入れた件数が多いほど小さくして、縦に伸びすぎないようにする (iOS と同じ閾値)。 */
private val LocalExportCell = staticCompositionLocalOf { 62.dp }
/** 名前を添えるか (件数が多いときは絵だけにする)。 */
private val LocalExportShowsNames = staticCompositionLocalOf { true }

@Composable
private fun TierListBoardImage(board: TierListBoard, items: Map<String, SortMakerItem>, thumbnails: Map<String, ImageBitmap>) {
    val placed = board.itemIds.count { board.tierIndexOf(it) != null }
    val cell = when {
        placed <= 150 -> 62.dp
        placed <= 400 -> 46.dp
        else -> 34.dp
    }
    CompositionLocalProvider(LocalExportCell provides cell, LocalExportShowsNames provides (placed <= 400)) {
        TierListBoardImageBody(board, items, thumbnails)
    }
}

@Composable
private fun TierListBoardImageBody(board: TierListBoard, items: Map<String, SortMakerItem>, thumbnails: Map<String, ImageBitmap>) {
    val palette = rememberShareCardPalette(seed = board.tiers.firstOrNull()?.colorSeed)
    PosterShareScaffold(
        palette = palette,
        width = 540.dp,
        height = null,
        kicker = "TIER LIST",
        title = board.displayTitle,
        titleSize = 32.sp,
        subtitle = board.scopeLabel
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 18.dp)
                .clip(RoundedCornerShape(10.dp)),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            board.tiers.forEach { tier -> ExportRow(tier, board, items, thumbnails) }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ExportRow(tier: TierDef, board: TierListBoard, items: Map<String, SortMakerItem>, thumbnails: Map<String, ImageBitmap>) {
    val ids = board.idsInTier(tier.id)
    val accent = rememberShareCardPalette(seed = tier.colorSeed).accent
    val onAccent = ImasTheme.onColor(accent)
    Row(modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
        Text(
            tier.label, fontSize = if (tier.label.length <= 2) 30.sp else 14.sp, fontWeight = FontWeight.Black,
            color = onAccent, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .padding(horizontal = 4.dp)
                .width(LABEL_WIDTH)
                .fillMaxHeight()
                .background(accent)
                .wrapContentHeight()
        )
        FlowRow(
            modifier = Modifier
                .weight(1f)
                .defaultMinSize(minHeight = LocalExportCell.current + (if (LocalExportShowsNames.current) 22.dp else 8.dp) + GAP * 2)
                .background(Color.White.copy(alpha = 0.06f))
                .padding(GAP),
            horizontalArrangement = Arrangement.spacedBy(GAP),
            verticalArrangement = Arrangement.spacedBy(GAP)
        ) {
            ids.forEach { id -> ExportTile(id, items, thumbnails) }
        }
    }
}

@Composable
private fun ExportTile(id: String, items: Map<String, SortMakerItem>, thumbnails: Map<String, ImageBitmap>) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        ExportVisual(id, items, thumbnails)
        if (LocalExportShowsNames.current) {
            val cell = LocalExportCell.current
            Text(
                items[id]?.title ?: "", fontSize = if (cell >= 60.dp) 9.sp else 7.sp, fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.85f),
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.width(cell)
            )
        }
    }
}

@Composable
private fun ExportVisual(id: String, items: Map<String, SortMakerItem>, thumbnails: Map<String, ImageBitmap>) {
    val CELL = LocalExportCell.current
    when (val item = items[id]) {
        is SortMakerItem.SongItem -> {
            val thumb = thumbnails[id]
            if (thumb != null) {
                Image(
                    bitmap = thumb, contentDescription = null, contentScale = ContentScale.Crop,
                    modifier = Modifier.size(CELL).clip(RoundedCornerShape(6.dp))
                )
            } else {
                val fallback = rememberShareCardPalette(seed = BrandColors.hex(item.song.brandId)).accentDeep
                Box(
                    Modifier.size(CELL).clip(RoundedCornerShape(6.dp)).background(fallback),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        item.song.title, fontSize = 8.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.85f),
                        textAlign = TextAlign.Center, maxLines = 3, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(4.dp)
                    )
                }
            }
        }
        is SortMakerItem.IdolItem -> {
            val palette = rememberShareCardPalette(seed = item.idol.color)
            val icon = thumbnails[id]
            if (icon != null) {
                Image(
                    bitmap = icon, contentDescription = null, contentScale = ContentScale.Crop,
                    modifier = Modifier.size(CELL).clip(CircleShape).border(2.dp, palette.accent, CircleShape)
                )
                return
            }
            val shortName = item.idol.shortName
            Box(
                Modifier
                    .size(CELL)
                    .clip(CircleShape)
                    .background(palette.accentDeep)
                    .border(2.dp, palette.accent, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    shortName, fontSize = if (shortName.length >= 3) 14.sp else 19.sp, fontWeight = FontWeight.Black,
                    color = palette.accent, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(6.dp)
                )
            }
        }
        null -> Box(Modifier.size(CELL).clip(RoundedCornerShape(6.dp)).background(Color.White.copy(alpha = 0.1f)))
    }
}
