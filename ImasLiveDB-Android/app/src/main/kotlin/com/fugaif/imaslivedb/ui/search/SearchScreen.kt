package com.fugaif.imaslivedb.ui.search

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.repository.SearchScope
import com.fugaif.imaslivedb.ui.components.ImasArtwork
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * アプリ唯一の検索画面 (iOS `UnifiedSearchView` の移植)。
 *
 * スコープ切替 (すべて/ライブ/楽曲/アイドル) 1 画面に統合し、
 * 検索 = 「探して詳細へ飛ぶ」、フィルタ = 「一覧を絞る」と役割を分ける。
 * 呼び出し元タブに応じた [initialScope] で開く。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(
    onNavigateToIdolDetail: (String) -> Unit,
    onNavigateToSongDetail: (String) -> Unit,
    onNavigateToEventDetail: (String) -> Unit,
    initialScope: SearchScope = SearchScope.ALL,
    viewModel: SearchViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(initialScope) {
        viewModel.setInitialScope(initialScope)
        focusRequester.requestFocus()
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("検索") }) },
        containerColor = DS.bg
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .background(DS.bg)
        ) {
            TextField(
                value = state.query,
                onValueChange = viewModel::setQuery,
                placeholder = { Text(state.scope.prompt, color = DS.ink3) },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null, tint = DS.ink3) },
                trailingIcon = {
                    if (state.query.isNotEmpty()) {
                        IconButton(onClick = { viewModel.setQuery("") }) {
                            Icon(Icons.Filled.Clear, contentDescription = "入力をクリア", tint = DS.ink3)
                        }
                    }
                },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { viewModel.commit() }),
                shape = RoundedCornerShape(50),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = DS.fill,
                    unfocusedContainerColor = DS.fill,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    focusedTextColor = DS.ink,
                    unfocusedTextColor = DS.ink
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .focusRequester(focusRequester)
            )

            ImasSegmented(
                labels = SearchScope.entries.map { it.label },
                selection = SearchScope.entries.indexOf(state.scope),
                onSelect = { viewModel.setScope(SearchScope.entries[it]) },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
            )

            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(top = 8.dp))

            when {
                state.query.isEmpty() -> HistoryList(
                    history = state.history,
                    scope = state.scope,
                    onSelect = viewModel::commit,
                    onRemove = viewModel::removeHistory,
                    onClear = viewModel::clearHistory
                )
                state.isSearching -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                state.visibleResultCount == 0 -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                    ImasEmptyState(
                        icon = Icons.Filled.Search,
                        title = "見つかりません",
                        message = "「${state.query}」に一致する${state.scope.emptyNoun}がありません"
                    )
                }
                else -> ResultList(
                    state = state,
                    onNavigateToIdolDetail = onNavigateToIdolDetail,
                    onNavigateToSongDetail = onNavigateToSongDetail,
                    onNavigateToEventDetail = onNavigateToEventDetail
                )
            }
        }
    }
}

@Composable
private fun HistoryList(
    history: List<String>,
    scope: SearchScope,
    onSelect: (String) -> Unit,
    onRemove: (String) -> Unit,
    onClear: () -> Unit
) {
    if (history.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            ImasEmptyState(
                icon = Icons.Filled.Search,
                title = "検索履歴はありません",
                message = "${scope.emptyNoun}を名前で探せます"
            )
        }
        return
    }
    LazyColumn(Modifier.fillMaxSize().background(DS.bg)) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("最近の検索", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
                Box(Modifier.weight(1f))
                Text(
                    "クリア",
                    fontSize = 12.sp,
                    color = DS.ink2,
                    modifier = Modifier.clickable(onClick = onClear)
                )
            }
        }
        items(history) { item ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(DS.surface)
                    .clickable { onSelect(item) }
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(Icons.Filled.History, contentDescription = null, tint = DS.ink3, modifier = Modifier.size(18.dp))
                Text(item, fontSize = 15.sp, color = DS.ink, modifier = Modifier.weight(1f))
                Icon(
                    Icons.Filled.Clear,
                    contentDescription = "$item を履歴から削除",
                    tint = DS.ink3,
                    modifier = Modifier.size(16.dp).clickable { onRemove(item) }
                )
            }
            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
        }
    }
}

@Composable
private fun ResultList(
    state: SearchUiState,
    onNavigateToIdolDetail: (String) -> Unit,
    onNavigateToSongDetail: (String) -> Unit,
    onNavigateToEventDetail: (String) -> Unit
) {
    LazyColumn(Modifier.fillMaxSize().background(DS.bg)) {
        if (state.scope.includes(SearchScope.IDOLS) && state.results.idols.isNotEmpty()) {
            item { ResultSectionHeader("アイドル", state.results.idols.size) }
            items(state.results.idols) { idol ->
                IdolSearchRow(idol) { onNavigateToIdolDetail(idol.id) }
                HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 44.dp))
            }
        }
        if (state.scope.includes(SearchScope.SONGS) && state.results.songs.isNotEmpty()) {
            item { ResultSectionHeader("楽曲", state.results.songs.size) }
            items(state.results.songs) { song ->
                SongSearchRow(song) { onNavigateToSongDetail(song.id) }
                HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 44.dp))
            }
        }
        if (state.scope.includes(SearchScope.EVENTS) && state.results.events.isNotEmpty()) {
            item { ResultSectionHeader("ライブ", state.results.events.size) }
            items(state.results.events) { event ->
                EventSearchRow(event) { onNavigateToEventDetail(event.id) }
                HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
            }
        }
    }
}

@Composable
private fun ResultSectionHeader(title: String, count: Int) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
        Box(Modifier.weight(1f))
        Text("${count}件", fontSize = 12.sp, color = DS.ink3)
    }
}

@Composable
private fun IdolSearchRow(idol: Idol, onClick: () -> Unit) {
    SearchRow(onClick = onClick, lead = {
        ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 36.dp)
    }, title = idol.name, subtitle = idol.nameKana)
}

@Composable
private fun SongSearchRow(song: Song, onClick: () -> Unit) {
    SearchRow(onClick = onClick, lead = {
        ImasArtwork(title = song.title, brand = song.brandId, size = 36.dp, imageUrl = song.artworkUrl)
    }, title = song.title, subtitle = null)
}

@Composable
private fun EventSearchRow(event: Event, onClick: () -> Unit) {
    SearchRow(onClick = onClick, lead = {
        ImasLeadBar(brand = event.brandId, height = 32.dp)
    }, title = event.name, subtitle = null)
}

/** 検索結果の 1 行。3 種で先頭要素だけ差し替える (行の余白・タイポは共通)。 */
@Composable
private fun SearchRow(
    onClick: () -> Unit,
    lead: @Composable () -> Unit,
    title: String,
    subtitle: String?
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(DS.surface)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        lead()
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, color = DS.ink)
            if (!subtitle.isNullOrEmpty()) {
                Text(subtitle, fontSize = 12.sp, color = DS.ink2)
            }
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = DS.ink3,
            modifier = Modifier.size(16.dp)
        )
    }
}
