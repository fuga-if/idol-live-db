package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.background
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
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.ui.components.NameFilterField
import com.fugaif.imaslivedb.ui.designsystem.ImasBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasContentState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyStateKind
import com.fugaif.imaslivedb.ui.designsystem.ImasListBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasRankBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSkeletonKind
import com.fugaif.imaslivedb.ui.designsystem.ImasStateContainer
import com.fugaif.imaslivedb.ui.designsystem.ImasSwatch
import com.fugaif.imaslivedb.ui.designsystem.ImasSwatchSize
import com.fugaif.imaslivedb.ui.designsystem.ImasToolbarButton
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress

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
                        ImasToolbarButton(icon = Icons.Filled.Sort, label = "並び順", onClick = { showSortMenu = true })
                        DropdownMenu(expanded = showSortMenu, onDismissRequest = { showSortMenu = false }) {
                            SORT_OPTIONS.forEach { (value, label) ->
                                DropdownMenuItem(text = { Text(label, color = DS.ink) }, onClick = {
                                    viewModel.setSort(value)
                                    showSortMenu = false
                                })
                            }
                        }
                    }
                    Box {
                        ImasToolbarButton(
                            icon = Icons.Filled.FilterList,
                            label = "カテゴリで絞り込み",
                            badge = uiState.activeFilterCount,
                            onClick = { showCategoryMenu = true }
                        )
                        DropdownMenu(expanded = showCategoryMenu, onDismissRequest = { showCategoryMenu = false }) {
                            TAG_CATEGORIES.forEach { (value, label) ->
                                DropdownMenuItem(text = { Text(label, color = DS.ink) }, onClick = {
                                    viewModel.setCategory(value)
                                    showCategoryMenu = false
                                })
                            }
                        }
                    }
                    ImasToolbarButton(icon = Icons.Filled.Add, label = "新規タグ作成", onClick = { showCreateSheet = true })
                }
            )
        }
    ) { padding ->
        ImasListBackdrop(modifier = Modifier.fillMaxSize().padding(padding)) {
            Column(Modifier.fillMaxSize()) {
                NameFilterField(
                    prompt = "タグ名で絞り込み",
                    value = uiState.nameFilter,
                    onValueChange = { viewModel.setNameFilter(it) }
                )
                val tags = uiState.visibleTags
                val state = when {
                    uiState.isLoading -> ImasContentState.Loading
                    tags.isEmpty() -> ImasContentState.Empty
                    else -> ImasContentState.Loaded
                }
                ImasStateContainer(
                    state = state,
                    modifier = Modifier.fillMaxSize(),
                    skeleton = ImasSkeletonKind.List(),
                    empty = {
                        // 「まだ 1 つも無い」と「絞り込んで 0 件」を言い分ける。
                        if (uiState.nameFilter.isEmpty()) {
                            ImasEmptyState(icon = Icons.Filled.Sell, title = "タグはまだありません")
                        } else {
                            ImasEmptyState(
                                ImasEmptyStateKind.NO_RESULTS,
                                title = "「${uiState.nameFilter}」に一致するタグがありません"
                            )
                        }
                    }
                ) {
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        itemsIndexed(tags, key = { _, tag -> tag.id }) { idx, tag ->
                            val rank = if (uiState.sort == "popular") idx + 1 else null
                            Column(Modifier.fillMaxWidth()) {
                                TagListRow(tag = tag, rank = rank, onClick = { onTagClick(tag.id) })
                                if (idx < tags.lastIndex) ImasRowDivider(inset = DS.Space.rowH)
                            }
                        }
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

/** タグ 1 件の行 (人気ソート時だけ先頭に小さい順位の札)。 */
@Composable
private fun TagListRow(tag: CommunityApi.CommunityTag, rank: Int?, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(DS.surface)
            .imasRowPress(onClick = onClick),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (rank != null) ImasRankBadge(rank)
        ImasRow(
            title = tag.name,
            // 前は行数制限なし。
            titleLineLimit = Int.MAX_VALUE,
            modifier = Modifier.weight(1f),
            subtitle = tag.description?.takeIf { it.isNotEmpty() },
            leading = tag.color?.let { hex ->
                ImasRowLeading.Custom(width = ImasSwatchSize.SMALL.diameter) { ImasSwatch(hex, size = ImasSwatchSize.SMALL) }
            } ?: ImasRowLeading.None,
            trailing = ImasRowTrailing.Custom {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight), verticalAlignment = Alignment.CenterVertically) {
                    if (!tag.category.isNullOrEmpty()) {
                        ImasBadge(tagCategoryLabel(tag.category), kind = ImasBadgeKind.NEUTRAL)
                    }
                    if (tag.totalUses > 0) {
                        Text("${tag.totalUses}曲", style = ImasTextRole.META.style, color = ImasTextRole.META.color)
                    }
                }
            },
            density = ImasRowDensity.COMPACT,
            titleAccessibilityLabel = "タグ: ${tag.name}"
        )
    }
}
