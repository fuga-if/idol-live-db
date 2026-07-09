package com.fugaif.imaslivedb.ui.polls

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.ViewList
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.SongWithArtists
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.BrandFilterItem
import com.fugaif.imaslivedb.ui.components.ImasArtwork
import com.fugaif.imaslivedb.ui.components.ImasFilterChip
import com.fugaif.imaslivedb.ui.tags.TagFilterSheet
import com.fugaif.imaslivedb.ui.theme.DS

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

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "楽曲を選択 (${selection.size})",
                    fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = { showAdvanced = !showAdvanced }) {
                    Icon(Icons.Filled.FilterList, contentDescription = "詳細検索", tint = if (showAdvanced) DS.pick else DS.ink2)
                }
                IconButton(onClick = {
                    displayMode = if (displayMode == SongPickerDisplayMode.GRID) SongPickerDisplayMode.LIST else SongPickerDisplayMode.GRID
                }) {
                    Icon(
                        if (displayMode == SongPickerDisplayMode.GRID) Icons.Filled.ViewList else Icons.Filled.GridView,
                        contentDescription = if (displayMode == SongPickerDisplayMode.GRID) "リスト表示" else "グリッド表示"
                    )
                }
            }

            if (brandOptions.size > 1) {
                BrandFilterChips(
                    brands = brandOptions.map { BrandFilterItem(it.id, it.shortName) },
                    selectedBrandId = selectedBrandId,
                    onBrandSelected = { selectedBrandId = it }
                )
            }

            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text("曲名で検索") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                trailingIcon = {
                    if (query.isNotEmpty()) {
                        IconButton(onClick = { query = "" }) { Icon(Icons.Filled.Clear, contentDescription = "クリア") }
                    }
                },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
            )

            if (showAdvanced) {
                OutlinedTextField(
                    value = songwriter,
                    onValueChange = { songwriter = it },
                    placeholder = { Text("作詞・作曲・編曲者で検索") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
                )
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    ImasFilterChip(label = "ソロ", selected = selectedSongType == "solo",
                        onClick = { selectedSongType = if (selectedSongType == "solo") null else "solo" })
                    ImasFilterChip(label = "ユニット", selected = selectedSongType == "unit",
                        onClick = { selectedSongType = if (selectedSongType == "unit") null else "unit" })
                    ImasFilterChip(label = "全体曲", selected = selectedSongType == "all",
                        onClick = { selectedSongType = if (selectedSongType == "all") null else "all" })
                }
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    ImasFilterChip(
                        label = if (selectedTags.isEmpty()) "タグで絞り込み" else selectedTags.joinToString(" ＋ ") { it.name },
                        selected = selectedTags.isNotEmpty(),
                        onClick = { showTagFilter = true }
                    )
                }
            }

            if (overRemaining) {
                Text(
                    "残り${remaining}曲まで選べます (現在+${newlyAddedCount}曲)",
                    fontSize = 12.sp, color = DS.danger,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp)
                )
            }

            if (state.isLoading) {
                Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            } else if (filtered.isEmpty()) {
                Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                    Text("該当する曲がありません", fontSize = 13.sp, color = DS.ink3)
                }
            } else if (displayMode == SongPickerDisplayMode.GRID) {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(3),
                    modifier = Modifier.fillMaxWidth().weight(1f).padding(horizontal = 12.dp),
                    contentPadding = PaddingValues(vertical = 8.dp)
                ) {
                    grouped.forEach { (brand, songs) ->
                        item(key = "h_${brand.id}", span = { GridItemSpan(maxLineSpan) }) {
                            Text(
                                "${brand.shortName} (${songs.size})",
                                fontSize = 14.sp, fontWeight = FontWeight.Bold, color = DS.ink2,
                                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)
                            )
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
                            Text(
                                "${brand.shortName} (${songs.size})",
                                fontSize = 14.sp, fontWeight = FontWeight.Bold, color = DS.ink2,
                                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)
                            )
                        }
                        lazyColumnItems(songs, key = { it.song.id }) { entry ->
                            SongListRow(entry = entry, isSelected = selection.contains(entry.song.id)) { toggle(entry) }
                        }
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("キャンセル") }
                Button(
                    onClick = {
                        val newIds = (selection - alreadySelected).toList().take(remaining)
                        onConfirm(newIds)
                    },
                    enabled = (selection - alreadySelected).isNotEmpty(),
                    modifier = Modifier.weight(1f)
                ) { Text("決定") }
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

@Composable
private fun SongGridCell(entry: SongWithArtists, isSelected: Boolean, onClick: () -> Unit) {
    val song = entry.song
    Column(
        modifier = Modifier.fillMaxWidth().padding(6.dp).clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(contentAlignment = Alignment.BottomEnd) {
            Box(modifier = Modifier.background(if (isSelected) DS.fill else Color.Transparent, CircleShape)) {
                ImasArtwork(title = song.title, seed = null, brand = song.brandId, size = 56.dp, imageUrl = song.artworkUrl)
            }
            Icon(
                if (isSelected) Icons.Filled.CheckCircle else Icons.Filled.Circle,
                contentDescription = null,
                tint = if (isSelected) DS.success else DS.ink3,
                modifier = Modifier.size(16.dp).background(DS.bg, CircleShape)
            )
        }
        Spacer(Modifier.height(4.dp))
        Text(
            song.title, fontSize = 11.sp, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun SongListRow(entry: SongWithArtists, isSelected: Boolean, onClick: () -> Unit) {
    val song = entry.song
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasArtwork(title = song.title, seed = null, brand = song.brandId, size = 40.dp, imageUrl = song.artworkUrl)
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Text(song.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (entry.artistNames.isNotEmpty()) {
                Text(entry.artistNames, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Icon(
            if (isSelected) Icons.Filled.CheckCircle else Icons.Filled.Circle,
            contentDescription = null,
            tint = if (isSelected) DS.success else DS.ink3
        )
    }
}
