package com.fugaif.imaslivedb.ui.songs

import com.fugaif.imaslivedb.ui.theme.MasteryPalette
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeAction
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipe
import com.fugaif.imaslivedb.ui.designsystem.ReadableWidth
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
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
import com.fugaif.imaslivedb.ui.designsystem.ImasChipRow
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterBar
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterBarItem
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasListSkeleton
import com.fugaif.imaslivedb.ui.designsystem.ImasListSummary
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasScopeChip
import com.fugaif.imaslivedb.ui.designsystem.ImasSearchField
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasToolbarButton
import com.fugaif.imaslivedb.ui.designsystem.SkeletonThumb
import com.fugaif.imaslivedb.ui.components.SongRow
import com.fugaif.imaslivedb.ui.components.SongRowMatch
import com.fugaif.imaslivedb.ui.edit.SongEditScreen
import com.fugaif.imaslivedb.ui.tags.TagFilterSheet
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.navigation.TopLevelTab
import com.fugaif.imaslivedb.ui.search.CrossTabCountChips
import com.fugaif.imaslivedb.ui.search.CrossTabSearch
import uniffi.imas_core.kamisabiCompletionLabel
import uniffi.imas_core.SearchMatchRowInput
import uniffi.imas_core.SearchMatchScope
import uniffi.imas_core.searchMatchTexts

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
    // 行の左スワイプ「プレイリスト」で足す曲 (null = シートを出さない)。
    var playlistTarget by remember { mutableStateOf<com.fugaif.imaslivedb.data.model.Song?>(null) }
    // 長押しで習熟度を付け替える対象の曲 (null = ピッカーを出さない)。
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
                        ImasToolbarButton(
                            icon = Icons.Filled.Add,
                            label = "曲を追加",
                            onClick = {
                                authState.startCommunityEdit(
                                    promptLogin = { showLoginPrompt = true },
                                    present = { showSongCreate = true }
                                )
                            }
                        )
                    }
                    ImasToolbarButton(
                        icon = Icons.Filled.Sell,
                        label = "タグで絞り込み",
                        badge = uiState.selectedTags.size,
                        onClick = { showTagFilter = true }
                    )
                    ImasToolbarButton(
                        icon = Icons.Filled.FilterList,
                        label = "フィルター",
                        badge = uiState.filterBadgeCount,
                        onClick = { showFilter = true }
                    )
                }
            )
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            ImasSearchField(
                // 何を絞るかは頭の札が示すので、プレースホルダは動詞だけでいい。
                // 「曲名 曲名で検索」と二重に書くと狭い欄が余計に読みにくくなる。
                prompt = "絞り込み",
                text = uiState.searchText,
                onTextChange = { viewModel.setSearchText(it) },
                leading = { SearchModeChip(uiState = uiState, viewModel = viewModel) },
                modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
            )

            ScopeSuggestionBar(uiState = uiState, viewModel = viewModel)
            // 同じ語がアイドル・ライブに何件あるか (虫眼鏡を畳んだ代わりの導線)。
            CrossTabCountChips(query = uiState.searchText, from = TopLevelTab.Songs)
            // 「他のタブに N 件」から飛んで来たら、その語で絞り込む。
            LaunchedEffect(CrossTabSearch.generation) {
                CrossTabSearch.take(TopLevelTab.Songs)?.let { viewModel.setSearchText(it) }
            }

            ImasFilterBar(items = filterBarItems(uiState, viewModel))

            TagFilterErrorBanner(visible = uiState.tagFilterError)
            KamisabiCompletionBanner(uiState = uiState)

            // 件数 / 並び替え。並び替えはその場のメニューで切り替える。
            // フィルタシートを開かせると、並びだけ変えたい時に絞り込み全体を掻き分けることになる。
            ImasListSummary(
                count = when (uiState.listMode) {
                    SongListMode.SONGS -> uiState.songs.size + uiState.fuzzySongs.size
                    SongListMode.ALBUMS -> uiState.albums.size
                    SongListMode.SERIES -> uiState.series.size
                },
                unit = when (uiState.listMode) {
                    SongListMode.SONGS -> "件"
                    SongListMode.ALBUMS -> "枚"
                    SongListMode.SERIES -> "シリーズ"
                },
                sortOptions = SongSortOrder.entries,
                sortSelection = uiState.sortOrder,
                onSortChange = viewModel::setSortOrder,
                sortLabel = { it.label },
                sortAscending = uiState.sortAscending ?: uiState.sortOrder.defaultAscending,
                onSortAscendingChange = viewModel::setSortAscending
            )
            ImasRowDivider()

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
                // 歌唱・作詞作曲で絞っているときの「なぜ出ているか」の説明は、画面の行ぶんを
                // コアで 1 回に作る (行ごとに呼ばない)。
                val matchDetails = remember(uiState.songs, uiState.fuzzySongs, uiState.searchText, uiState.searchMode) {
                    searchMatchDetails(uiState.songs + uiState.fuzzySongs, uiState.searchText, uiState.searchMode)
                }
                // 広い画面では本文幅を抑える (iOS の readableContentMargins と対)。
                ReadableWidth { readable ->
                    LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = readable) {
                        items(uiState.songs, key = { it.song.id }) { item ->
                            SongListRow(item, uiState, matchDetails[item.song.id], viewModel, onSongClick) {
                                playlistTarget = item.song
                            }
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
                                SongListRow(item, uiState, matchDetails[item.song.id], viewModel, onSongClick) {
                                    playlistTarget = item.song
                                }
                            }
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

    playlistTarget?.let { song ->
        Dialog(onDismissRequest = { playlistTarget = null }) {
            com.fugaif.imaslivedb.ui.playlists.AddToPlaylistSheet(
                song = song,
                onDismiss = { playlistTarget = null }
            )
        }
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
    matchDetail: String?,
    viewModel: SongListViewModel,
    onSongClick: (String) -> Unit,
    onAddToPlaylist: () -> Unit
) {
    // 行を引いて習熟度を付ける (iOS `MasterySwipeActions` と同じ)。左に引くと段が並び、最上段が
    // 画面の端 (指の届く位置) に来る。右に引くと「未設定」に戻す。長押しのメニューは一覧に付けない
    // (スクロールの途中の指を長押しと取り違え、一覧を流す邪魔になるため)。
    val scale = uiState.masteryScale
    val levels = remember(scale) { (1..scale.steps.toInt()).map { it.toUByte() } }
    ImasSwipe(
        leading = listOf(
            ImasSwipeAction(kind = ImasSwipeKind.UNDO, title = "未設定") { viewModel.setMastery(item.song.id, 0u) },
            ImasSwipeAction(kind = ImasSwipeKind.PLAYLIST, title = "プレイリスト") { onAddToPlaylist() }
        ),
        trailing = levels.map { level ->
            ImasSwipeAction(
                kind = ImasSwipeKind.MEMO,
                title = scale.swipeLabel(level),
                id = "mastery_$level",
                showsIcon = false,
                tint = MasteryPalette.fill(level, scale.steps)
            ) { viewModel.setMastery(item.song.id, level) }
        },
        allowsFullSwipe = false
    ) {
    SongRow(
        title = item.song.title, songId = item.song.id,
        artistNames = item.artistNames,
        singerLabel = item.song.singerLabel,
        unitName = item.song.unitName,
        artworkUrl = item.song.artworkUrl,
        previewUrl = item.song.previewUrl,
        brandId = item.song.brandId,
        releaseDate = item.song.releaseDate,
        isMyPick = uiState.myPickSongIds.contains(item.song.id),
        collectedCount = uiState.collectedCounts[item.song.id],
        masteryLevel = uiState.masteryLevels[item.song.id] ?: 0u,
        masteryScale = uiState.masteryScale,
        tagVoteCount = if (uiState.selectedTags.size == 1) uiState.tagVoteCounts[item.song.id] else null,
        // 何で絞っているかを行に渡す。当たった箇所に色が敷かれ、スコープに応じた補足が出る。
        searchMatch = uiState.searchText.takeIf { it.isNotEmpty() }
            ?.let { SongRowMatch(text = it, scope = uiState.searchMode, detail = matchDetail) },
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onSongClick(item.song.id) }
            .padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
    )
    }
    // 68dp = 画面の余白 + 行頭のジャケ写の幅ぶん (SongRow 自身の余白と揃える)。
    ImasRowDivider(inset = DS.sp5 + 52.dp)
}

