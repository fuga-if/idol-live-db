package com.fugaif.imaslivedb.ui.sortmaker

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.TextSnippet
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.games.SortMakerSubject
import com.fugaif.imaslivedb.ui.share.ShareCardActionPane
import com.fugaif.imaslivedb.ui.share.ShareCardArtwork
import com.fugaif.imaslivedb.ui.share.ShareCardRatio
import com.fugaif.imaslivedb.ui.share.ShareCardSheet
import com.fugaif.imaslivedb.ui.share.ShareCardSize
import com.fugaif.imaslivedb.ui.share.ShareInk
import com.fugaif.imaslivedb.ui.share.SoloShareScaffold
import com.fugaif.imaslivedb.ui.share.SocialShare
import com.fugaif.imaslivedb.ui.share.rememberShareCardPalette
import uniffi.imas_core.SortMakerShareRow
import uniffi.imas_core.sortMakerShareText

// =============================================================================
// 結果の共有シート。画像カード (ベスト10) と、文字だけの共有。iOS SortMakerShareCard.swift の移植。
// =============================================================================

@Composable
fun SortMakerShareSheet(
    subject: SortMakerSubject,
    scopeLabel: String,
    rows: List<Pair<Int, SortMakerItem>>,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val topArtworkUrl = (rows.firstOrNull()?.second as? SortMakerItem.SongItem)?.song?.artworkUrl
    var artwork by remember { mutableStateOf<ImageBitmap?>(null) }
    var isPreparing by remember(topArtworkUrl) { mutableStateOf(!topArtworkUrl.isNullOrBlank()) }

    LaunchedEffect(topArtworkUrl) {
        artwork = ShareCardArtwork.load(context, topArtworkUrl)
        isPreparing = false
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
                isPreparingCard = isPreparing,
                fileNamePrefix = "sort_maker"
            ) { size ->
                SortMakerShareCard(subject = subject, scopeLabel = scopeLabel, rows = rows, artwork = artwork, size = size)
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(com.fugaif.imaslivedb.ui.theme.DS.fill)
                    .clickable { SocialShare.shareText(context, shareText) }
                    .padding(vertical = 12.dp),
                horizontalArrangement = Arrangement.Center
            ) {
                Icon(Icons.Filled.TextSnippet, null, tint = com.fugaif.imaslivedb.ui.theme.DS.ink, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(8.dp))
                Text("テキストでシェア", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = com.fugaif.imaslivedb.ui.theme.DS.ink)
            }
        }
    }
}

/**
 * 画像カード。near-black 地に 1 位を大きく、2〜10 位を 1 行ずつ。
 * 版権の都合でアイドルの画像は載せず、メンバーカラーの印だけにする。
 */
@Composable
private fun SortMakerShareCard(
    subject: SortMakerSubject,
    scopeLabel: String,
    rows: List<Pair<Int, SortMakerItem>>,
    artwork: ImageBitmap?,
    size: ShareCardSize
) {
    val palette = rememberShareCardPalette(seed = rows.firstOrNull()?.second?.seed)
    SoloShareScaffold(palette = palette, size = size, badge = subject.title) {
        Column {
            Text(
                scopeLabel, fontSize = 13.sp, fontWeight = FontWeight.Medium,
                color = ShareInk.ink.copy(alpha = 0.6f), maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 10.dp)
            )

            val first = rows.firstOrNull()
            if (first != null) {
                Row(modifier = Modifier.padding(top = 18.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    if (subject == SortMakerSubject.SONG) {
                        FirstVisual(artwork, palette.accentDeep)
                        Spacer(Modifier.width(16.dp))
                    }
                    Column {
                        Text("${first.first}位", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = palette.accent)
                        Text(
                            first.second.title,
                            fontSize = 32.sp, fontWeight = FontWeight.Bold,
                            color = ShareInk.ink, maxLines = 2, overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }

            Column(modifier = Modifier.padding(top = 20.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                rows.drop(1).take(9).forEach { (rank, item) ->
                    val rowAccent = rememberShareCardPalette(seed = item.seed).accent
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        Text(
                            "$rank", fontSize = 15.sp, fontWeight = FontWeight.Bold,
                            color = ShareInk.ink.copy(alpha = 0.55f),
                            modifier = Modifier.width(26.dp)
                        )
                        Spacer(Modifier.width(10.dp))
                        androidx.compose.foundation.layout.Box(
                            Modifier.width(4.dp).height(16.dp).clip(RoundedCornerShape(2.dp)).background(rowAccent)
                        )
                        Spacer(Modifier.width(10.dp))
                        Text(
                            item.title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold,
                            color = ShareInk.ink.copy(alpha = 0.92f), maxLines = 1, overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun FirstVisual(artwork: ImageBitmap?, fallback: androidx.compose.ui.graphics.Color) {
    if (artwork != null) {
        Image(
            bitmap = artwork, contentDescription = null, contentScale = ContentScale.Crop,
            modifier = Modifier.size(96.dp).clip(RoundedCornerShape(10.dp))
        )
    } else {
        androidx.compose.foundation.layout.Box(
            Modifier.size(96.dp).clip(RoundedCornerShape(10.dp)).background(fallback),
            contentAlignment = androidx.compose.ui.Alignment.Center
        ) {
            Icon(Icons.Filled.MusicNote, null, tint = ShareInk.ink.copy(alpha = 0.3f), modifier = Modifier.size(32.dp))
        }
    }
}
