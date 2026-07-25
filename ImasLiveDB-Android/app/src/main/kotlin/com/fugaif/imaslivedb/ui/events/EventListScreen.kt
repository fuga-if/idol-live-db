package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.IconButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.BrandFilterItem
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.components.ImasListSkeleton
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.components.MarkToggleAction
import com.fugaif.imaslivedb.ui.components.SkeletonThumb
import com.fugaif.imaslivedb.ui.theme.DS

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun EventListScreen(
    onEventClick: (String) -> Unit,
    onNavigateToSearch: () -> Unit = {},
    viewModel: EventListViewModel = viewModel()
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()

    var showVenuePicker by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { viewModel.load(context) }

    if (showVenuePicker) {
        VenuePickerSheet(
            directory = uiState.venueDirectory,
            selected = uiState.venue,
            onSelect = { viewModel.selectVenue(context, it) },
            onDismiss = { showVenuePicker = false }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("ライブ") },
                actions = {
                    IconButton(onClick = onNavigateToSearch) {
                        Icon(Icons.Filled.Search, contentDescription = "検索")
                    }
                }
            )
        }
    ) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding)) {
            ImasSegmented(
                labels = listOf("今後の予定", "開催済み"),
                selection = uiState.timeFilter,
                onSelect = { viewModel.selectTimeFilter(it) },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)
            )

            // Brand filter chips
            val brandItems = uiState.brands.map { BrandFilterItem(it.id, it.shortName) }
            BrandFilterChips(
                brands = brandItems,
                selectedBrandId = uiState.selectedBrandId,
                onBrandSelected = { viewModel.selectBrand(it) }
            )

            // "配信を除く" toggle + count
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                FilterChip(
                    selected = uiState.hideStreaming,
                    onClick = { viewModel.toggleHideStreaming() },
                    label = { Text("配信を除く", style = MaterialTheme.typography.labelMedium) },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Filled.VideocamOff,
                            contentDescription = null
                        )
                    }
                )
                Spacer(modifier = Modifier.padding(horizontal = 4.dp))
                // 会場で絞り込む。選択中は会場名を出し、もう一度押すとピッカーを開き直せる。
                FilterChip(
                    selected = uiState.venue != null,
                    onClick = { showVenuePicker = true },
                    label = {
                        Text(
                            uiState.venueDirectory.venue(uiState.venue)?.name ?: "会場",
                            style = MaterialTheme.typography.labelMedium,
                            maxLines = 1
                        )
                    },
                    leadingIcon = {
                        Icon(imageVector = Icons.Filled.Place, contentDescription = null)
                    },
                    trailingIcon = if (uiState.venue != null) {
                        {
                            Icon(
                                imageVector = Icons.Filled.Clear,
                                contentDescription = "会場絞り込みを解除",
                                modifier = Modifier
                                    .size(18.dp)
                                    .clickable { viewModel.selectVenue(context, null) }
                            )
                        }
                    } else {
                        null
                    }
                )
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    text = "${uiState.filteredEvents.size}件",
                    style = MaterialTheme.typography.bodySmall,
                    color = DS.ink2
                )
            }

            HorizontalDivider()

            if (uiState.isLoading) {
                ImasListSkeleton(rows = 10, thumb = SkeletonThumb.None)
            } else if (uiState.groupedByYear.isEmpty()) {
                ImasEmptyState(
                    icon = Icons.Filled.MusicNote,
                    title = if (uiState.timeFilter == 0) "今後の予定はありません" else "開催済みのライブがありません",
                    message = if (uiState.timeFilter == 0) {
                        "現在、登録されている今後のライブはありません。「開催済み」タブもご確認ください。"
                    } else {
                        "開催済みのライブはまだ登録されていません。"
                    }
                )
            } else {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    uiState.groupedByYear.forEach { group ->
                        stickyHeader(key = group.year) {
                            YearSectionHeader(year = group.year)
                        }
                        items(group.events, key = { it.event.id }) { ew ->
                            EventRow(
                                eventWithDate = ew,
                                onClick = { onEventClick(ew.event.id) }
                            )
                            HorizontalDivider(modifier = Modifier.padding(start = 72.dp))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun YearSectionHeader(year: String) {
    Text(
        text = year,
        style = MaterialTheme.typography.labelLarge,
        color = DS.ink2,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp)
    )
}

@Composable
private fun EventRow(
    eventWithDate: EventWithDateRange,
    onClick: () -> Unit
) {
    val event = eventWithDate.event
    val isJoint = event.jointBrandIdList.isNotEmpty()
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ImasLeadBar(brand = event.brandId, height = 38.dp, rainbow = isJoint)

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = event.name,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = DS.ink,
                maxLines = 2,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
            )
            eventWithDate.dateRange?.let { d ->
                Text(text = d, style = MaterialTheme.typography.bodySmall, color = DS.ink2)
            }
        }

        Spacer(modifier = Modifier.width(4.dp))
        MarkToggleAction(
            entityType = UserMark.EVENT,
            entityId = event.id,
            kind = UserMark.FAVORITE,
            activeIcon = Icons.Filled.Star,
            inactiveIcon = Icons.Filled.StarBorder,
            activeTint = DS.favorite,
            contentDescription = "お気に入り"
        )
    }
}
