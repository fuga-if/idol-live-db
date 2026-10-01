package com.fugaif.imaslivedb.ui.sortmaker

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.games.SortMakerSubject
import com.fugaif.imaslivedb.data.games.TierDef
import com.fugaif.imaslivedb.data.games.TierListBoard
import com.fugaif.imaslivedb.di.AppModule
import uniffi.imas_core.tierListAssignFromRanking
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.ui.components.ImasArtwork
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasTheme
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand

// =============================================================================
// 結果: 表彰台 (1〜3 位) + 4 位以下の一覧 + 共有。iOS SortMakerResultView.swift の移植。
// =============================================================================

@Composable
fun SortMakerResultScreen(
    model: SortMakerPlayViewModel,
    state: SortMakerPlayUiState,
    onItemClick: (SortMakerItem) -> Unit,
    onPlayAgain: () -> Unit,
    onOpenTierList: (TierListBoard) -> Unit = {}
) {
    val context = LocalContext.current
    val subject = state.session.subject
    val rows = remember(state) { model.rankedItems() }
    var showShare by rememberSaveable { mutableStateOf(false) }
    var confirmRestart by rememberSaveable { mutableStateOf(false) }

    // ティアー表は何枚でも保存できるので、新しい 1 枚として作る (上書き確認はしない)。
    fun makeTierList() {
        val defaultTiers = TierDef.defaults()
        // 振り分け規則はコア (tierListAssignFromRanking)。ここでは順位を渡すだけ。
        val tierIndices = tierListAssignFromRanking(rows.map { it.first.toUInt() })
        val placements = rows.mapIndexed { i, (_, item) -> item.id to defaultTiers[tierIndices[i].toInt()].id }.toMap()
        val board = TierListBoard(
            subject = subject,
            itemIds = rows.map { it.second.id },
            tiers = defaultTiers,
            placements = placements,
            scopeLabel = state.session.scopeLabel,
            suggested = placements
        )
        AppModule.from(context).tierListStore.save(board)
        onOpenTierList(board)
    }

    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Column {
            Text(
                "あなたの${if (subject == SortMakerSubject.SONG) "好きな曲" else "好きなアイドル"}ランキング",
                fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DS.ink
            )
            Text(
                "${state.session.scopeLabel} · ${state.coreState.answered}戦で決定",
                fontSize = 12.sp, color = DS.ink3
            )
        }

        Podium(rows) { onItemClick(it) }

        if (rows.size > 3) {
            SortMakerRankingList(rows = rows.drop(3), onSelect = { onItemClick(it) })
        }

        Actions(
            canUndo = model.canUndo,
            onShare = { showShare = true },
            onMakeTierList = { makeTierList() },
            onUndoLast = { model.undo() },
            onPlayAgain = { confirmRestart = true }
        )
    }

    if (showShare) {
        SortMakerShareSheet(
            subject = subject,
            scopeLabel = state.session.scopeLabel,
            rows = rows,
            onDismiss = { showShare = false }
        )
    }

    if (confirmRestart) {
        AlertDialog(
            onDismissRequest = { confirmRestart = false },
            title = { Text("この結果を消して、同じ対象でやり直しますか？") },
            confirmButton = {
                Text(
                    "設定に戻ってやり直す",
                    color = DS.warning,
                    modifier = Modifier
                        .clickable {
                            confirmRestart = false
                            AppModule.from(context).sortMakerStore.clear(subject)
                            onPlayAgain()
                        }
                        .padding(12.dp)
                )
            },
            dismissButton = {
                Text("キャンセル", color = DS.ink2, modifier = Modifier.clickable { confirmRestart = false }.padding(12.dp))
            }
        )
    }

}

// MARK: - 表彰台

@Composable
private fun Podium(rows: List<Pair<Int, SortMakerItem>>, onClick: (SortMakerItem) -> Unit) {
    val first = rows.firstOrNull() ?: return
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        PodiumCard(rank = first.first, item = first.second, large = true) { onClick(first.second) }
        val runnersUp = rows.drop(1).take(2)
        if (runnersUp.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                runnersUp.forEach { (rank, item) ->
                    Box(Modifier.weight(1f)) { PodiumCard(rank = rank, item = item, large = false) { onClick(item) } }
                }
                if (runnersUp.size == 1) Box(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun PodiumCard(rank: Int, item: SortMakerItem, large: Boolean, onClick: () -> Unit) {
    val theme = imasThemeForBrand(item.seed, item.brandId)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(if (large) theme.tint else DS.surface)
            .clickable(onClick = onClick)
            .padding(if (large) 24.dp else 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Box {
            PodiumVisual(item, size = if (large) 132.dp else 88.dp)
            Box(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .offset(x = (-8).dp, y = (-8).dp)
                    .size(if (large) 36.dp else 28.dp)
                    .clip(CircleShape)
                    .background(theme.accent),
                contentAlignment = Alignment.Center
            ) {
                Text("$rank", fontSize = if (large) 18.sp else 13.sp, fontWeight = FontWeight.Black, color = theme.onAccent)
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                item.title,
                fontSize = if (large) 19.sp else 15.sp, fontWeight = FontWeight.Bold, color = DS.ink,
                textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            item.subtitle?.let { Text(it, fontSize = 12.sp, color = DS.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
    }
}

@Composable
private fun PodiumVisual(item: SortMakerItem, size: androidx.compose.ui.unit.Dp) {
    when (item) {
        is SortMakerItem.SongItem -> ImasArtwork(title = item.song.title, imageUrl = item.song.artworkUrl, size = size)
        is SortMakerItem.IdolItem -> ImasAvatar(label = item.idol.shortName, seed = item.idol.color, brand = item.idol.brandId, size = size, entityId = item.idol.id)
    }
}

// MARK: - 操作

@Composable
private fun Actions(
    canUndo: Boolean,
    onShare: () -> Unit,
    onMakeTierList: () -> Unit,
    onUndoLast: () -> Unit,
    onPlayAgain: () -> Unit
) {
    val accent = imasTheme(null, null).accent
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(accent)
                .clickable(onClick = onShare)
                .padding(vertical = 16.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Filled.Share, null, tint = DS.surface, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("結果をシェア", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = DS.surface)
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(DS.surface)
                .clickable(onClick = onMakeTierList)
                .padding(vertical = 14.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Filled.Layers, null, tint = DS.ink, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text("この順位でティアー表をつくる", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(DS.surface)
                    .clickable(enabled = canUndo, onClick = onUndoLast)
                    .padding(vertical = 14.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.AutoMirrored.Filled.Undo, null, tint = if (canUndo) DS.ink else DS.ink3, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text("最後の1戦をやり直す", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = if (canUndo) DS.ink else DS.ink3)
            }
            Row(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(DS.surface)
                    .clickable(onClick = onPlayAgain)
                    .padding(vertical = 14.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Filled.Refresh, null, tint = DS.ink, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text("もう一度", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
            }
        }
    }
}
