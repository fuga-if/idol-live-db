package com.fugaif.imaslivedb.ui.idols

import com.fugaif.imaslivedb.ui.theme.DS
import androidx.compose.runtime.remember
import uniffi.imas_core.groupIndicesByYearDesc
import com.fugaif.imaslivedb.ui.designsystem.ImasDateHeader
import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Mic
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasCardListStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasShowRow
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.imasRowPress

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
                state.isLoading -> ImasLoadingState(modifier = Modifier.fillMaxSize())
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
                // iOS `IdolSongHistoryView` と同じく半券の行 (`ImasShowRow`)。日付は半券の左に出るので
                // 副題からは外す (下段に重複させない)。題は Android の今の表示名設定 (eventDisplayName) のまま。
                else -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    ImasSectionHeader(title = "披露履歴", count = "${state.history.size}", tight = true)
                    // 年ごとに区切る (半券の日付は月日だけなので、年は見出しで示す)。区切り方はコア。
                    val yearGroups = remember(state.history) { groupIndicesByYearDesc(state.history.map { it.date }) }
                    yearGroups.forEach { group ->
                    ImasDateHeader(big = group.label, modifier = Modifier.padding(horizontal = DS.Space.screen))
                    ImasCardList(items = group.indices.map { state.history[it.toInt()] }, style = ImasCardListStyle.PLAIN, key = { it.showId }) { row ->
                        ImasShowRow(
                            date = row.date,
                            title = AppPreferences.eventDisplayName(row.eventName),
                            subtitle = listOfNotNull(row.venue, row.showName).filter { it.isNotEmpty() }.joinToString(" ・ "),
                            seed = idol?.color,
                            brand = idol?.brandId,
                            showsChevron = true,
                            modifier = Modifier.imasRowPress(onClick = { onShowClick(row.showId) })
                        )
                    }
                    }
                }
            }
        }
    }
}
