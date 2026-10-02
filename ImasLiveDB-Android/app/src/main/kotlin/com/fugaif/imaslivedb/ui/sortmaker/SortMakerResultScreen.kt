package com.fugaif.imaslivedb.ui.sortmaker

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.games.SortMakerSubject
import com.fugaif.imaslivedb.data.games.TierDef
import com.fugaif.imaslivedb.data.games.TierListBoard
import com.fugaif.imaslivedb.di.AppModule
import uniffi.imas_core.tierListAssignFromRanking
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.ui.designsystem.ImasArtwork
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasConfirmDestructive
import com.fugaif.imaslivedb.ui.designsystem.ImasPodium
import com.fugaif.imaslivedb.ui.designsystem.ImasPodiumEntry
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole

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
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(DS.sp5),
        verticalArrangement = Arrangement.spacedBy(DS.sp6)
    ) {
        Column {
            ImasText(
                "あなたの${if (subject == SortMakerSubject.SONG) "好きな曲" else "好きなアイドル"}ランキング",
                ImasTextRole.SECTION_TITLE
            )
            ImasText("${state.session.scopeLabel} · ${state.coreState.answered}戦で決定", ImasTextRole.META)
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

    ImasConfirmDestructive(
        title = "この結果を消して、同じ対象でやり直しますか？",
        isPresented = confirmRestart,
        onDismiss = { confirmRestart = false },
        onConfirm = {
            AppModule.from(context).sortMakerStore.clear(subject)
            onPlayAgain()
        },
        actionTitle = "設定に戻ってやり直す"
    )
}

// MARK: - 表彰台

@Composable
private fun Podium(rows: List<Pair<Int, SortMakerItem>>, onClick: (SortMakerItem) -> Unit) {
    if (rows.isEmpty()) return
    val entries = rows.take(3).mapIndexed { index, (rank, item) ->
        ImasPodiumEntry(
            id = item.id,
            rank = rank,
            title = item.title,
            subtitle = item.subtitle,
            seed = item.seed,
            brand = item.brandId,
            // 絵の大きさは順位の数値でなく並びの位置で決める (先頭だけ大きい)。
            // 同率 1 位が複数いると rank は全部 1 になり、全員分大きい絵が半幅の札に入って潰れるため。
            visual = { PodiumVisual(item, size = if (index == 0) 150.dp else 96.dp) },
            onClick = { onClick(item) }
        )
    }
    ImasPodium(entries = entries)
}

@Composable
private fun PodiumVisual(item: SortMakerItem, size: Dp) {
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
    Column(verticalArrangement = Arrangement.spacedBy(DS.sp3), modifier = Modifier.padding(top = DS.sp3)) {
        ImasButton(
            title = "結果をシェア",
            onClick = onShare,
            icon = Icons.Filled.Share,
            role = ImasButtonRole.PRIMARY,
            size = ImasButtonSize.LARGE,
            fillsWidth = true
        )
        ImasButton(
            title = "この順位でティアー表をつくる",
            onClick = onMakeTierList,
            icon = Icons.Filled.Layers,
            role = ImasButtonRole.SECONDARY,
            size = ImasButtonSize.LARGE,
            fillsWidth = true
        )
        // 半幅の Row だと「最後の1戦をやり直す」が 360dp 幅の端末で切れるため、縦に積んで全幅にする。
        ImasButton(
            title = "最後の1戦をやり直す",
            onClick = onUndoLast,
            icon = Icons.AutoMirrored.Filled.Undo,
            role = ImasButtonRole.SECONDARY,
            size = ImasButtonSize.LARGE,
            fillsWidth = true,
            enabled = canUndo
        )
        ImasButton(
            title = "もう一度",
            onClick = onPlayAgain,
            icon = Icons.Filled.Refresh,
            role = ImasButtonRole.SECONDARY,
            size = ImasButtonSize.LARGE,
            fillsWidth = true
        )
    }
}
