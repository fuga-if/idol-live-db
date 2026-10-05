package com.fugaif.imaslivedb.ui.events

import com.fugaif.imaslivedb.ui.designsystem.ReadableWidth
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.ui.designsystem.ImasDateHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterBar
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterBarItem
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.components.EventAttendanceSwipeRow
import com.fugaif.imaslivedb.ui.designsystem.ImasListSkeleton
import com.fugaif.imaslivedb.ui.designsystem.ImasStubDate
import com.fugaif.imaslivedb.ui.designsystem.ImasStubRow
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
import com.fugaif.imaslivedb.ui.components.NameFilterField
import com.fugaif.imaslivedb.ui.designsystem.SkeletonThumb
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.navigation.TopLevelTab
import com.fugaif.imaslivedb.ui.search.CrossTabCountChips
import com.fugaif.imaslivedb.ui.search.CrossTabSearch
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.data.model.JstDay
import uniffi.imas_core.spokenDate
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasDisclosureRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import androidx.compose.runtime.saveable.rememberSaveable
import uniffi.imas_core.OpenArchive
import uniffi.imas_core.OpenTicketSale
import uniffi.imas_core.ticketApplicationLabel
import uniffi.imas_core.TicketApplication
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun EventListScreen(
    onEventClick: (String) -> Unit,
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
                    BadgedBox(
                        badge = {
                            if (uiState.activeFilterCount > 0) Badge { Text("${uiState.activeFilterCount}") }
                        },
                        modifier = Modifier.padding(end = DS.Space.gap)
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
            ImasTabs(
                labels = listOf("今後の予定", "開催済み"),
                selection = uiState.timeFilter,
                onSelect = { viewModel.selectTimeFilter(it) },
                modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
            )

            // 一覧そのものを絞る欄。虫眼鏡のシート (横断検索) だと結果がそこで完結してしまい、
            // ブランド絞り込みや期間フィルタと合わせられない。
            NameFilterField(
                prompt = "ライブ名で絞り込み",
                value = uiState.searchText,
                onValueChange = { viewModel.setSearchText(it) }
            )
            // 同じ語が曲・アイドルに何件あるか (虫眼鏡を畳んだ代わりの導線)。
            CrossTabCountChips(query = uiState.searchText, from = TopLevelTab.Events)
            // 「他のタブに N 件」から飛んで来たら、その語で絞り込む。
            // 当たりが開催済みにしか無いなら、そちらへ着地する。件数を見せて誘って
            // おいて 0 件の画面を出すのは、この導線の趣旨に反する。
            LaunchedEffect(CrossTabSearch.generation) {
                val handed = CrossTabSearch.take(TopLevelTab.Events) ?: return@LaunchedEffect
                viewModel.setSearchText(handed)
                val sides = AppModule.from(context).searchRepository
                    .eventSearchSides(handed, JstDay.today())
                if (sides.second > sides.first) viewModel.selectTimeFilter(1)
            }

            ActiveFilterChipRow(
                uiState = uiState,
                viewModel = viewModel,
                onClearVenue = { viewModel.selectVenue(context, null) }
            )

            // 会場チップ + 件数。会場だけは専用ピッカーを開くのでフィルタシートに畳まず一覧に残す。
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight),
                verticalAlignment = Alignment.CenterVertically
            ) {
                ImasFilterChip(
                    label = uiState.venueDirectory.venue(uiState.venue)?.name ?: "会場",
                    selected = uiState.venue != null,
                    onClick = { showVenuePicker = true },
                    icon = Icons.Filled.Place,
                    onClear = if (uiState.venue != null) {
                        { viewModel.selectVenue(context, null) }
                    } else null,
                    clearContentDescription = "会場絞り込みを解除"
                )
                Spacer(modifier = Modifier.weight(1f))
                ImasText("${uiState.filteredCount}件", role = ImasTextRole.NOTE, color = DS.ink2)
            }

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
                // 広い画面では本文幅を抑える (iOS の readableContentMargins と対)。
                ReadableWidth { readable ->
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = readable,
                        verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
                    ) {
                        if (uiState.timeFilter == 0 && uiState.openSales.isNotEmpty()) {
                            item(key = "open_sales") {
                                OpenSalesSection(
                                    sales = uiState.openSales,
                                    onEventClick = onEventClick,
                                    modifier = Modifier.padding(horizontal = DS.Space.screen)
                                )
                            }
                        }
                        if (uiState.timeFilter == 0 && uiState.openArchives.isNotEmpty()) {
                            item(key = "open_archives") {
                                OpenArchivesSection(
                                    archives = uiState.openArchives,
                                    onEventClick = onEventClick,
                                    modifier = Modifier.padding(horizontal = DS.Space.screen)
                                )
                            }
                        }
                        uiState.groupedByYear.forEach { group ->
                            stickyHeader(key = group.year) {
                                ImasDateHeader(
                                    big = group.year,
                                    isPast = uiState.timeFilter == 1,
                                    modifier = Modifier.padding(horizontal = DS.Space.screen)
                                )
                            }
                            items(group.events, key = { it.event.id }) { ew ->
                                // 行の右スワイプで参加登録 (イベントは公演を複数束ねるので、
                                // 既存の EventAttendanceSheet をそのまま開く)。
                                EventAttendanceSwipeRow(
                                    eventId = ew.event.id,
                                    brand = ew.event.brandId
                                ) {
                                    // 一覧は常に正式名 (ImasEventRow の「ライブ名を省略表示」設定を
                                    // 通さない。長押しの「ライブ名をコピー」も前に無いので付けない)。
                                    val spoken = remember(ew.firstDate) { ew.firstDate?.let { spokenDate(it) } }
                                    ImasStubRow(
                                        date = ew.firstDate?.let { ImasStubDate(it) } ?: ImasStubDate.Unknown,
                                        title = ew.event.name,
                                        modifier = Modifier
                                            .padding(horizontal = DS.Space.screen)
                                            .imasRowPress(onClick = { onEventClick(ew.event.id) }),
                                        subtitle = ew.dateRange,
                                        brand = ew.event.brandId,
                                        rainbow = ew.isJoint,
                                        spokenDate = spoken
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * 適用中フィルタの removable チップ列 (iOS EventListView.activeFilterChips 相当)。
 * ブランド / 除外種別 / 参加状態 / お気に入り / メモ / 空イベント / 配信除外 / 会場 / 検索語 を
 * 横スクロールで一覧し、× で個別解除する。見た目は DesignSystem の `ImasFilterBar`。
 */
@Composable
private fun ActiveFilterChipRow(
    uiState: EventListUiState,
    viewModel: EventListViewModel,
    onClearVenue: () -> Unit
) {
    val brandNames = remember(uiState.brands) { uiState.brands.associate { it.id to it.shortName } }

    val items = buildList {
        if (uiState.appliedSearchText.isNotEmpty()) {
            add(ImasFilterBarItem(id = "search", title = "「${uiState.appliedSearchText}」", onRemove = viewModel::clearSearchText))
        }
        // 並びは選択順でなくソート済みで固定する。押すたびにチップが入れ替わると押し損ねる。
        uiState.selectedBrandIds.sorted().forEach { id ->
            add(ImasFilterBarItem(id = "brand_$id", title = brandNames[id] ?: id, onRemove = { viewModel.toggleBrand(id) }))
        }
        uiState.excludedKinds.sorted().forEach { kind ->
            add(ImasFilterBarItem(id = "kind_$kind", title = "除外: ${eventKindLabel(kind)}", onRemove = { viewModel.removeExcludedKind(kind) }))
        }
        when (uiState.attendanceFilter) {
            "attended" -> add(ImasFilterBarItem(id = "attendance", title = "参加済み", onRemove = viewModel::clearAttendanceFilter))
            "not_attended" -> add(ImasFilterBarItem(id = "attendance", title = "未参加", onRemove = viewModel::clearAttendanceFilter))
        }
        if (uiState.requireFavorite) {
            add(ImasFilterBarItem(id = "favorite", title = "お気に入り", onRemove = viewModel::clearFavoriteFilter))
        }
        if (uiState.requireNote) {
            add(ImasFilterBarItem(id = "note", title = "メモあり", onRemove = viewModel::clearNoteFilter))
        }
        if (uiState.showEmptyEvents) {
            add(ImasFilterBarItem(id = "empty", title = "空イベントも表示", onRemove = viewModel::clearShowEmptyEvents))
        }
        if (uiState.hideStreaming) {
            add(ImasFilterBarItem(id = "stream", title = "配信を除く", onRemove = viewModel::toggleHideStreaming))
        }
        uiState.venue?.let { venueId ->
            add(ImasFilterBarItem(id = "venue", title = uiState.venueDirectory.venue(venueId)?.name ?: venueId, onRemove = onClearVenue))
        }
    }

    // ImasFilterBar は内部の ImasChipRow が左右の余白を自分で持つ (ここで足すと二重になる)。
    ImasFilterBar(items = items)
}

/**
 * 見られるアーカイブ: 全ライブ横断の「いま見逃し配信が見られる」公演を終わりの近い順に
 * (iOS `openArchivesSection`)。押すとそのライブの詳細へ (公演の価格の行に期間と配信の券種がある)。
 */
@Composable
private fun OpenArchivesSection(archives: List<OpenArchive>, onEventClick: (String) -> Unit, modifier: Modifier = Modifier) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    val shown = if (expanded) archives else archives.take(OPEN_SALES_COLLAPSED_LIMIT)
    ImasSection("見られるアーカイブ", modifier = modifier, count = "${archives.size}件", style = ImasSectionHeaderStyle.SMALL) {
        ImasCardList {
            shown.forEachIndexed { index, archive ->
                ImasRow(
                    title = archive.eventName,
                    modifier = Modifier.imasRowPress(onClick = { onEventClick(archive.eventId) }),
                    subtitle = listOf(archive.showLabels.joinToString("・"), archive.endsLabel)
                        .filter { it.isNotEmpty() }
                        .joinToString(" ・ "),
                    leading = ImasRowLeading.Bar(seed = archive.brandColor),
                    trailing = ImasRowTrailing.Badge(archive.remainingLabel, ImasBadgeKind.ATTENTION),
                    density = ImasRowDensity.COMPACT,
                    subtitleLineLimit = 2,
                    position = if (index == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING
                )
            }
            if (archives.size > OPEN_SALES_COLLAPSED_LIMIT) {
                ImasRowDivider(inset = DS.Space.rowH)
                ImasDisclosureRow(
                    title = if (expanded) "畳む" else "ほかのアーカイブ",
                    isExpanded = expanded,
                    onToggle = { expanded = !expanded },
                    count = if (expanded) null else "${archives.size - OPEN_SALES_COLLAPSED_LIMIT}件"
                )
            }
        }
    }
}

/** 畳んだときに出す受付中の件数 (iOS `openSalesCollapsedLimit`)。 */
private const val OPEN_SALES_COLLAPSED_LIMIT = 3

/**
 * 受付中のチケット: 全ライブ横断の「いま申し込める」受付を締切の近い順に (iOS `openSalesSection`)。
 * 押すとそのライブの詳細へ (受付の詳細・申込リンクはそこにある)。
 */
@Composable
private fun OpenSalesSection(sales: List<OpenTicketSale>, onEventClick: (String) -> Unit, modifier: Modifier = Modifier) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    var applications by remember { mutableStateOf<Map<String, TicketApplication>>(emptyMap()) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(sales) { applications = AppModule.from(context).userMarkRepository.ticketApplications() }
    // 詳細で記録を付け替えて戻ってきたときに読み直す (戻るだけでは sales が変わらない)。
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        scope.launch { applications = AppModule.from(context).userMarkRepository.ticketApplications() }
    }
    val shown = if (expanded) sales else sales.take(OPEN_SALES_COLLAPSED_LIMIT)
    ImasSection("受付中のチケット", modifier = modifier, count = "${sales.size}件", style = ImasSectionHeaderStyle.SMALL) {
        ImasCardList {
            shown.forEachIndexed { index, open ->
                ImasRow(
                    title = open.sale.eventName,
                    modifier = Modifier.imasRowPress(onClick = { onEventClick(open.sale.eventId) }),
                    subtitle = listOfNotNull(open.sale.name, open.deadlineLabel).joinToString(" ・ "),
                    leading = ImasRowLeading.Bar(seed = open.brandColor),
                    // 申し込み済みなら締切より記録を見せる (もう急ぐ必要がない。iOS と同じ)。
                    trailing = applications[open.sale.id]?.let { ImasRowTrailing.Badge(ticketApplicationLabel(open.sale.kind, it), ImasBadgeKind.GUEST) }
                        ?: open.remainingLabel?.let { ImasRowTrailing.Badge(it, ImasBadgeKind.ATTENTION) } ?: ImasRowTrailing.None,
                    density = ImasRowDensity.COMPACT,
                    subtitleLineLimit = 2,
                    position = if (index == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING
                )
            }
            if (sales.size > OPEN_SALES_COLLAPSED_LIMIT) {
                ImasRowDivider(inset = DS.Space.rowH)
                ImasDisclosureRow(
                    title = if (expanded) "畳む" else "ほかの受付",
                    isExpanded = expanded,
                    onToggle = { expanded = !expanded },
                    count = if (expanded) null else "${sales.size - OPEN_SALES_COLLAPSED_LIMIT}件"
                )
            }
        }
    }
}

