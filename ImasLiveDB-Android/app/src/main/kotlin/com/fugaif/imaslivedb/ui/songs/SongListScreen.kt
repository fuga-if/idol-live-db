package com.fugaif.imaslivedb.ui.songs

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SearchBar
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Surface
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
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.auth.showEditAffordance
import com.fugaif.imaslivedb.data.auth.startCommunityEdit
import com.fugaif.imaslivedb.data.model.SongCollectFilter
import com.fugaif.imaslivedb.data.model.SongSortOrder
import com.fugaif.imaslivedb.data.model.SongWithArtists
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.CommunityLoginPromptDialog
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasFilterChip
import com.fugaif.imaslivedb.ui.components.ImasListSkeleton
import com.fugaif.imaslivedb.ui.components.ImasRemovableChip
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.components.SkeletonThumb
import com.fugaif.imaslivedb.ui.components.SongRow
import com.fugaif.imaslivedb.ui.components.SongRowMatch
import com.fugaif.imaslivedb.ui.edit.SongEditScreen
import com.fugaif.imaslivedb.ui.tags.TagFilterSheet
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.navigation.TopLevelTab
import com.fugaif.imaslivedb.ui.search.CrossTabCountChips
import com.fugaif.imaslivedb.ui.search.CrossTabSearch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongListScreen(
    onSongClick: (String) -> Unit,
    viewModel: SongListViewModel = viewModel()
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()
    var showFilter by remember { mutableStateOf(false) }
    var showTagFilter by remember { mutableStateOf(false) }
    var showSongCreate by remember { mutableStateOf(false) }
    var showLoginPrompt by remember { mutableStateOf(false) }
    val authState by AppModule.from(context).authService.state.collectAsState()
    // 権限フラグは認証状態が変わった時だけコアへ問い合わせる (詳細は data/auth/EditPermission.kt)。
    val canEditHere = remember(authState) { authState.showEditAffordance }

    LaunchedEffect(Unit) { viewModel.init(context) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("楽曲") },
                actions = {
                    // BAN 済みには導線自体を出さない。未ログインはゲートがログイン誘導へ回す。
                    if (canEditHere) {
                        IconButton(onClick = {
                            authState.startCommunityEdit(
                                promptLogin = { showLoginPrompt = true },
                                present = { showSongCreate = true }
                            )
                        }) {
                            Icon(Icons.Filled.Add, contentDescription = "曲を追加")
                        }
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
                        // 何を絞るかは頭のチップが示すので、プレースホルダは動詞だけでいい。
                        // 「曲名 曲名で検索」と二重に書くと狭い欄が余計に読みにくくなる。
                        placeholder = { Text("絞り込み") },
                        leadingIcon = { SearchModeChip(uiState = uiState, viewModel = viewModel) }
                    )
                },
                expanded = false,
                onExpandedChange = {},
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp)
            ) {}

            ScopeSuggestionBar(uiState = uiState, viewModel = viewModel)
            // 同じ語がアイドル・ライブに何件あるか (虫眼鏡を畳んだ代わりの導線)。
            CrossTabCountChips(query = uiState.searchText, from = TopLevelTab.Songs)
            // 「他のタブに N 件」から飛んで来たら、その語で絞り込む。
            LaunchedEffect(CrossTabSearch.generation) {
                CrossTabSearch.take(TopLevelTab.Songs)?.let { viewModel.setSearchText(it) }
            }

            RemovableFilterChipRow(uiState = uiState, viewModel = viewModel)

            TagFilterErrorBanner(visible = uiState.tagFilterError)

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
                    // 画面に並んでいる行数。あいまい候補も見えている以上、数から外さない。
                    text = when (uiState.listMode) {
                        SongListMode.SONGS -> "${uiState.songs.size + uiState.fuzzySongs.size}件"
                        SongListMode.ALBUMS -> "${uiState.albums.size}枚"
                        SongListMode.SERIES -> "${uiState.series.size}シリーズ"
                    },
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
            } else if (uiState.listMode == SongListMode.ALBUMS) {
                AlbumGrid(albums = uiState.albums, onSelect = viewModel::drillIntoAlbum)
            } else if (uiState.listMode == SongListMode.SERIES) {
                SeriesGrid(series = uiState.series, onSelect = viewModel::drillIntoSeries)
            } else if (uiState.songs.isEmpty() && uiState.fuzzySongs.isEmpty()) {
                ImasEmptyState(
                    icon = Icons.Filled.FilterList,
                    title = if (uiState.searchText.isEmpty()) {
                        "条件に一致する楽曲がありません"
                    } else {
                        "絞り込み結果がありません"
                    },
                    message = if (uiState.searchText.isEmpty()) {
                        "フィルタ条件を変更するか、フィルタを解除してください。"
                    } else {
                        "「${uiState.searchText}」に一致する楽曲がありません"
                    }
                )
            } else {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(uiState.songs, key = { it.song.id }) { item ->
                        SongListRow(item, uiState, viewModel, onSongClick)
                    }
                    if (uiState.fuzzySongs.isNotEmpty()) {
                        item {
                            // 打った通りではない候補なので、区切って理由を書く。黙って下に足すと
                            // 「なぜこの曲が出ているのか」が読めず、一致の精度を疑わせる。
                            ImasSectionHeader(title = "もしかして", tight = true)
                        }
                        // key を分けるのは、同じ曲が両方に出た時に LazyColumn が落ちないため
                        // (VM 側で重複は除いているが、key の衝突は例外になるので保険をかける)。
                        items(uiState.fuzzySongs, key = { "fuzzy_${it.song.id}" }) { item ->
                            SongListRow(item, uiState, viewModel, onSongClick)
                        }
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
            currentListMode = uiState.listMode,
            onDismiss = { showFilter = false },
            onApply = { filter, sort, ascending, showOtherBrand, collectFilter, myMarkFilter, listMode ->
                viewModel.applyFilter(filter, sort, ascending, showOtherBrand, collectFilter, myMarkFilter, listMode)
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

    // 編集フォームはフルスクリーン Dialog に載せる (RecentEditsScreen → SetlistEditScreen と同じ)。
    if (showSongCreate) {
        Dialog(
            onDismissRequest = { showSongCreate = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            SongEditScreen(
                // 1 ブランドに絞り込んでいる時だけ初期値にする (その文脈で追加するのが普通なので)。
                // 複数ブランドを選んでいる時は決め打てないので未指定のまま出す。
                initialBrandId = uiState.filter.brandIds.singleOrNull(),
                onDismiss = { showSongCreate = false },
                onSaved = {
                    showSongCreate = false
                    // admin が即時反映した時に一覧へ載るよう引き直す。修正リクエスト
                    // (一般ユーザー) では DB が変わらないので、結果は同じ一覧になる。
                    viewModel.init(context)
                }
            )
        }
    }

    if (showLoginPrompt) {
        CommunityLoginPromptDialog(
            message = "楽曲の追加にはログインが必要です。",
            onDismiss = { showLoginPrompt = false }
        )
    }
}

/**
 * 一覧の 1 行。確実な一致とあいまい候補 (「もしかして」) で同じ見た目を使う。
 * 候補であることは行ではなく見出しで示すので、行の側は一切変えない。
 */
@Composable
private fun SongListRow(
    item: SongWithArtists,
    uiState: SongListUiState,
    viewModel: SongListViewModel,
    onSongClick: (String) -> Unit
) {
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
        lyricist = item.song.lyricist,
        composer = item.song.composer,
        arranger = item.song.arranger,
        // 何で絞っているかを行に渡す。当たった箇所に色が敷かれ、スコープに応じた補足が出る。
        searchMatch = uiState.searchText.takeIf { it.isNotEmpty() }
            ?.let { SongRowMatch(text = it, scope = uiState.searchMode) },
        onFavoriteToggle = { viewModel.toggleFavorite(item.song.id) },
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onSongClick(item.song.id) }
            .padding(horizontal = 16.dp, vertical = 4.dp)
    )
    HorizontalDivider(modifier = Modifier.padding(start = 68.dp))
}

/**
 * 検索欄の頭に差す 曲名 / アイドル / 作詞作曲 の切り替えチップ (iOS `searchModeChip` 相当)。
 *
 * 全幅のセグメントにすると行を 1 本余分に食う。入力欄の中のチップなら、
 * いま何を探しているかを見せたまま 1 行に収まる。
 *
 * アルバム/シリーズ表示では絞る対象が集計名で固定なので、押せないラベルとして出す
 * (「アイドル」を選べてしまうと、選んでもアルバム名しか絞られず嘘になる)。
 */
@Composable
private fun SearchModeChip(uiState: SongListUiState, viewModel: SongListViewModel) {
    val switchable = uiState.listMode == SongListMode.SONGS
    var expanded by remember { mutableStateOf(false) }

    Surface(
        shape = CircleShape,
        color = DS.fill,
        modifier = Modifier.padding(end = 4.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .clickable(enabled = switchable) { expanded = true }
                .padding(start = 10.dp, end = if (switchable) 2.dp else 10.dp, top = 4.dp, bottom = 4.dp)
        ) {
            Text(
                text = uiState.searchMode.label(uiState.listMode),
                style = MaterialTheme.typography.labelMedium,
                color = DS.ink2,
                maxLines = 1
            )
            if (switchable) {
                Icon(
                    imageVector = Icons.Filled.ArrowDropDown,
                    contentDescription = "検索対象を切り替え",
                    tint = DS.ink2,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            SongSearchMode.entries.forEach { mode ->
                DropdownMenuItem(
                    text = { Text(mode.label(uiState.listMode)) },
                    onClick = {
                        viewModel.setSearchMode(mode)
                        expanded = false
                    }
                )
            }
        }
    }
}

/**
 * 「ほかのスコープにも当たりがある」ことを知らせる行 (iOS `scopeSuggestionBar` 相当)。
 *
 * スコープを混ぜないので結果は常に 1 種類ぶんで、「曲名だけで絞りたかったのに」も
 * 「どれで引っかかったか分からない」も起きない。代わりに見落とす恐れがあるので、
 * 件数だけ出して 1 タップで移れるようにする。
 */
@Composable
private fun ScopeSuggestionBar(uiState: SongListUiState, viewModel: SongListViewModel) {
    if (uiState.otherScopeCounts.isEmpty()) return
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("ほかに", style = MaterialTheme.typography.bodySmall, color = DS.ink3)
        // 並びは enum の宣言順で固定する。件数順にすると打鍵のたびにチップが入れ替わって押し損ねる。
        SongSearchMode.entries.forEach { mode ->
            val count = uiState.otherScopeCounts[mode] ?: return@forEach
            ImasFilterChip(
                label = "${mode.label(uiState.listMode)} ${count}件",
                selected = false,
                onClick = { viewModel.setSearchMode(mode) }
            )
        }
    }
}

/**
 * タグ絞り込みの取得に失敗した (オフライン等) ことを知らせるバナー。
 *
 * 「タグに合致する曲が 0 件」との誤読を避けるため、VM は失敗時に一覧を空にせず
 * 絞り込み自体を見送る。ここでその状態を明示する。
 */
@Composable
private fun TagFilterErrorBanner(visible: Boolean) {
    if (!visible) return
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = Icons.Filled.Warning,
            contentDescription = null,
            tint = DS.warning,
            modifier = Modifier.size(16.dp)
        )
        Text(
            text = "タグ絞り込みの取得に失敗しました。表示中の一覧にはタグ条件が反映されていません。",
            style = MaterialTheme.typography.bodySmall,
            color = DS.ink2
        )
    }
}

