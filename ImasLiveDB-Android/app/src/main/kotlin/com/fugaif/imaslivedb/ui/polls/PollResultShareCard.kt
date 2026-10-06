package com.fugaif.imaslivedb.ui.polls

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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.image.GalleryKind
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.producercard.ProducerCardFiles
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.share.PosterShareScaffold
import com.fugaif.imaslivedb.ui.share.ShareCardActionPane
import com.fugaif.imaslivedb.ui.share.ShareCardArtwork
import com.fugaif.imaslivedb.ui.share.ShareCardRatio
import com.fugaif.imaslivedb.ui.share.ShareCardSheet
import com.fugaif.imaslivedb.ui.share.ShareCardSize
import com.fugaif.imaslivedb.ui.share.ShareInk
import com.fugaif.imaslivedb.ui.share.rememberShareCardPalette
import com.fugaif.imaslivedb.ui.theme.BrandColors
import java.util.TimeZone
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.PollCardEntryInput
import uniffi.imas_core.PollCardRow
import uniffi.imas_core.PollCardTarget
import uniffi.imas_core.PollResultCard
import uniffi.imas_core.PollResultCardInput
import uniffi.imas_core.pollResultCard

// =============================================================================
// みんなの投票の結果をシェアする画像。iOS PollResultShareCard.swift の移植。
// 中身 (見出し・順位・載せる数) はコアの pollResultCard、組みはソートメーカーの画像と同じ。
// =============================================================================

/** 画像に載せる候補 1 つ (名前・差し色・焼き込む画像・画像の無いアイドルの判子の文字)。 */
data class PollResultShareItem(
    val name: String,
    val seed: String?,
    val image: ImageBitmap? = null,
    val monogram: String? = null
)

@Composable
fun PollResultShareSheet(
    detail: CommunityApi.PollDetail,
    songsById: Map<String, Song>,
    idolsById: Map<String, Idol>,
    unitsById: Map<String, ImasUnit>,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    var card by remember { mutableStateOf<PollResultCard?>(null) }
    var items by remember { mutableStateOf<Map<String, PollResultShareItem>>(emptyMap()) }

    LaunchedEffect(detail) {
        val now = System.currentTimeMillis()
        val isActive = detail.isActive
        // 締切が未知の値 (Long.MAX_VALUE) は開催中扱いなので、刷るのは今日の日付。
        val built = pollResultCard(
            PollResultCardInput(
                title = detail.title,
                target = when (detail.targetType) {
                    "idol" -> PollCardTarget.IDOL
                    "unit" -> PollCardTarget.UNIT
                    else -> PollCardTarget.SONG
                },
                isActive = isActive,
                endsAtEpochMs = detail.endsAtMs,
                nowEpochMs = now,
                tzOffsetSeconds = TimeZone.getDefault().getOffset(if (isActive) now else detail.endsAtMs) / 1000,
                totalVotes = detail.totalVotes.coerceAtLeast(0).toUInt(),
                entries = detail.entries.map { PollCardEntryInput(it.entityId, it.voteCount.coerceAtLeast(0).toUInt()) }
            )
        )
        val podiumIds = built.podium.map { it.entityId }.toSet()
        val store = AppModule.from(context).customImageStore
        // 焼き込みは読み込みを待たないので、表彰台の画像を先に ImageBitmap にしておく。
        suspend fun localImage(id: String, kind: GalleryKind): ImageBitmap? = withContext(Dispatchers.IO) {
            store.primaryImageFile(id, kind)?.let { ProducerCardFiles.decodeBounded(it, maxPixels = 600) }?.asImageBitmap()
        }
        val resolved = mutableMapOf<String, PollResultShareItem>()
        for (row in built.podium + built.rest) {
            val id = row.entityId
            val onPodium = id in podiumIds
            resolved[id] = when (detail.targetType) {
                "idol" -> idolsById[id]?.let {
                    PollResultShareItem(it.name, it.color, if (onPodium) localImage(id, GalleryKind.IDOL) else null, it.shortName)
                }
                "unit" -> unitsById[id]?.let {
                    PollResultShareItem(it.displayName, BrandColors.hex(it.brandId), if (onPodium) localImage(id, GalleryKind.UNIT) else null)
                }
                else -> songsById[id]?.let {
                    PollResultShareItem(it.title, BrandColors.hex(it.brandId), if (onPodium) ShareCardArtwork.load(context, it.artworkUrl) else null)
                }
            } ?: continue
        }
        items = resolved
        card = built
    }

    ShareCardSheet(title = "結果をシェア", onDismiss = onDismiss) {
        ShareCardActionPane(
            ratios = listOf(ShareCardRatio.PORTRAIT),
            isPreparingCard = card == null,
            fileNamePrefix = "poll_result"
        ) { size ->
            val ready = card
            if (ready != null) {
                PollResultShareCard(card = ready, items = items, size = size)
            } else {
                Box(Modifier.size(size.widthUnits.dp, size.heightUnits.dp).background(ShareInk.nearBlack))
            }
        }
    }
}

