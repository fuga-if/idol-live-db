package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.EventWithDate
import com.fugaif.imaslivedb.ui.components.BrandColorBar
import com.fugaif.imaslivedb.ui.components.ImasListSkeleton
import com.fugaif.imaslivedb.ui.components.SkeletonThumb
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.BrandFilterItem

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun EventListScreen(
    onEventClick: (String) -> Unit,
    viewModel: EventListViewModel = viewModel()
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(Unit) { viewModel.load(context) }

    Scaffold(
        topBar = {
            TopAppBar(title = { Text("ライブ") })
        }
    ) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding)) {
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
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    text = "${uiState.filteredEvents.size}件",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            HorizontalDivider()

            if (uiState.isLoading) {
                ImasListSkeleton(rows = 10, thumb = SkeletonThumb.None)
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
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp)
    )
}

@Composable
private fun EventRow(
    eventWithDate: EventWithDate,
    onClick: () -> Unit
) {
    val event = eventWithDate.event
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ImasLeadBar(brand = event.brandId, height = 38.dp)

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = event.name,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = DS.ink,
                maxLines = 2,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
            )
            eventWithDate.firstDate?.let { d ->
                Text(text = d, style = MaterialTheme.typography.bodySmall, color = DS.ink2)
            }
        }
    }
}
