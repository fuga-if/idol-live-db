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
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
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
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.components.ImasListSkeleton
import com.fugaif.imaslivedb.ui.components.ImasRemovableChip
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.components.MarkToggleAction
import com.fugaif.imaslivedb.ui.components.NameFilterField
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
    var showFilterSheet by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { viewModel.load(context) }

    if (showVenuePicker) {
        VenuePickerSheet(
            directory = uiState.venueDirectory,
            selected = uiState.venue,
            onSelect = { viewModel.selectVenue(context, it) },
            onDismiss = { showVenuePicker = false }
        )
    }

    if (showFilterSheet) {
        EventFilterSheet(
            brands = uiState.brands,
            currentBrandIds = uiState.selectedBrandIds,
            currentExcludedKinds = uiState.excludedKinds,
            currentAttendanceFilter = uiState.attendanceFilter,
            currentRequireFavorite = uiState.requireFavorite,
            currentRequireNote = uiState.requireNote,
            currentShowEmptyEvents = uiState.showEmptyEvents,
            currentHideStreaming = uiState.hideStreaming,
            onDismiss = { showFilterSheet = false },
            onApply = { brandIds, kinds, attendance, favorite, note, showEmpty, hideStreaming ->
                viewModel.applyFilterSheet(brandIds, kinds, attendance, favorite, note, showEmpty, hideStreaming)
                showFilterSheet = false
            }
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
                    BadgedBox(
                        badge = {
                            if (uiState.activeFilterCount > 0) Badge { Text("${uiState.activeFilterCount}") }
                        },
                        modifier = Modifier.padding(end = 8.dp)
                    ) {
                        IconButton(onClick = { showFilterSheet = true }) {
                            Icon(Icons.Filled.FilterList, contentDescription = "フィルター")
                        }
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

            // 一覧そのものを絞る欄。虫眼鏡のシート (横断検索) だと結果がそこで完結してしまい、
            // ブランド絞り込みや期間フィルタと合わせられない。
            NameFilterField(
                prompt = "ライブ名で絞り込み",
                value = uiState.searchText,
                onValueChange = { viewModel.setSearchText(it) }
            )

            ActiveFilterChipRow(
                uiState = uiState,
                viewModel = viewModel,
                onClearVenue = { viewModel.selectVenue(context, null) }
            )

            // 会場チップ + 件数。会場だけは専用ピッカーを開くのでフィルタシートに畳まず一覧に残す。
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
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
                    text = "${uiState.filteredCount}件",
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

/**
 * 適用中フィルタの removable チップ列 (iOS EventListView.activeFilterChips 相当)。
 * ブランド / 除外種別 / 参加状態 / お気に入り / メモ / 空イベント / 会場 / 検索語 を
 * 横スクロールで一覧し、× で個別解除する。
 */
@Composable
private fun ActiveFilterChipRow(
    uiState: EventListUiState,
    viewModel: EventListViewModel,
    onClearVenue: () -> Unit
) {
    val hasChips = uiState.selectedBrandIds.isNotEmpty() ||
        uiState.excludedKinds.isNotEmpty() ||
        uiState.attendanceFilter != "all" ||
        uiState.requireFavorite ||
        uiState.requireNote ||
        uiState.showEmptyEvents ||
        uiState.hideStreaming ||
        uiState.venue != null ||
        uiState.appliedSearchText.isNotEmpty()
    if (!hasChips) return

    val brandNames = remember(uiState.brands) { uiState.brands.associate { it.id to it.shortName } }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (uiState.appliedSearchText.isNotEmpty()) {
            ImasRemovableChip(
                text = "「${uiState.appliedSearchText}」",
                onRemove = viewModel::clearSearchText
            )
        }
        // 並びは選択順でなくソート済みで固定する。押すたびにチップが入れ替わると押し損ねる。
        uiState.selectedBrandIds.sorted().forEach { id ->
            ImasRemovableChip(
                text = brandNames[id] ?: id,
                onRemove = { viewModel.toggleBrand(id) }
            )
        }
        uiState.excludedKinds.sorted().forEach { kind ->
            ImasRemovableChip(
                text = "除外: ${eventKindLabel(kind)}",
                onRemove = { viewModel.removeExcludedKind(kind) }
            )
        }
        when (uiState.attendanceFilter) {
            "attended" -> ImasRemovableChip(text = "参加済み", onRemove = viewModel::clearAttendanceFilter)
            "not_attended" -> ImasRemovableChip(text = "未参加", onRemove = viewModel::clearAttendanceFilter)
            else -> {}
        }
        if (uiState.requireFavorite) {
            ImasRemovableChip(text = "お気に入り", onRemove = viewModel::clearFavoriteFilter)
        }
        if (uiState.requireNote) {
            ImasRemovableChip(text = "メモあり", onRemove = viewModel::clearNoteFilter)
        }
        if (uiState.showEmptyEvents) {
            ImasRemovableChip(text = "空イベントも表示", onRemove = viewModel::clearShowEmptyEvents)
        }
        if (uiState.hideStreaming) {
            ImasRemovableChip(text = "配信を除く", onRemove = viewModel::toggleHideStreaming)
        }
        uiState.venue?.let { venueId ->
            ImasRemovableChip(
                text = uiState.venueDirectory.venue(venueId)?.name ?: venueId,
                onRemove = onClearVenue
            )
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
        ImasLeadBar(brandId = event.brandId, height = 38.dp, rainbow = isJoint)

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