/**
 * 検索欄の頭に差す 曲名 / アイドル / 作詞作曲 の切り替えの札 (iOS `searchModeChip` 相当)。
 *
 * 全幅のセグメントにすると行を 1 本余分に食う。入力欄の中の札なら、
 * いま何を探しているかを見せたまま 1 行に収まる。
 *
 * アルバム/シリーズ表示では絞る対象が集計名で固定なので、押せない札として出す
 * (「アイドル」を選べてしまうと、選んでもアルバム名しか絞られず嘘になる)。
 */
@Composable
private fun SearchModeChip(uiState: SongListUiState, viewModel: SongListViewModel) {
    val switchable = uiState.listMode == SongListMode.SONGS
    var expanded by remember { mutableStateOf(false) }

    Box {
        ImasScopeChip(
            label = uiState.searchMode.label(uiState.listMode),
            enabled = switchable,
            onClickLabel = "検索対象を切り替え",
            onClick = { expanded = true }
        )
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
 * 「ほかのスコープにも当たりがある」ことを知らせる札の列 (iOS `scopeSuggestionBar` 相当)。
 *
 * スコープを混ぜないので結果は常に 1 種類ぶんで、「曲名だけで絞りたかったのに」も
 * 「どれで引っかかったか分からない」も起きない。代わりに見落とす恐れがあるので、
 * 件数だけ出して 1 タップで移れるようにする。
 */
@Composable
private fun ScopeSuggestionBar(uiState: SongListUiState, viewModel: SongListViewModel) {
    if (uiState.otherScopeCounts.isEmpty()) return
    ImasChipRow(modifier = Modifier.padding(vertical = DS.Space.gapTight)) {
        ImasText("ほかに", ImasTextRole.META, color = DS.ink3)
        // 並びは enum の宣言順で固定する。件数順にすると打鍵のたびに札が入れ替わって押し損ねる。
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
 * タグ絞り込みの取得に失敗した (オフライン等) ことを知らせる札。
 *
 * 「タグに合致する曲が 0 件」との誤読を避けるため、VM は失敗時に一覧を空にせず
 * 絞り込み自体を見送る。ここでその状態を明示する。
 */
@Composable
private fun TagFilterErrorBanner(visible: Boolean) {
    if (!visible) return
    ImasNotice(
        kind = ImasNoticeKind.WARNING,
        message = "タグ絞り込みの取得に失敗しました。表示中の一覧にはタグ条件が反映されていません。",
        modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.note)
    )
}

/**
 * 「KAMISABI収録のみ」絞り込み中だけ出す所持コンプ (iOS `SongListView.kamisabiCompletionBanner` 相当)。
 *
 * **分母は `uiState.songs` を数えない。** KAMISABI はブランドごとの別商品 (ML/SideM/シャニ)
 * なので、表示行数を分母にすると (ブランド未選択のときは 3 商品合算の行数になり)
 * 実態と合わない数になる。分母の規則はコア一本 ([SongListViewModel] の
 * `kamisabiCompletion` = `SongRepository.fetchKamisabiCompletion` の値そのまま)。
 */
@Composable
private fun KamisabiCompletionBanner(uiState: SongListUiState) {
    val completion = uiState.kamisabiCompletion
    if (!uiState.filter.kamisabiOnly || uiState.listMode != SongListMode.SONGS ||
        uiState.isLoading || completion == null
    ) {
        return
    }
    ImasText(
        kamisabiCompletionLabel(completion),
        ImasTextRole.SECTION_LABEL,
        modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
    )
}

/**
 * 適用中フィルタの removable な札の並び (iOS SongListView.removableFilterBar 相当)。
 * マイマーク / 回収 / シートで選んだ絞り込み / 選択中タグ を [ImasFilterBar] で横に並べ、× で個別解除する。
 * 何も効いていなければ空のリストを返し、[ImasFilterBar] 自身が何も出さない。
 */
private fun filterBarItems(uiState: SongListUiState, viewModel: SongListViewModel): List<ImasFilterBarItem> {
    val filter = uiState.filter
    // 検索語と同じ軸の条件は、打った語に上書きされている間だけ出さない
    // (VM の withSearch を参照。入力欄と札に違う値が並ぶのを避ける)。
    val searching = uiState.searchText.isNotEmpty()
    val idolOverridden = searching && uiState.searchMode == SongSearchMode.PERFORMER
    val songwriterOverridden = searching && uiState.searchMode == SongSearchMode.CREATOR

    return buildList {
        if (uiState.myMarkFilter.requireMyPick) {
            add(ImasFilterBarItem(id = "myPick", title = "担当", onRemove = viewModel::clearMyPickFilter))
        }
        if (uiState.myMarkFilter.requireFavorite) {
            add(ImasFilterBarItem(id = "favorite", title = "お気に入り", onRemove = viewModel::clearFavoriteFilter))
        }
        if (uiState.myMarkFilter.requireNote) {
            add(ImasFilterBarItem(id = "note", title = "メモあり", onRemove = viewModel::clearNoteFilter))
        }
        when (uiState.collectFilter) {
            SongCollectFilter.COLLECTED ->
                add(ImasFilterBarItem(id = "collect", title = "現地回収済", onRemove = viewModel::clearCollectFilter))
            SongCollectFilter.UNCOLLECTED ->
                add(ImasFilterBarItem(id = "collect", title = "未回収", onRemove = viewModel::clearCollectFilter))
            SongCollectFilter.ALL -> {}
        }
        filter.idolIds?.takeIf { it.isNotEmpty() && !idolOverridden }?.let { ids ->
            // 名前の引き当てはフィルタシート側にしか無いので、札は人数で出す。
            add(
                ImasFilterBarItem(
                    id = "idols",
                    title = "アイドル ${ids.size}人",
                    onRemove = { viewModel.clearFilterField { f -> f.copy(idolIds = null) } }
                )
            )
        }
        filter.songType?.let { type ->
            add(
                ImasFilterBarItem(
                    id = "songType",
                    title = songTypeLabel(type),
                    onRemove = { viewModel.clearFilterField { f -> f.copy(songType = null) } }
                )
            )
        }
        if (filter.kamisabiOnly) {
            add(
                ImasFilterBarItem(
                    id = "kamisabi",
                    title = "KAMISABI収録",
                    onRemove = { viewModel.clearFilterField { f -> f.copy(kamisabiOnly = false) } }
                )
            )
        }
        filter.seriesGroup?.takeIf { it.isNotEmpty() }?.let { value ->
            add(ImasFilterBarItem(id = "series", title = value, onRemove = { viewModel.clearFilterField { f -> f.copy(seriesGroup = null) } }))
        }
        filter.cdSeries?.takeIf { it.isNotEmpty() }?.let { value ->
            add(ImasFilterBarItem(id = "cdSeries", title = value, onRemove = { viewModel.clearFilterField { f -> f.copy(cdSeries = null) } }))
        }
        filter.liveName?.takeIf { it.isNotEmpty() }?.let { value ->
            add(ImasFilterBarItem(id = "live", title = value, onRemove = { viewModel.clearFilterField { f -> f.copy(liveName = null) } }))
        }
        filter.songwriter?.takeIf { it.isNotEmpty() && !songwriterOverridden }?.let { value ->
            add(ImasFilterBarItem(id = "songwriter", title = value, onRemove = { viewModel.clearFilterField { f -> f.copy(songwriter = null) } }))
        }
        uiState.selectedTags.forEach { tag ->
            val label = if (uiState.selectedTags.size == 1) {
                val count = uiState.tagVoteCounts.keys.size
                if (count > 0) "${tag.name} ${count}曲" else tag.name
            } else {
                tag.name
            }
            add(ImasFilterBarItem(id = "tag_${tag.name}", title = label, onRemove = { viewModel.removeTag(tag) }))
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

/**
 * 歌唱・作詞作曲で絞っているときの行の説明 (当たった 1 人を先頭に「ほか N 人」/
 * 当たった役割と名前)。組み立ても照合もコア (searchMatchTexts)。曲名で絞っているときは空。
 */
private fun searchMatchDetails(
    songs: List<SongWithArtists>,
    searchText: String,
    mode: SongSearchMode
): Map<String, String> {
    val needle = searchText.trim()
    val scope = when (mode) {
        SongSearchMode.PERFORMER -> SearchMatchScope.PERFORMER
        SongSearchMode.CREATOR -> SearchMatchScope.CREATOR
        SongSearchMode.TITLE -> return emptyMap()
    }
    if (needle.isEmpty() || songs.isEmpty()) return emptyMap()
    val rows = songs.map { item ->
        SearchMatchRowInput(
            // 優先順: ユニット名 → 歌唱者表記。
            performerLabels = listOfNotNull(item.song.unitName, item.artistNames).filter { it.isNotBlank() },
            lyricist = item.song.lyricist,
            composer = item.song.composer,
            arranger = item.song.arranger
        )
    }
    return searchMatchTexts(rows, scope, needle)
        .mapIndexedNotNull { index, text -> text?.let { songs[index].song.id to it } }
        .toMap()
}