/**
 * 適用中フィルタの removable チップ列 (iOS SongListView.removableFilterBar 相当)。
 * マイマーク / 回収 / シートで選んだ絞り込み / 選択中タグ を横スクロールで一覧し、× で個別解除する。
 */
@Composable
private fun RemovableFilterChipRow(uiState: SongListUiState, viewModel: SongListViewModel) {
    val filter = uiState.filter
    // 検索語と同じ軸の条件は、打った語に上書きされている間だけ出さない
    // (VM の withSearch を参照。入力欄とチップに違う値が並ぶのを避ける)。
    val searching = uiState.searchText.isNotEmpty()
    val idolOverridden = searching && uiState.searchMode == SongSearchMode.PERFORMER
    val songwriterOverridden = searching && uiState.searchMode == SongSearchMode.CREATOR
    val hasChips = uiState.myMarkFilter.isActive ||
        uiState.collectFilter != SongCollectFilter.ALL ||
        uiState.selectedTags.isNotEmpty() ||
        !filter.seriesGroup.isNullOrEmpty() ||
        !filter.cdSeries.isNullOrEmpty() ||
        !filter.liveName.isNullOrEmpty() ||
        (!filter.songwriter.isNullOrEmpty() && !songwriterOverridden) ||
        filter.songType != null ||
        (!filter.idolIds.isNullOrEmpty() && !idolOverridden)
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
        if (uiState.myMarkFilter.requireNote) {
            ImasRemovableChip(text = "メモあり", onRemove = viewModel::clearNoteFilter)
        }
        when (uiState.collectFilter) {
            SongCollectFilter.COLLECTED -> ImasRemovableChip(text = "現地回収済", onRemove = viewModel::clearCollectFilter)
            SongCollectFilter.UNCOLLECTED -> ImasRemovableChip(text = "未回収", onRemove = viewModel::clearCollectFilter)
            SongCollectFilter.ALL -> {}
        }
        filter.idolIds?.takeIf { it.isNotEmpty() && !idolOverridden }?.let { ids ->
            // 名前の引き当てはフィルタシート側にしか無いので、チップは人数で出す。
            ImasRemovableChip(
                text = "アイドル ${ids.size}人",
                onRemove = { viewModel.clearFilterField { f -> f.copy(idolIds = null) } }
            )
        }
        filter.songType?.let { type ->
            ImasRemovableChip(
                text = songTypeLabel(type),
                onRemove = { viewModel.clearFilterField { f -> f.copy(songType = null) } }
            )
        }
        filter.seriesGroup?.takeIf { it.isNotEmpty() }?.let { value ->
            ImasRemovableChip(
                text = value,
                onRemove = { viewModel.clearFilterField { f -> f.copy(seriesGroup = null) } }
            )
        }
        filter.cdSeries?.takeIf { it.isNotEmpty() }?.let { value ->
            ImasRemovableChip(
                text = value,
                onRemove = { viewModel.clearFilterField { f -> f.copy(cdSeries = null) } }
            )
        }
        filter.liveName?.takeIf { it.isNotEmpty() }?.let { value ->
            ImasRemovableChip(
                text = value,
                onRemove = { viewModel.clearFilterField { f -> f.copy(liveName = null) } }
            )
        }
        filter.songwriter?.takeIf { it.isNotEmpty() && !songwriterOverridden }?.let { value ->
            ImasRemovableChip(
                text = value,
                onRemove = { viewModel.clearFilterField { f -> f.copy(songwriter = null) } }
            )
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
