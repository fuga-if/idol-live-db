package com.fugaif.imaslivedb.ui.polls

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.ui.components.ImasArtwork
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.theme.DS

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
                title = { Text("殿堂", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                }
            )
        }
    ) { padding ->
        // 空状態・エラーは画面中央に据える (ImasEmptyState は modifier を取らないので Box 側で寄せる)。
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            when {
                state.isLoading -> CircularProgressIndicator()
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
                    items(state.rows, key = { it.result.pollId }) { row ->
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
                        HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun HallOfFameRowView(row: HallOfFameRow, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp)
    ) {
        // 曲はジャケ写、アイドル/ユニットはモノグラム。「実写優先」の一覧デザインに揃える。
        if (row.result.targetType == "song") {
            ImasArtwork(title = row.displayName, size = 44.dp, imageUrl = row.artworkUrl)
        } else {
            ImasAvatar(label = row.displayName, seed = row.seed, brand = row.brandId, size = 44.dp)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                row.result.title, fontSize = 12.sp, color = DS.ink3,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            Text(
                row.displayName, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Filled.EmojiEvents, contentDescription = null,
                    tint = DS.warning, modifier = Modifier.size(14.dp)
                )
                Text(
                    "優勝", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = DS.warning,
                    modifier = Modifier.padding(start = 3.dp)
                )
            }
            Text("${row.result.voteCount}票", fontSize = 12.sp, color = DS.ink3)
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
            tint = DS.ink3, modifier = Modifier.size(16.dp)
        )
    }
}
