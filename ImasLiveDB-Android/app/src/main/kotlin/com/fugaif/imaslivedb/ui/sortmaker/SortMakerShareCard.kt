package com.fugaif.imaslivedb.ui.sortmaker

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.TextSnippet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.games.SortMakerSubject
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.share.PosterShareScaffold
import com.fugaif.imaslivedb.ui.share.ShareCardActionPane
import com.fugaif.imaslivedb.ui.share.ShareCardArtwork
import com.fugaif.imaslivedb.ui.share.ShareCardRatio
import com.fugaif.imaslivedb.ui.share.ShareCardSheet
import com.fugaif.imaslivedb.ui.share.ShareCardSize
import com.fugaif.imaslivedb.ui.share.SocialShare
import com.fugaif.imaslivedb.ui.share.rememberShareCardPalette
import uniffi.imas_core.SortMakerShareRow
import uniffi.imas_core.sortMakerShareText

// =============================================================================
// 結果の共有シート。画像カード (ランキングのポスター) と、文字だけの共有。
// iOS SortMakerShareCard.swift (design(sort-maker) 2023e85d/d8475fef) の移植。
// =============================================================================

@Composable
fun SortMakerShareSheet(
    subject: SortMakerSubject,
    scopeLabel: String,
    rows: List<Pair<Int, SortMakerItem>>,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    // 表彰台 (1〜3 位) のジャケ。焼き込みは非同期読み込みを待たないので先に読んでおく。
    var artworks by remember { mutableStateOf<Map<String, ImageBitmap>>(emptyMap()) }
    var isLoadingArtwork by remember { mutableStateOf(true) }

    LaunchedEffect(rows) {
        val loaded = mutableMapOf<String, ImageBitmap>()
        rows.take(3).forEach { (_, item) ->
            if (item is SortMakerItem.SongItem) {
                ShareCardArtwork.load(context, item.song.artworkUrl)?.let { loaded[item.song.id] = it }
            }
        }
        artworks = loaded
        isLoadingArtwork = false
    }

    val shareText = remember(subject, scopeLabel, rows) {
        sortMakerShareText(
            title = subject.title,
            scopeLabel = scopeLabel,
            rows = rows.map { (rank, item) -> SortMakerShareRow(rank = rank.toUInt(), name = item.title) }
        )
    }

    ShareCardSheet(title = "結果をシェア", onDismiss = onDismiss) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            ShareCardActionPane(
                ratios = listOf(ShareCardRatio.PORTRAIT),
                isPreparingCard = isLoadingArtwork,
                fileNamePrefix = "sort_maker"
            ) { size ->
                SortMakerShareCard(subject = subject, scopeLabel = scopeLabel, rows = rows, artworks = artworks, size = size)
            }

            ImasButton(
                title = "テキストでシェア",
                onClick = { SocialShare.shareText(context, shareText) },
                icon = Icons.Filled.TextSnippet,
                role = ImasButtonRole.SECONDARY,
                size = ImasButtonSize.MEDIUM
            )
        }
    }
}

/**
 * 画像カード: ランキングのポスター。
 *
 * 上に「MY BEST 10」の大見出し、中央に 1〜3 位の表彰台 (1 位を大きく真ん中に)、
 * 下に 4〜10 位を 2 列で。near-black の単色地に、1 位の色を差し色として 1 点だけ使う。
 *
 * 焼き込む固定キャンバスなので、色は固定色だけ・文字は固定 sp
 * (アプリ内の文字サイズ倍率がかかると枠からあふれるため)。
 * 版権の都合でアイドルの絵は載せず、メンバーカラーのモノグラムにする。
 */
@Composable
private fun SortMakerShareCard(
    subject: SortMakerSubject,
    scopeLabel: String,
    rows: List<Pair<Int, SortMakerItem>>,
    artworks: Map<String, ImageBitmap>,
    size: ShareCardSize
) {
    val podium = rows.take(3)
    val rest = rows.drop(3).take(7)
    val palette = rememberShareCardPalette(seed = rows.firstOrNull()?.second?.seed)

    PosterShareScaffold(
        palette = palette,
        width = size.widthUnits.dp,
        height = size.heightUnits.dp,
        kicker = subject.title,
        trailingKicker = "RESULT",
        title = if (rows.size >= 10) "MY BEST 10" else "MY BEST ${rows.size}",
        subtitle = scopeLabel
    ) {
        PodiumRow(podium = podium, accent = palette.accent, artworks = artworks, modifier = Modifier.fillMaxWidth().padding(top = 22.dp))
        if (rest.isNotEmpty()) {
            Box(Modifier.fillMaxWidth().padding(top = 18.dp).height(1.dp).background(Color.White.copy(alpha = 0.12f)))
            RestGrid(rest = rest, modifier = Modifier.padding(top = 14.dp))
        }
    }
}

