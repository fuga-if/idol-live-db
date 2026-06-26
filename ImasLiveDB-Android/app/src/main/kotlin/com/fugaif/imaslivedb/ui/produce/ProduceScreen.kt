package com.fugaif.imaslivedb.ui.produce

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.HowToVote
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.brandColor
import com.fugaif.imaslivedb.ui.theme.hexToColor

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProduceScreen(
    onNavigateToStats: () -> Unit,
    onNavigateToSettings: () -> Unit,
    onNavigateToSearch: () -> Unit,
    onNavigateToPolls: () -> Unit,
    onNavigateToIdol: (String) -> Unit,
    onNavigateToSong: (String) -> Unit,
    viewModel: ProduceViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("プロデュース", fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = onNavigateToSearch) { Icon(Icons.Filled.Search, "検索") }
                    IconButton(onClick = onNavigateToSettings) { Icon(Icons.Filled.Settings, "設定・マイ") }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())
        ) {
            if (state.pickedIdols.isEmpty() && state.favoriteIdols.isEmpty() && state.favoriteSongs.isEmpty()) {
                Text(
                    "アイドルや楽曲の詳細画面で ♥ を押すと、担当・お気に入りがここに並びます",
                    modifier = Modifier.fillMaxWidth().padding(24.dp),
                    color = DS.ink3,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            IdolSection("担当", state.pickedIdols, DS.pick, onNavigateToIdol)
            IdolSection("お気に入りアイドル", state.favoriteIdols, DS.favorite, onNavigateToIdol)
            if (state.favoriteSongs.isNotEmpty()) {
                SectionTitle("お気に入り曲")
                state.favoriteSongs.forEach { song ->
                    SongLine(song) { onNavigateToSong(song.id) }
                }
            }

            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(top = 8.dp))
            HubRow(Icons.Filled.HowToVote, "投票・予想", "タグ・ペンライト・ポール", DS.ink2, onNavigateToPolls)
            HorizontalDivider(color = DS.sep)
            HubRow(Icons.Filled.BarChart, "統計", "ブランド別・年別・ランキング", DS.ink2, onNavigateToStats)
            HorizontalDivider(color = DS.sep)
            HubRow(Icons.Filled.Settings, "設定・マイ", "", DS.ink2, onNavigateToSettings)
        }
    }
}

@Composable
private fun IdolSection(title: String, idols: List<Idol>, accent: Color, onClick: (String) -> Unit) {
    if (idols.isEmpty()) return
    SectionTitle(title)
    LazyRow(
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        items(idols) { idol ->
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.clickable { onClick(idol.id) }.size(width = 64.dp, height = 84.dp)
            ) {
                androidx.compose.foundation.layout.Box(
                    modifier = Modifier.size(48.dp).clip(CircleShape)
                        .background(idol.color?.let { hexToColor(it) } ?: accent)
                )
                Text(
                    idol.name,
                    style = MaterialTheme.typography.labelSmall,
                    color = DS.ink,
                    maxLines = 2,
                    modifier = Modifier.padding(top = 4.dp)
                )
            }
        }
    }
}

@Composable
private fun SongLine(song: Song, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        androidx.compose.foundation.layout.Box(
            modifier = Modifier.size(width = 4.dp, height = 32.dp).clip(CircleShape).background(brandColor(song.brandId))
        )
        Text(
            song.title,
            style = MaterialTheme.typography.bodyMedium,
            color = DS.ink,
            modifier = Modifier.padding(start = 12.dp)
        )
    }
}

@Composable
private fun SectionTitle(title: String) {
    Text(
        title,
        modifier = Modifier.fillMaxWidth().padding(start = 16.dp, top = 16.dp, bottom = 6.dp),
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.Bold,
        color = DS.ink2
    )
}

@Composable
private fun HubRow(icon: ImageVector, title: String, subtitle: String, accent: Color, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, tint = accent, modifier = Modifier.size(22.dp))
        Column(modifier = Modifier.weight(1f).padding(start = 14.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = DS.ink)
            if (subtitle.isNotEmpty()) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = DS.ink3)
            }
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = DS.ink3, modifier = Modifier.size(18.dp))
    }
}
