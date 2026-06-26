package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import com.fugaif.imaslivedb.ui.components.GradientHeader
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.brandColor
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.EventCastRow
import com.fugaif.imaslivedb.data.model.EventStats
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.ui.components.ColorDot
import androidx.compose.ui.platform.LocalContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventDetailScreen(
    eventId: String,
    onBack: () -> Unit,
    onShowClick: (String) -> Unit,
    onIdolClick: (String) -> Unit,
    viewModel: EventDetailViewModel = viewModel(key = eventId)
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(eventId) { viewModel.load(context, eventId) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(uiState.eventName) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { innerPadding ->
        if (uiState.isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
            ) {
                // ブランドグラデ + イベント名 (iOS 詳細ヘッダーに合わせる)
                item {
                    Box(modifier = Modifier.fillMaxWidth()) {
                        GradientHeader(color = brandColor(uiState.brandId), height = 96.dp)
                        Text(
                            uiState.eventName,
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                            color = DS.ink,
                            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 48.dp, bottom = 8.dp)
                        )
                    }
                }
                // Stats section
                uiState.stats?.let { stats ->
                    item {
                        EventStatsSection(stats = stats)
                        HorizontalDivider()
                    }
                }

                // Shows section header
                item {
                    SectionHeader(title = "公演一覧")
                }

                items(uiState.shows, key = { it.id }) { show ->
                    ShowRow(
                        show = show,
                        onClick = { onShowClick(show.id) }
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 16.dp))
                }

                // Cast section
                if (uiState.castMembers.isNotEmpty()) {
                    item {
                        SectionHeader(title = "出演キャスト（${uiState.castMembers.size}名）")
                    }
                    items(uiState.castMembers, key = { it.id }) { member ->
                        CastMemberRow(
                            member = member,
                            onClick = { idolId ->
                                if (idolId != null) onIdolClick(idolId)
                            }
                        )
                        HorizontalDivider(modifier = Modifier.padding(start = 16.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    com.fugaif.imaslivedb.ui.components.ImasSectionHeader(title = title)
}

@Composable
private fun EventStatsSection(stats: EventStats) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically
    ) {
        StatBadge(value = "${stats.showCount}", label = "公演")
        VerticalDivider(modifier = Modifier.height(32.dp))
        StatBadge(value = "${stats.totalSongs}", label = "曲（延べ）")
        VerticalDivider(modifier = Modifier.height(32.dp))
        StatBadge(value = "${stats.uniqueSongs}", label = "ユニーク曲")
        VerticalDivider(modifier = Modifier.height(32.dp))
        StatBadge(value = "${stats.castCount}", label = "キャスト")
    }
}

@Composable
private fun StatBadge(value: String, label: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun ShowRow(show: Show, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(
            text = show.name,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.SemiBold
        )
        Row(modifier = Modifier.fillMaxWidth()) {
            if (show.venue != null) {
                Text(
                    text = show.venue,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = show.date,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun CastMemberRow(
    member: EventCastRow,
    onClick: (String?) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = member.idolId != null) { onClick(member.idolId) }
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        ColorDot(hexColor = member.idolColor, size = 10.dp)

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = member.name,
                style = MaterialTheme.typography.bodyMedium
            )
            if (member.idolName != null) {
                Text(
                    text = member.idolName,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        if (member.idolId != null) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(16.dp)
            )
        }
    }
}
