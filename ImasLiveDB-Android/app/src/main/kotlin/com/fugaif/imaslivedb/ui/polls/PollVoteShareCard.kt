package com.fugaif.imaslivedb.ui.polls

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.ui.share.PosterShareScaffold
import com.fugaif.imaslivedb.ui.share.ShareCardActionPane
import com.fugaif.imaslivedb.ui.share.ShareCardRatio
import com.fugaif.imaslivedb.ui.share.ShareCardSheet
import com.fugaif.imaslivedb.ui.share.ShareCardSize
import com.fugaif.imaslivedb.ui.share.ShareInk
import com.fugaif.imaslivedb.ui.share.rememberShareCardPalette
import java.util.TimeZone
import uniffi.imas_core.PollCardEntryInput
import uniffi.imas_core.PollCardTarget
import uniffi.imas_core.PollVoteCard
import uniffi.imas_core.PollVoteCardInput
import uniffi.imas_core.PollVotePick
import uniffi.imas_core.pollVoteCard

// =============================================================================
// 自分の投票 (「私の投票」) をシェアする画像。iOS PollVoteShareCard.swift の移植。
// 中身 (見出し・いまの順位・誘いの帯) はコアの pollVoteCard、骨格は結果の画像と同じ。
// =============================================================================

@Composable
fun PollVoteShareSheet(
    detail: CommunityApi.PollDetail,
    songsById: Map<String, Song>,
    idolsById: Map<String, Idol>,
    unitsById: Map<String, ImasUnit>,
    /** 添える本文 (「お題「…」で「A」に投票しました！ #アイドルライブDB」+ URL)。 */
    shareText: String,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    var card by remember { mutableStateOf<PollVoteCard?>(null) }
    var items by remember { mutableStateOf<Map<String, PollResultShareItem>>(emptyMap()) }

    LaunchedEffect(detail) {
        // 締切が未知の値 (Long.MAX_VALUE) は「締切なし」として渡す。
        val endsAt = detail.endsAtMs.takeIf { it != Long.MAX_VALUE }
        val built = pollVoteCard(
            PollVoteCardInput(
                title = detail.title,
                target = when (detail.targetType) {
                    "idol" -> PollCardTarget.IDOL
                    "unit" -> PollCardTarget.UNIT
                    else -> PollCardTarget.SONG
                },
                isActive = detail.isActive,
                endsAtEpochMs = endsAt,
                tzOffsetSeconds = TimeZone.getDefault().getOffset(endsAt ?: System.currentTimeMillis()) / 1000,
                myEntityIds = detail.entries.filter { it.mine }.map { it.entityId },
                entries = detail.entries.map { PollCardEntryInput(it.entityId, it.voteCount.coerceAtLeast(0).toUInt()) }
            )
        )
        val ids = built.picks.map { it.entityId }
        items = resolvePollShareItems(
            context = context,
            targetType = detail.targetType,
            ids = ids,
            imageIds = ids.toSet(),
            songsById = songsById, idolsById = idolsById, unitsById = unitsById
        )
        card = built
    }

    ShareCardSheet(title = "投票をシェア", onDismiss = onDismiss) {
        ShareCardActionPane(
            ratios = listOf(ShareCardRatio.PORTRAIT),
            isPreparingCard = card == null,
            shareText = shareText,
            fileNamePrefix = "poll_vote"
        ) { size ->
            val ready = card
            if (ready != null) {
                PollVoteShareCard(card = ready, items = items, size = size)
            } else {
                Box(Modifier.size(size.widthUnits.dp, size.heightUnits.dp).background(ShareInk.nearBlack))
            }
        }
    }
}

/**
 * 画像: 私の投票。骨格は [PosterShareScaffold] (結果の画像と同じ)。自分の票 (最大 3) を同じ大きさで横に並べ、
 * 絵の角に投票の印 (✓)、名前の下にいまの順位と票数。開催中は下に差し色の帯で「あなたも投票しよう」を刷る
 * (平らな塗り、角は立てる)。焼き込む固定キャンバスなので色は固定色、文字は固定 sp。
 */
@Composable
private fun PollVoteShareCard(card: PollVoteCard, items: Map<String, PollResultShareItem>, size: ShareCardSize) {
    val palette = rememberShareCardPalette(seed = card.picks.firstOrNull()?.let { items[it.entityId]?.seed })
    // 1 つなら大きく、3 つでも横幅 (468dp) に収まる大きさ。
    val side = when (card.picks.size) {
        0, 1 -> 196.dp
        2 -> 168.dp
        else -> 136.dp
    }
    val many = card.picks.size >= 3

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
        // 「わたしの投票」+ 右へ伸びる罫 (チケットの欄の見出しの書き方)。
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 22.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(card.sectionLabel, fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, color = Color.White.copy(alpha = 0.7f))
            Box(Modifier.weight(1f).height(1.dp).background(Color.White.copy(alpha = 0.14f)))
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 18.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.Top
        ) {
            card.picks.forEach { pick -> PickSlot(pick, items[pick.entityId], side, many, palette.accent) }
        }
        card.callToAction?.let { cta ->
            // 開催中だけの誘いの帯。差し色の平らな塗りに黒の文字。
            Row(
                modifier = Modifier.padding(top = 22.dp).fillMaxWidth().heightIn(min = 44.dp).background(palette.accent).padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(cta, fontSize = 15.sp, fontWeight = FontWeight.ExtraBold, color = ShareInk.nearBlack, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.weight(1f))
                Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, tint = ShareInk.nearBlack, modifier = Modifier.size(18.dp))
            }
        }
    }
}

@Composable
private fun PickSlot(pick: PollVotePick, item: PollResultShareItem?, side: androidx.compose.ui.unit.Dp, many: Boolean, accent: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box {
            PollShareVisual(item, side)
            // 絵の左上に重ねる投票の印。差し色の正方形に ✓ (投票用紙のチェック欄)。
            Box(
                Modifier.offset(x = (-6).dp, y = (-6).dp).size(30.dp).background(accent).border(2.dp, ShareInk.nearBlack),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = ShareInk.nearBlack, modifier = Modifier.size(20.dp))
            }
        }
        Text(
            item?.name.orEmpty(), fontSize = if (many) 14.sp else 16.sp, fontWeight = FontWeight.Bold, color = Color.White,
            textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.width(side + 8.dp).height(if (many) 38.dp else 42.dp)
        )
        if (pick.rankLabel.isNotEmpty()) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    pick.rankLabel, fontSize = 20.sp, fontWeight = FontWeight.Black,
                    color = if (pick.rank == 1u) accent else Color.White.copy(alpha = 0.85f)
                )
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("${pick.voteCount}", fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, color = Color.White.copy(alpha = 0.7f))
                    Text("票", fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.5f), modifier = Modifier.padding(bottom = 3.dp))
                }
            }
        }
    }
}
