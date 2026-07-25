package com.fugaif.imaslivedb.ui.songs

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SearchBar
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.SongCollectFilter
import com.fugaif.imaslivedb.data.model.SongSortOrder
import com.fugaif.imaslivedb.ui.components.ImasListSkeleton
import com.fugaif.imaslivedb.ui.components.ImasRemovableChip
import com.fugaif.imaslivedb.ui.components.SkeletonThumb
import com.fugaif.imaslivedb.ui.components.SongRow
import com.fugaif.imaslivedb.ui.tags.TagFilterSheet
import com.fugaif.imaslivedb.ui.theme.DS

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongListScreen(
    onSongClick: (String) -> Unit,
    onNavigateToSearch: () -> Unit = {},
    viewModel: SongListViewModel = viewModel()
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()
    var showFilter by remember { mutableStateOf(false) }
    var showTagFilter by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { viewModel.init(context) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("楽曲") },
                actions = {
                    IconButton(onClick = onNavigateToSearch) {
                        Icon(Icons.Filled.Search, contentDescription = "検索")
                    }
                    BadgedBox(
                        badge = {
                            if (uiState.selectedTags.isNotEmpty()) {
                                Badge { Text("${uiState.selectedTags.size}") }
                            }
                        },
                        modifier = Modifier.padding(end = 8.dp)
                    ) {
                        IconButton(onClick = { showTagFilter = true }) {
                            Icon(
                                imageVector = Icons.Filled.Sell,
                                contentDescription = "タグで絞り込み"
                            )
                        }
                    }
                    BadgedBox(
                        badge = {
                            if (uiState.filterBadgeCount > 0) {
                                Badge { Text("${uiState.filterBadgeCount}") }
                            }
                        },
                        modifier = Modifier.padding(end = 8.dp)
                    ) {
                        IconButton(onClick = { showFilter = true }) {
                            Icon(
                                imageVector = Icons.Filled.FilterList,
                                contentDescription = "フィルター"
                            )
                        }
                    }
                }
            )
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            // Search bar
            SearchBar(
                inputField = {
                    SearchBarDefaults.InputField(
                        query = uiState.searchText,
                        onQueryChange = { viewModel.setSearchText(it) },
                        onSearch = {},
                        expanded = false,
                        onExpandedChange = {},
                        placeholder = { Text("曲名で検索") }
                    )
                },
                expanded = false,
                onExpandedChange = {},
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp)
            ) {}

            RemovableFilterChipRow(uiState = uiState, viewModel = viewModel)

            // Count + sort control (件数 / 並び替え。タップでフィルタシートを開く)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { showFilter = true }
                    .padding(horizontal = 16.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "${uiState.songs.size}件",
                    style = MaterialTheme.typography.bodySmall,
                    color = DS.ink2
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.Sort,
                        contentDescription = null,
                        tint = DS.ink2,
                        modifier = Modifier.padding(2.dp)
                    )
                    Text(text = uiState.sortOrder.label, style = MaterialTheme.typography.bodySmall, color = DS.ink)
                }
            }

            HorizontalDivider()

            if (uiState.isLoading) {
                ImasListSkeleton(rows = 12, thumb = SkeletonThumb.Square)
            } else {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(uiState.songs, key = { it.song.id }) { item ->
                        SongRow(
                            title = item.song.title,
                            artistNames = item.artistNames,
                            unitName = item.song.unitName,
                            artworkUrl = item.song.artworkUrl,
                            previewUrl = item.song.previewUrl,
                            brandId = item.song.brandId,
                            releaseDate = item.song.releaseDate,
                            isFavorite = uiState.favoriteSongIds.contains(item.song.id),
                            isMyPick = uiState.myPickSongIds.contains(item.song.id),
                            collectedCount = uiState.collectedCounts[item.song.id],
                            tagVoteCount = if (uiState.selectedTags.size == 1) uiState.tagVoteCounts[item.song.id] else null,
                            onFavoriteToggle = { viewModel.toggleFavorite(item.song.id) },
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onSongClick(item.song.id) }
                                .padding(horizontal = 16.dp, vertical = 4.dp)
                        )
                        HorizontalDivider(modifier = Modifier.padding(start = 68.dp))
                    }
                }
            }
        }
    }

    if (showFilter) {
        SongFilterSheet(
            currentFilter = uiState.filter,
            currentSortOrder = uiState.sortOrder,
            currentSortAscending = uiState.sortAscending,
            currentShowOtherBrand = uiState.showOtherBrand,
            currentCollectFilter = uiState.collectFilter,
            currentMyMarkFilter = uiState.myMarkFilter,
            onDismiss = { showFilter = false },
            onApply = { filter, sort, ascending, showOtherBrand, collectFilter, myMarkFilter ->
                viewModel.applyFilter(filter, sort, ascending, showOtherBrand, collectFilter, myMarkFilter)
                showFilter = false
            }
        )
    }

    if (showTagFilter) {
        TagFilterSheet(
            initialSelection = uiState.selectedTags,
            onDismiss = { showTagFilter = false },
            onDone = { viewModel.applyTagFilter(it) }
        )
    }
}

/**
 * 適用中フィルタの removable チップ列 (iOS SongListView.removableFilterBar 相当)。
 * 担当 / お気に入り / 回収済み or 未回収 / 選択中タグ を横スクロールで一覧し、× で個別解除する。
 */
@Composable
private fun RemovableFilterChipRow(uiState: SongListUiState, viewModel: SongListViewModel) {
    val hasChips = uiState.myMarkFilter.requireMyPick ||
        uiState.myMarkFilter.requireFavorite ||
        uiState.collectFilter != SongCollectFilter.ALL ||
        uiState.selectedTags.isNotEmpty()
    if (!hasChips) return

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (uiState.myMarkFilter.requireMyPick) {
            ImasRemovableChip(text = "担当", onRemove = viewModel::clearMyPickFilter)
        }
        if (uiState.myMarkFilter.requireFavorite) {
            ImasRemovableChip(text = "お気に入り", onRemove = viewModel::clearFavoriteFilter)
        }
        when (uiState.collectFilter) {
            SongCollectFilter.COLLECTED -> ImasRemovableChip(text = "現地回収済", onRemove = viewModel::clearCollectFilter)
            SongCollectFilter.UNCOLLECTED -> ImasRemovableChip(text = "未回収", onRemove = viewModel::clearCollectFilter)
            SongCollectFilter.ALL -> {}
        }
        uiState.selectedTags.forEach { tag ->
            val label = if (uiState.selectedTags.size == 1) {
                val count = uiState.tagVoteCounts.keys.size
                if (count > 0) "${tag.name} ${count}曲" else tag.name
            } else {
                tag.name
            }
            ImasRemovableChip(text = label, onRemove = { viewModel.removeTag(tag) })
        }
    }
}

private val SongSortOrder.label: String
    get() = when (this) {
        SongSortOrder.TITLE_KANA -> "五十音順"
        SongSortOrder.RELEASE_DATE -> "リリース日順"
        SongSortOrder.PERFORMANCE_COUNT -> "披露回数順"
        SongSortOrder.COLLECTED_COUNT -> "現地回収回数順"
        SongSortOrder.COLLECTED_RATE -> "回収率順"
    }
