package com.fugaif.imaslivedb.ui.stats

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.ui.components.ImasArtwork
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasRankingRow
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.components.ImasStatBar
import com.fugaif.imaslivedb.ui.components.ImasStatTile
import com.fugaif.imaslivedb.ui.theme.DS

/** 統計。iOS 構造: DB統計タイル + ブランド別/年別 ImasStatBar + 披露/出演 ImasRankingRow。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatsScreen(viewModel: StatsViewModel = viewModel()) {
    val state by viewModel.uiState.collectAsState()

    Scaffold(topBar = { TopAppBar(title = { Text("統計", fontWeight = FontWeight.Bold) }) }) { padding ->
        if (state.isLoading) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        } else {
            Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
                state.databaseStats?.let { db ->
                    Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ImasStatTile(Icons.Filled.LibraryMusic, "${db.songCount}", "楽曲", modifier = Modifier.weight(1f))
                        ImasStatTile(Icons.Filled.Groups, "${db.idolCount}", "アイドル", modifier = Modifier.weight(1f))
                    }
                    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ImasStatTile(Icons.Filled.CalendarMonth, "${db.eventCount}", "イベント", modifier = Modifier.weight(1f))
                        ImasStatTile(Icons.Filled.Mic, "${db.showCount}", "公演", modifier = Modifier.weight(1f))
                    }
                }

                if (state.brandSongCounts.isNotEmpty()) {
                    ImasSectionHeader("ブランド別 楽曲数")
                    val max = state.brandSongCounts.maxOf { it.songCount }.coerceAtLeast(1)
                    state.brandSongCounts.forEach { b ->
                        ImasStatBar(b.shortName, "${b.songCount}", b.songCount * 100.0 / max, seed = b.color, brand = b.id)
                    }
                }

                if (state.yearlyShowCounts.isNotEmpty()) {
                    ImasSectionHeader("年別 公演数")
                    val max = state.yearlyShowCounts.maxOf { it.showCount }.coerceAtLeast(1)
                    state.yearlyShowCounts.forEach { y ->
                        ImasStatBar(y.year, "${y.showCount}", y.showCount * 100.0 / max)
                    }
                }

                if (state.songPlayCounts.isNotEmpty()) {
                    ImasSectionHeader("披露回数ランキング")
                    state.songPlayCounts.forEachIndexed { i, s ->
                        ImasRankingRow(rank = i + 1, title = s.title, metric = "${s.playCount}", brand = s.brandId) {
                            ImasArtwork(title = s.title, brand = s.brandId, size = 44.dp)
                        }
                    }
                }

                if (state.castShowCounts.isNotEmpty()) {
                    ImasSectionHeader("出演公演数ランキング")
                    state.castShowCounts.forEachIndexed { i, c ->
                        ImasRankingRow(rank = i + 1, title = c.name, metric = "${c.showCount}", unit = "公演") {
                            ImasAvatar(label = c.name, size = 44.dp)
                        }
                    }
                }
                Box(Modifier.size(24.dp).background(DS.bg))
            }
        }
    }
}