// MARK: - 表彰台

@Composable
private fun PodiumRow(podium: List<Pair<Int, SortMakerItem>>, accent: Color, artworks: Map<String, ImageBitmap>, modifier: Modifier = Modifier) {
    // 並びは 2 位・1 位・3 位 (1 位を真ん中に高く)。
    val order = listOf(1, 0, 2).filter { it < podium.size }
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Bottom) {
        order.forEach { i ->
            PodiumSlot(row = podium[i], isFirst = i == 0, accent = accent, artworks = artworks)
        }
    }
}

@Composable
private fun PodiumSlot(row: Pair<Int, SortMakerItem>, isFirst: Boolean, accent: Color, artworks: Map<String, ImageBitmap>) {
    val (rank, item) = row
    val side = if (isFirst) 148.dp else 112.dp
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            "$rank", fontSize = if (isFirst) 44.sp else 32.sp, fontWeight = FontWeight.Black,
            color = if (isFirst) accent else Color.White.copy(alpha = 0.75f)
        )
        PodiumVisual(item = item, side = side, artworks = artworks)
        Text(
            item.title, fontSize = if (isFirst) 15.sp else 12.sp, fontWeight = FontWeight.Bold, color = Color.White,
            textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.width(side + 12.dp).height(if (isFirst) 40.dp else 32.dp)
        )
    }
}

@Composable
private fun PodiumVisual(item: SortMakerItem, side: androidx.compose.ui.unit.Dp, artworks: Map<String, ImageBitmap>) {
    when (item) {
        is SortMakerItem.SongItem -> {
            val artwork = artworks[item.song.id]
            if (artwork != null) {
                Image(
                    bitmap = artwork, contentDescription = null, contentScale = ContentScale.Crop,
                    modifier = Modifier.size(side).clip(RoundedCornerShape(side * 0.08f))
                )
            } else {
                val fallback = rememberShareCardPalette(seed = null).accentDeep
                Box(
                    Modifier.size(side).clip(RoundedCornerShape(side * 0.08f)).background(fallback),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        item.song.title, fontSize = (side.value * 0.12f).sp, fontWeight = FontWeight.Bold,
                        color = Color.White.copy(alpha = 0.8f), textAlign = TextAlign.Center, maxLines = 3,
                        overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(side * 0.1f)
                    )
                }
            }
        }
        is SortMakerItem.IdolItem -> {
            val palette = rememberShareCardPalette(seed = item.idol.color)
            val shortName = item.idol.shortName
            Box(
                Modifier
                    .size(side)
                    .clip(CircleShape)
                    .background(palette.accentDeep)
                    .border(side * 0.03f, palette.accent, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    shortName,
                    fontSize = (side.value * (if (shortName.length >= 3) 0.24f else 0.32f)).sp,
                    fontWeight = FontWeight.Black, color = palette.accent,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(side * 0.12f)
                )
            }
        }
    }
}

// MARK: - 4〜10 位

@Composable
private fun RestGrid(rest: List<Pair<Int, SortMakerItem>>, modifier: Modifier = Modifier) {
    // 縦に読めるよう左列 4〜7 位、右列 8〜10 位。
    val left = rest.take(4)
    val right = rest.drop(4)
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(20.dp)) {
        RestColumn(items = left, modifier = Modifier.weight(1f))
        RestColumn(items = right, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun RestColumn(items: List<Pair<Int, SortMakerItem>>, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(9.dp)) {
        items.forEach { (rank, item) ->
            val rowAccent = rememberShareCardPalette(seed = item.seed).accent
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "$rank", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = Color.White.copy(alpha = 0.5f),
                    modifier = Modifier.width(22.dp), textAlign = TextAlign.End
                )
                Box(Modifier.width(3.dp).height(14.dp).clip(RoundedCornerShape(1.5.dp)).background(rowAccent))
                Text(
                    item.title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.92f),
                    maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}
