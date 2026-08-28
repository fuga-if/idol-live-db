package com.fugaif.imaslivedb.ui.idols

import android.app.Application
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
import androidx.compose.material.icons.filled.Mic
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.songs.eventDisplayName
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * アイドル × 曲 の披露履歴 (iOS `IdolSongHistoryView` の移植)。
 *
 * アイドル詳細の「ライブ歌唱曲」から開く。曲詳細へ飛ばすと「この人がこの曲を歌った公演」が
 * 全披露履歴に埋もれてしまうので、本人ぶんだけを並べる画面を分けてある。
 * 配色シードは本人のイメージカラー — 誰の履歴を見ているかを色でも示す。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IdolSongHistoryScreen(
    idolId: String,
    songId: String,
    onBack: () -> Unit,
    onShowClick: (String) -> Unit,
    viewModel: IdolSongHistoryViewModel = viewModel(
        key = "$idolId/$songId",
        factory = IdolSongHistoryViewModel.Factory(
            LocalContext.current.applicationContext as Application, idolId, songId
        )
    )
) {
    val state by viewModel.uiState.collectAsState()
    val idol = state.idol
    val song = state.song

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        listOfNotNull(idol?.name, song?.title).joinToString(" × "),
                        maxLines = 1, overflow = TextOverflow.Ellipsis
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when {
                state.isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                state.history.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    ImasEmptyState(
                        icon = Icons.Filled.Mic,
                        title = "披露履歴がありません",
                        message = listOfNotNull(idol?.name, song?.title)
                            .takeIf { it.size == 2 }
                            ?.let { "${it[0]} による「${it[1]}」の披露記録はありません" },
                        seed = idol?.color, brand = idol?.brandId
                    )
                }
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    item(key = "header") {
                        ImasSectionHeader(title = "披露履歴", count = "${state.history.size}", tight = true)
                    }
                    items(state.history, key = { it.showId }) { row ->
                        HistoryRow(row, seed = idol?.color, brand = idol?.brandId) { onShowClick(row.showId) }
                        HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun HistoryRow(row: CastShowRow, seed: String?, brand: String?, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ImasLeadBar(seedHex = seed, brandId = brand, height = 38.dp)
        Column(Modifier.weight(1f)) {
            Text(
                AppPreferences.eventDisplayName(row.eventName),
                fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            val sub = listOfNotNull(row.date, row.venue, row.showName)
                .filter { it.isNotEmpty() }
                .joinToString(" ・ ")
            if (sub.isNotEmpty()) {
                Text(sub, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight, null,
            tint = DS.ink3, modifier = Modifier.size(16.dp)
        )
    }
}
