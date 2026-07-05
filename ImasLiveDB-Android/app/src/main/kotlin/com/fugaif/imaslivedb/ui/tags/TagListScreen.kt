package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.ui.theme.DS

private val SORT_OPTIONS = listOf("popular" to "人気", "recent" to "新着", "name" to "名前")

/** タグ一覧。iOS TagListView の移植 (人気/新着/名前順 + カテゴリ絞り込み + 新規作成)。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagListScreen(
    onBack: () -> Unit,
    onTagClick: (String) -> Unit,
    onSongClick: (String) -> Unit,
    viewModel: TagListViewModel = viewModel()
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()
    var showCreateSheet by remember { mutableStateOf(false) }
    var showCategoryMenu by remember { mutableStateOf(false) }
    var showSortMenu by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { viewModel.init(context) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("タグ") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                actions = {
                    Box {
                        IconButton(onClick = { showSortMenu = true }) {
                            Icon(Icons.Filled.Sort, contentDescription = "並び順")
                        }
                        DropdownMenu(expanded = showSortMenu, onDismissRequest = { showSortMenu = false }) {
                            SORT_OPTIONS.forEach { (value, label) ->
                                DropdownMenuItem(text = { Text(label) }, onClick = {
                                    viewModel.setSort(value)
                                    showSortMenu = false
                                })
                            }
                        }
                    }
                    Box {
                        BadgedBox(badge = {
                            if (uiState.activeFilterCount > 0) Badge { Text("${uiState.activeFilterCount}") }
                        }) {
                            IconButton(onClick = { showCategoryMenu = true }) {
                                Icon(Icons.Filled.FilterList, contentDescription = "カテゴリで絞り込み")
                            }
                        }
                        DropdownMenu(expanded = showCategoryMenu, onDismissRequest = { showCategoryMenu = false }) {
                            TAG_CATEGORIES.forEach { (value, label) ->
                                DropdownMenuItem(text = { Text(label) }, onClick = {
                                    viewModel.setCategory(value)
                                    showCategoryMenu = false
                                })
                            }
                        }
                    }
                    IconButton(onClick = { showCreateSheet = true }) {
                        Icon(Icons.Filled.Add, contentDescription = "新規タグ作成")
                    }
                }
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when {
                uiState.isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                uiState.tags.isEmpty() -> Text(
                    "タグはまだありません", color = DS.ink2,
                    modifier = Modifier.align(Alignment.Center)
                )
                else -> LazyColumn(modifier = Modifier.fillMaxSize()) {
                    itemsIndexed(uiState.tags, key = { _, tag -> tag.id }) { idx, tag ->
                        val rank = if (uiState.sort == "popular") idx + 1 else null
                        TagListRow(
                            tag = tag, rank = rank,
                            modifier = Modifier.fillMaxWidth().clickable { onTagClick(tag.id) }
                                .padding(horizontal = 16.dp, vertical = 10.dp)
                        )
                        HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                    }
                }
            }
        }
    }

    if (showCreateSheet) {
        TagCreateSheet(
            onDismiss = { showCreateSheet = false },
            onCreated = { viewModel.prependCreatedTag(it) }
        )
    }
}

@Composable
private fun TagListRow(tag: CommunityApi.CommunityTag, rank: Int?, modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (rank != null) TagRankBadge(rank)
            TagColorDot(tag.color)
            Text(tag.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
            if (!tag.category.isNullOrEmpty()) {
                Text(
                    tagCategoryLabel(tag.category), fontSize = 11.sp, color = DS.ink2,
                    modifier = Modifier.padding(horizontal = 2.dp)
                )
            }
            Box(Modifier.weight(1f))
            if (tag.totalUses > 0) {
                Text("${tag.totalUses}曲", fontSize = 12.sp, color = DS.ink2)
            }
        }
        if (!tag.description.isNullOrEmpty()) {
            Text(
                tag.description, fontSize = 12.sp, color = DS.ink2, maxLines = 1,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp)
            )
        }
    }
}
