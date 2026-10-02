package com.fugaif.imaslivedb.ui.polls

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items as lazyColumnItems
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as lazyGridItems
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.ViewList
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.SongWithArtists
import com.fugaif.imaslivedb.data.model.Vocab
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.BrandFilterItem
import com.fugaif.imaslivedb.ui.designsystem.ImasArtworkCell
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyStateKind
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSearchField
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectableRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasTextFieldRow
import com.fugaif.imaslivedb.ui.tags.TagFilterSheet
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasPress

private enum class SongPickerDisplayMode { GRID, LIST }

/**
 * お題(投票)に新しい候補曲を追加するピッカー。iOS `SongSearchPickerView` の移植。
 * タイトル検索に加えて作詞作曲・曲種別・タグでの絞り込みに対応し、通常の曲一覧と遜色ない検索力を持たせる。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongPollCandidatePicker(
    alreadySelected: Set<String>,
    remaining: Int,
    restrictedBrandIds: Set<String>? = null,
    onDismiss: () -> Unit,
    onConfirm: (List<String>) -> Unit,
    viewModel: SongPollCandidatePickerViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var selection by remember { mutableStateOf(alreadySelected) }
    var query by remember { mutableStateOf("") }
    var songwriter by remember { mutableStateOf("") }
    var selectedBrandId by remember { mutableStateOf<String?>(null) }
    var selectedSongType by remember { mutableStateOf<String?>(null) }
    var selectedTags by remember { mutableStateOf<List<CommunityApi.CommunityTag>>(emptyList()) }
    var showTagFilter by remember { mutableStateOf(false) }
    var showAdvanced by remember { mutableStateOf(false) }
    var displayMode by remember { mutableStateOf(SongPickerDisplayMode.GRID) }

    val brandOptions = remember(state.brands, restrictedBrandIds) {
        if (restrictedBrandIds == null) state.brands else state.brands.filter { it.id in restrictedBrandIds }
    }

    LaunchedEffect(query, songwriter, selectedBrandId, selectedSongType, selectedTags) {
        viewModel.search(
            title = query,
            songwriter = songwriter,
            brandId = selectedBrandId,
            songType = selectedSongType,
            tagIds = selectedTags.map { it.id }
        )
    }

    // BRAND スコープのお題では複数ブランドがまとめて許可されうる (SongSearchFilter は単一 brandId しか
    // 絞り込めないため) ので、取得後にスコープ内ブランドだけへさらに絞る。
    val filtered = remember(state.songs, restrictedBrandIds) {
        if (restrictedBrandIds == null) state.songs else state.songs.filter { it.song.brandId in restrictedBrandIds }
    }
    val grouped = remember(filtered, state.brands) {
        state.brands.mapNotNull { brand ->
            val list = filtered.filter { it.song.brandId == brand.id }
            if (list.isEmpty()) null else brand to list
        }
    }
    val newlyAddedCount = (selection - alreadySelected).size
    val overRemaining = newlyAddedCount > remaining

    fun toggle(song: SongWithArtists) {
        selection = if (selection.contains(song.song.id)) selection - song.song.id else selection + song.song.id
    }

    fun confirm() {
        // 選択は選択肢の表示順 (ブランド順 → 一覧の並び) で返す。
        // 何を入れて何を取り消すか・残りの票数での打ち切りはコア (planVoteSelection)。
        val ordered = state.brands
            .flatMap { brand -> state.songs.filter { it.song.brandId == brand.id } }
            .map { it.song.id }
            .filter { it in selection }
        onConfirm(ordered + (selection - ordered.toSet()))
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            ImasSheetToolbar(
                kind = ImasSheetToolbarKind.Select(
                    canFinish = (selection - alreadySelected).isNotEmpty(),
                    onCancel = onDismiss,
                    onFinish = ::confirm
                ),
                title = "楽曲を選択 (${selection.size})"
            )
            Row(Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen), horizontalArrangement = Arrangement.End) {
                ImasIconButton(
                    icon = Icons.Filled.FilterList,
                    label = "詳細検索",
                    size = ImasIconButtonSize.SMALL,
                    style = if (showAdvanced) ImasIconButtonStyle.TINTED else ImasIconButtonStyle.PLAIN,
                    onClick = { showAdvanced = !showAdvanced }
                )
                ImasIconButton(
                    icon = if (displayMode == SongPickerDisplayMode.GRID) Icons.Filled.ViewList else Icons.Filled.GridView,
                    label = if (displayMode == SongPickerDisplayMode.GRID) "リスト表示" else "グリッド表示",
                    size = ImasIconButtonSize.SMALL,
                    style = ImasIconButtonStyle.PLAIN,
                    onClick = {
                        displayMode = if (displayMode == SongPickerDisplayMode.GRID) SongPickerDisplayMode.LIST else SongPickerDisplayMode.GRID
                    }
                )
            }

            if (brandOptions.size > 1) {
                BrandFilterChips(
                    brands = brandOptions.map { BrandFilterItem(it.id, it.shortName) },
                    selectedBrandId = selectedBrandId,
                    onBrandSelected = { selectedBrandId = it }
                )
            }

            ImasSearchField(
                prompt = "曲名で検索",
                text = query,
                onTextChange = { query = it },
                modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
            )

            if (showAdvanced) {
                ImasTextFieldRow(
                    title = "作詞・作曲・編曲者",
                    text = songwriter,
                    onTextChange = { songwriter = it },
                    modifier = Modifier.padding(horizontal = DS.Space.screen)
                )
                Row(
                    modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight),
                    horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)
                ) {
                    // 絞り込みは先頭の 3 種 (ソロ / ユニット / 全体曲)。語はコアの vocabulary。
                    Vocab.table.songTypes.take(3).forEach { term ->
                        ImasFilterChip(label = term.shortLabel, selected = selectedSongType == term.value,
                            onClick = { selectedSongType = if (selectedSongType == term.value) null else term.value })
                    }
                }
                Row(
                    modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    ImasFilterChip(
                        label = if (selectedTags.isEmpty()) "タグで絞り込み" else selectedTags.joinToString(" ＋ ") { it.name },
                        selected = selectedTags.isNotEmpty(),
                        onClick = { showTagFilter = true }
                    )
                }
            }

            if (overRemaining) {
                ImasNotice(
                    kind = ImasNoticeKind.WARNING,
                    message = "残り${remaining}曲まで選べます (現在+${newlyAddedCount}曲)",
                    modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
                )
            }

            if (state.isLoading) {
                Box(Modifier.fillMaxSize().weight(1f), contentAlignment = Alignment.Center) { ImasLoadingState() }
            } else if (filtered.isEmpty()) {
                Box(Modifier.fillMaxSize().weight(1f), contentAlignment = Alignment.Center) {
                    ImasEmptyState(ImasEmptyStateKind.NO_RESULTS, title = "該当する曲がありません")
                }
            } else if (displayMode == SongPickerDisplayMode.GRID) {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(3),
                    modifier = Modifier.fillMaxWidth().weight(1f).padding(horizontal = DS.Space.gap),
                    contentPadding = PaddingValues(vertical = DS.Space.gap)
                ) {
                    grouped.forEach { (brand, songs) ->
                        item(key = "h_${brand.id}", span = { GridItemSpan(maxLineSpan) }) {
                            ImasSectionHeader(title = "${brand.shortName} (${songs.size})", style = ImasSectionHeaderStyle.SMALL)
                        }
                        lazyGridItems(songs, key = { it.song.id }) { entry ->
                            SongGridCell(entry = entry, isSelected = selection.contains(entry.song.id)) { toggle(entry) }
                        }
                    }
                }
            } else {
                LazyColumn(modifier = Modifier.fillMaxWidth().weight(1f)) {
                    grouped.forEach { (brand, songs) ->
                        item(key = "h_${brand.id}") {
                            ImasSectionHeader(
                                title = "${brand.shortName} (${songs.size})",
                                style = ImasSectionHeaderStyle.SMALL,
                                contentPadding = PaddingValues(horizontal = DS.Space.screen, vertical = DS.Space.header)
                            )
                        }
                        lazyColumnItems(songs, key = { it.song.id }) { entry ->
                            ImasSelectableRow(
                                title = entry.song.title,
                                subtitle = entry.artistNames.takeIf { it.isNotEmpty() },
                                isSelected = selection.contains(entry.song.id),
                                onClick = { toggle(entry) },
                                leading = ImasRowLeading.Artwork(title = entry.song.title, brand = entry.song.brandId, imageUrl = entry.song.artworkUrl)
                            )
                        }
                    }
                }
            }
        }
    }

    if (showTagFilter) {
        TagFilterSheet(
            initialSelection = selectedTags,
            onDismiss = { showTagFilter = false },
            onDone = { selectedTags = it }
        )
    }
}

/** ジャケの格子セル + 選択の印 (ImasArtworkCell に選択印は無いので、ここで重ねる)。 */
@Composable
private fun SongGridCell(entry: SongWithArtists, isSelected: Boolean, onClick: () -> Unit) {
    val song = entry.song
    Box(Modifier.fillMaxWidth().padding(DS.Space.gapTight).imasPress(onClick = onClick)) {
        ImasArtworkCell(title = song.title, brand = song.brandId, imageUrl = song.artworkUrl)
        Icon(
            if (isSelected) Icons.Filled.CheckCircle else Icons.Filled.Circle,
            contentDescription = null,
            tint = if (isSelected) DS.success else DS.ink3,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .size(16.dp)
                .background(DS.bg, CircleShape)
        )
    }
}