/**
 * 画像: 投票結果のポスター。骨格は [PosterShareScaffold]、中身は 1〜3 位の表彰台 (2 位・1 位・3 位の順) と
 * 4 位以降の 2 列。票数は表彰台の名前の下と行末に刷る。焼き込む固定キャンバスなので色は固定色、文字は固定 sp。
 */
@Composable
private fun PollResultShareCard(card: PollResultCard, items: Map<String, PollResultShareItem>, size: ShareCardSize) {
    val palette = rememberShareCardPalette(seed = card.podium.firstOrNull()?.let { items[it.entityId]?.seed })

    PosterShareScaffold(
        palette = palette,
        width = size.widthUnits.dp,
        height = size.heightUnits.dp,
        kicker = card.kicker,
        trailingKicker = card.imprint,
        title = card.title,
        titleSize = 38.sp,
        subtitle = card.subtitle
    ) {
        val order = listOf(1, 0, 2).filter { it < card.podium.size }
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 18.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.Bottom
        ) {
            order.forEach { i -> PodiumSlot(card.podium[i], items[card.podium[i].entityId], isFirst = i == 0, accent = palette.accent) }
        }
        if (card.rest.isNotEmpty()) {
            Box(Modifier.fillMaxWidth().padding(top = 16.dp).height(1.dp).background(Color.White.copy(alpha = 0.12f)))
            // 縦に読めるよう左列に前半 4 件、右列に残り。
            Row(modifier = Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                RestColumn(card.rest.take(4), items, Modifier.weight(1f))
                RestColumn(card.rest.drop(4), items, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun PodiumSlot(row: PollCardRow, item: PollResultShareItem?, isFirst: Boolean, accent: Color) {
    val side = if (isFirst) 148.dp else 112.dp
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            "${row.rank}", fontSize = if (isFirst) 44.sp else 32.sp, fontWeight = FontWeight.Black,
            color = if (row.rank == 1u) accent else Color.White.copy(alpha = 0.75f)
        )
        PodiumVisual(item, side)
        Text(
            item?.name.orEmpty(), fontSize = if (isFirst) 15.sp else 12.sp, fontWeight = FontWeight.Bold, color = Color.White,
            textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.width(side + 12.dp).height(if (isFirst) 40.dp else 32.dp)
        )
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("${row.voteCount}", fontSize = if (isFirst) 26.sp else 20.sp, fontWeight = FontWeight.ExtraBold, color = Color.White)
            Text("票", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.6f), modifier = Modifier.padding(bottom = 3.dp))
        }
    }
}

/** 画像は大きさの決まった枠に上寄せで切る (縦長の写真で顔が切れにくい)。無ければアイドルは判子、曲・ユニットは名前の札。 */
@Composable
private fun PodiumVisual(item: PollResultShareItem?, side: Dp) {
    val shape = RoundedCornerShape(side * 0.08f)
    val image = item?.image
    val monogram = item?.monogram
    when {
        image != null -> Image(
            bitmap = image, contentDescription = null, contentScale = ContentScale.Crop, alignment = Alignment.TopCenter,
            modifier = Modifier.size(side).clip(shape)
        )
        monogram != null -> {
            val palette = rememberShareCardPalette(seed = item.seed)
            Box(
                Modifier.size(side).clip(CircleShape).background(palette.accentDeep).border(side * 0.03f, palette.accent, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    monogram, fontSize = (side.value * (if (monogram.length >= 3) 0.24f else 0.32f)).sp,
                    fontWeight = FontWeight.Black, color = palette.accent, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(side * 0.12f)
                )
            }
        }
        else -> {
            val fallback = rememberShareCardPalette(seed = item?.seed).accentDeep
            Box(Modifier.size(side).clip(shape).background(fallback), contentAlignment = Alignment.Center) {
                Text(
                    item?.name.orEmpty(), fontSize = (side.value * 0.12f).sp, fontWeight = FontWeight.Bold,
                    color = Color.White.copy(alpha = 0.8f), textAlign = TextAlign.Center, maxLines = 3,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(side * 0.1f)
                )
            }
        }
    }
}

@Composable
private fun RestColumn(rows: List<PollCardRow>, items: Map<String, PollResultShareItem>, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(9.dp)) {
        rows.forEach { row ->
            val item = items[row.entityId]
            val rowAccent = rememberShareCardPalette(seed = item?.seed).accent
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "${row.rank}", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = Color.White.copy(alpha = 0.5f),
                    modifier = Modifier.width(22.dp), textAlign = TextAlign.End
                )
                Box(Modifier.width(3.dp).height(14.dp).clip(RoundedCornerShape(1.5.dp)).background(rowAccent))
                Text(
                    item?.name.orEmpty(), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.92f),
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f)
                )
                Text("${row.voteCount}", fontSize = 15.sp, fontWeight = FontWeight.ExtraBold, color = Color.White.copy(alpha = 0.7f))
            }
        }
    }
}
