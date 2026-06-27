package com.fugaif.imaslivedb.ui.songs

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.CircularProgressIndicator
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
import com.fugaif.imaslivedb.ui.components.ImasListSkeleton
import com.fugaif.imaslivedb.ui.components.SkeletonThumb
import com.fugaif.imaslivedb.ui.components.SongRow

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongListScreen(
    onSongClick: (String) -> Unit,
    viewModel: SongListViewModel = viewModel()
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()
    var showFilter by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { viewModel.init(context) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("楽曲") },
                actions = {
                    BadgedBox(
                        badge = {
                            if (uiState.activeFilterCount > 0) {
                                Badge { Text("${uiState.activeFilterCount}") }
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

            // Count label
            Text(
                text = "${uiState.songs.size}件 ／ ${uiState.sortOrder.label}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
            )

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
            onDismiss = { showFilter = false },
            onApply = { filter, sort ->
                viewModel.applyFilter(filter, sort)
                showFilter = false
            }
        )
    }
}

private val com.fugaif.imaslivedb.data.model.SongSortOrder.label: String
    get() = when (this) {
        com.fugaif.imaslivedb.data.model.SongSortOrder.TITLE_KANA -> "五十音順"
        com.fugaif.imaslivedb.data.model.SongSortOrder.RELEASE_DATE -> "リリース日順"
        com.fugaif.imaslivedb.data.model.SongSortOrder.PERFORMANCE_COUNT -> "披露回数順"
    }
