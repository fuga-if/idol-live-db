package com.fugaif.imaslivedb.ui.polls

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.ui.designsystem.ImasArtwork
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasAwardChip
import com.fugaif.imaslivedb.ui.designsystem.ImasCardListStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasMetric
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowChevron
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasRowPress

/**
 * 殿堂 — 終了したお題の優勝曲/アイドル/ユニットを並べる。iOS PollHallOfFameView の移植。
 * 「みんなの投票」で盛り上がった結果を振り返るための画面で、各行から対象の詳細へ抜ける。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PollHallOfFameScreen(
    onBack: () -> Unit,
    onSongClick: (String) -> Unit,
    onIdolClick: (String) -> Unit,
    onUnitClick: (String) -> Unit,
    viewModel: PollHallOfFameViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("殿堂") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                }
            )
        }
    ) { padding ->
        // 空状態・エラーは画面中央に据える。
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            when {
                state.isLoading -> ImasLoadingState()
                state.loadError != null -> ImasEmptyState(
                    icon = Icons.Filled.ErrorOutline,
                    title = "読み込みに失敗しました",
                    message = state.loadError,
                    actionTitle = "再試行",
                    onAction = { viewModel.load() }
                )
                state.rows.isEmpty() -> ImasEmptyState(
                    icon = Icons.Filled.EmojiEvents,
                    title = "まだ優勝者がいません",
                    message = "お題が終了すると、ここに優勝した曲やアイドルが並びます。"
                )
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    // 同じ対象が複数のお題で優勝しうるので、キーは entityId ではなく pollId。
                    itemsIndexed(state.rows, key = { _, row -> row.result.pollId }) { idx, row ->
                        Column(Modifier.fillMaxWidth()) {
                            HallOfFameRowView(
                                row = row,
                                onClick = {
                                    when (row.result.targetType) {
                                        "idol" -> onIdolClick(row.result.entityId)
                                        "unit" -> onUnitClick(row.result.entityId)
                                        else -> onSongClick(row.result.entityId)
                                    }
                                }
                            )
                            if (idx < state.rows.lastIndex) ImasRowDivider(inset = DS.Space.rowH)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun HallOfFameRowView(row: HallOfFameRow, onClick: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .imasRowPress(onClick = onClick)
            .padding(vertical = DS.Space.gapTight),
        verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
    ) {
        ImasAwardChip(title = row.result.title, rank = 1)
        ImasRow(
            title = row.displayName,
            leading = if (row.result.targetType == "song") {
                ImasRowLeading.Artwork(title = row.displayName, imageUrl = row.artworkUrl)
            } else {
                ImasRowLeading.Avatar(label = row.displayName, seed = row.seed, brand = row.brandId)
            },
            trailing = ImasRowTrailing.Custom {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                    ImasMetric(value = "${row.result.voteCount}", unit = "票")
                    ImasRowChevron()
                }
            },
            density = ImasRowDensity.COMPACT
        )
    }
}
