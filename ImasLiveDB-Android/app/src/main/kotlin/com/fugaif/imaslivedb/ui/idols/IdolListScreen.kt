package com.fugaif.imaslivedb.ui.idols

import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.FilterAltOff
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.ViewList
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Badge
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import com.fugaif.imaslivedb.ui.components.CopyItem
import com.fugaif.imaslivedb.ui.components.Copyable
import com.fugaif.imaslivedb.ui.components.ImasIdolCell
import com.fugaif.imaslivedb.ui.components.NameFilterField
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasGridSkeleton
import com.fugaif.imaslivedb.ui.designsystem.ImasListSkeleton
import com.fugaif.imaslivedb.ui.designsystem.ImasMarkButton
import com.fugaif.imaslivedb.ui.designsystem.ImasMarkKind
import com.fugaif.imaslivedb.ui.designsystem.ImasMetric
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowChevron
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeadBar
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.designsystem.SkeletonThumb
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.imasThemePrewarm
import com.fugaif.imaslivedb.ui.units.UnitListBody
import com.fugaif.imaslivedb.ui.units.UnitListMode
import com.fugaif.imaslivedb.ui.units.UnitListViewModel
import com.fugaif.imaslivedb.ui.navigation.TopLevelTab
import com.fugaif.imaslivedb.ui.search.CrossTabCountChips
import androidx.compose.runtime.LaunchedEffect
import com.fugaif.imaslivedb.ui.search.CrossTabSearch
import uniffi.imas_core.IdolSearchTargetCounts

/**
 * アイドル一覧。iOS `IdolListView` の構成: ブランド別セクション (見出し + 行/グリッド)。
 * フィルタ/表示形式/表示モードはフィルタシートで設定する。
 * 絞り込み結果は ViewModel が保持する state をそのまま読む (判定本体は imas-core)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IdolListScreen(
    onNavigateToIdolDetail: (String) -> Unit,
    onNavigateToUnitDetail: (String) -> Unit = {},
    viewModel: IdolListViewModel = viewModel(),
    unitListViewModel: UnitListViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val unitState by unitListViewModel.uiState.collectAsState()
    var showFilterSheet by remember { mutableStateOf(false) }
    var tab by rememberSaveable { mutableIntStateOf(0) }

    // 絞り込み・並べ替え・ブランド別グループ化は ViewModel が imas-core へ委譲して算出済み。
    // ここで組むと再コンポーズのたびに全件ぶんの射影 + FFI 往復が走る。
    val filteredIdols = state.filteredIdols
    val groupedByBrand = state.groupedByBrand
    val visibleBrands = state.visibleBrands

    // 行の色を行ごとに derive すると LazyColumn / LazyVerticalGrid の初回スクロール中に
    // 1 行 1 回 FFI を跨ぐ。行が組まれる前に 1 往復で温めておき、行はメモに当てる。
    // 温めは remember の中で行う。LaunchedEffect / SideEffect はコンポーズの後なので、
    // 初回に組まれる行には間に合わない (埋めるのは純粋計算のメモだけなので再コンポーズも誘発しない)。
    //
    // 1 行が引く組は 2 通り。ImasLeadBar は brandId をブランド色 hex に解決してから derive し、
    // ImasAvatar と件数テキストは brandId をそのまま渡す。両方温めないと片方が行ごとに跨ぐ。
    imasThemePrewarm(filteredIdols) {
        filteredIdols.flatMap {
            listOf(it.color to it.brandId)
        }
    }

    // 身長順・年齢順などブランドを跨ぐ並びのときだけの「通し」見出し (「身長順 ・ N人」)。
    val flatHeader = if (state.sortOrder.keepsBrandGrouping) null else "${state.sortOrder.label}順 ・ ${filteredIdols.size}人"

    fun displayName(idol: Idol): String =
        if (state.displayMode == IdolDisplayMode.CV_NAME) (state.castNames[idol.id] ?: idol.name) else idol.name

    fun secondaryText(idol: Idol): String? =
        if (state.displayMode == IdolDisplayMode.CV_NAME) idol.name else idol.nameKana

    fun cvLine(idol: Idol): String? {
        if (!state.showCV || state.displayMode != IdolDisplayMode.IDOL_NAME) return null
        return state.castNames[idol.id]?.let { "CV: $it" }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (tab == 0) "アイドル" else "ユニット", fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = {
                        if (tab == 0) {
                            viewModel.setListMode(if (state.listMode == IdolListMode.GRID) IdolListMode.LIST else IdolListMode.GRID)
                        } else {
                            unitListViewModel.setListMode(if (unitState.listMode == UnitListMode.GRID) UnitListMode.LIST else UnitListMode.GRID)
                        }
                    }) {
                        val isGrid = if (tab == 0) state.listMode == IdolListMode.GRID else unitState.listMode == UnitListMode.GRID
                        Icon(
                            if (isGrid) Icons.Filled.ViewList else Icons.Filled.GridView,
                            contentDescription = if (isGrid) "リスト表示" else "グリッド表示"
                        )
                    }
                    if (tab == 0) {
                        IconButton(onClick = { showFilterSheet = true }) {
                            BadgedBox(badge = {
                                if (state.filterBadgeCount > 0) Badge { Text("${state.filterBadgeCount}") }
                            }) {
                                Icon(Icons.Filled.FilterList, contentDescription = "フィルタ")
                            }
                        }
                    }
                }
            )
        }
    ) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).fillMaxSize()) {
            ImasSegmented(
                labels = listOf("アイドル", "ユニット"),
                selection = tab, onSelect = { tab = it },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)
            )
            if (tab == 1) {
                UnitListBody(onNavigateToUnitDetail = onNavigateToUnitDetail, viewModel = unitListViewModel)
            } else {
            NameFilterField(
                prompt = "アイドル・CV名で絞り込み",
                value = state.searchText,
                onValueChange = viewModel::setSearchText
            )
            // 打っている間だけ「アイドル名 / CV名」の切替を件数つきで出す
            // (今の切替で 0 件でも、もう片方に居ることが一目で分かるように)。
            val counts = state.searchCounts
            if (state.searchText.isNotEmpty() && counts != null) {
                val targets = IdolSearchTarget.entries
                ImasSegmented(
                    labels = targets.map { "${it.label} ${counts.of(it)}" },
                    selection = targets.indexOf(state.searchTarget),
                    onSelect = { viewModel.setSearchTarget(targets[it]) },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)
                )
            }
            // 同じ語が曲・ライブに何件あるか (虫眼鏡を畳んだ代わりの導線)。
            CrossTabCountChips(query = state.searchText, from = TopLevelTab.Idols)
            // 「他のタブに N 件」から飛んで来たら、その語で絞り込む。
            LaunchedEffect(CrossTabSearch.generation) {
                CrossTabSearch.take(TopLevelTab.Idols)?.let { viewModel.setSearchText(it) }
            }
            HorizontalDivider(color = DS.sep)

            when {
                state.isLoading -> {
                    if (state.listMode == IdolListMode.GRID) ImasGridSkeleton(columns = 4, count = 16)
                    else ImasListSkeleton(rows = 12, thumb = SkeletonThumb.Circle)
                }
                state.searchText.isNotEmpty() && filteredIdols.isEmpty() -> {
                    val other = IdolSearchTarget.entries.first { it != state.searchTarget }
                    val otherCount = state.searchCounts?.of(other) ?: 0
                    if (otherCount > 0) {
                        // もう片方でなら当たる。分けたせいで引けなくなったように見せない。
                        ImasEmptyState(
                            icon = Icons.Filled.Person,
                            title = "${state.searchTarget.label}には見つかりません",
                            message = "「${state.searchText}」は${other.label}で ${otherCount} 人見つかります",
                            actionTitle = "${other.label}で探す",
                            onAction = { viewModel.setSearchTarget(other) }
                        )
                    } else {
                        ImasEmptyState(icon = Icons.Filled.Person, title = "見つかりませんでした", message = "「${state.searchText}」に一致するアイドルはいません。")
                    }
                }
                filteredIdols.isEmpty() -> {
                    ImasEmptyState(
                        icon = Icons.Filled.FilterAltOff,
                        title = "該当するアイドルがいません",
                        message = "フィルタ条件を変更するか、フィルタを解除してください。",
                        actionTitle = if (state.filterBadgeCount > 0) "フィルタを解除" else null,
                        onAction = if (state.filterBadgeCount > 0) { { viewModel.clearQuickFilters() } } else null
                    )
                }
                state.listMode == IdolListMode.GRID -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize()
                    ) {
                        IdolGrid(
                            visibleBrands = visibleBrands,
                            groupedByBrand = groupedByBrand,
                            flatIdols = if (flatHeader == null) emptyList() else filteredIdols,
                            flatHeader = flatHeader,
                            metricById = state.metricById,
                            collapsedBrands = state.collapsedBrands,
                            pickIds = state.pickIds,
                            favoriteIds = state.favoriteIds,
                            onToggleBrand = viewModel::toggleBrandCollapse,
                            onSelect = { onNavigateToIdolDetail(it.id) }
                        )
                    }
                }
                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize()
                    ) {
                        LazyColumn(modifier = Modifier.fillMaxSize()) {
                            if (flatHeader != null) {
                                item(key = "flat_header") {
                                    ImasSectionHeader(
                                        title = flatHeader,
                                        style = ImasSectionHeaderStyle.SMALL
                                    )
                                }
                                items(filteredIdols, key = { it.id }) { idol ->
                                    IdolRow(
                                        idol = idol,
                                        isPick = state.pickIds.contains(idol.id),
                                        displayName = displayName(idol),
                                        secondary = secondaryText(idol),
                                        cvLine = cvLine(idol),
                                        metric = state.metricById[idol.id],
                                        onClick = { onNavigateToIdolDetail(idol.id) },
                                        onToggleMyPick = { viewModel.toggleMyPick(idol.id) }
                                    )
                                }
                            }
                            visibleBrands.forEach { brand ->
                                val idols = groupedByBrand[brand.id] ?: emptyList()
                                val collapsed = state.collapsedBrands.contains(brand.id)
                                item(key = "h_${brand.id}") {
                                    BrandSectionHeader(brand, idols.size, !collapsed) { viewModel.toggleBrandCollapse(brand.id) }
                                }
                                if (!collapsed) {
                                    items(idols, key = { it.id }) { idol ->
                                        IdolRow(
                                            idol = idol,
                                            isPick = state.pickIds.contains(idol.id),
                                            displayName = displayName(idol),
                                            secondary = secondaryText(idol),
                                            cvLine = cvLine(idol),
                                            onClick = { onNavigateToIdolDetail(idol.id) },
                                            onToggleMyPick = { viewModel.toggleMyPick(idol.id) }
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
    }

    if (showFilterSheet) {
        IdolFilterSheet(
            brands = state.brands,
            currentBrandIds = state.selectedBrandIds,
            currentAttribute = state.selectedAttribute,
            currentDisplayMode = state.displayMode,
            currentShowCV = state.showCV,
            currentRequireMyPick = state.requireMyPick,
            currentRequireFavorite = state.requireFavorite,
            currentRequireNote = state.requireNote,
            currentSortOrder = state.sortOrder,
            currentSortAscending = state.sortAscending,
            onDismiss = { showFilterSheet = false },
            onApply = { brandIds, attribute, displayMode, showCV, requireMyPick, requireFavorite, requireNote, sortOrder, sortAscending ->
                viewModel.applyFilterSheet(
                    brandIds, attribute, displayMode, showCV,
                    requireMyPick, requireFavorite, requireNote, sortOrder, sortAscending
                )
            }
        )
    }
}

/** ブランドの区切り見出し (iOS `BrandSectionHeader` + 開閉シェブロン)。見た目は [ImasSectionHeader] (小)。 */
@Composable
private fun BrandSectionHeader(brand: Brand, count: Int, expanded: Boolean, onToggle: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth()
            .imasRowPress(onClickLabel = if (expanded) "折りたたむ" else "展開", onClick = onToggle)
            // 「ブランド名 人数」と開閉を 1 つの押せる項目として読ませる (前の Android と同じ)。
            .clearAndSetSemantics {
                contentDescription = "${brand.shortName} $count"
                stateDescription = if (expanded) "展開中" else "折りたたみ中"
                role = Role.Button
                heading()
                onClick(label = if (expanded) "折りたたむ" else "展開") { onToggle(); true }
            }
            .padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasSectionHeader(
            title = brand.shortName,
            count = "$count",
            seed = brand.color,
            style = ImasSectionHeaderStyle.SMALL,
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(0.dp)
        )
        Icon(
            if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
            contentDescription = null,
            tint = DS.ink2
        )
    }
}

/**
 * アイドル一覧の行。★お気に入りトグルは行から撤去済み (2026-09、iOS と同じ)。
 * お気に入り自体は詳細画面のボタン・お気に入り一覧・絞り込みに残しているので
 * 機能は消えていない。グリッド表示は元々お気に入りを出していないので変更なし。
 *
 * 表示形式 (アイドル名/CV名) で主題が入れ替わるため `ImasIdolRow` ではなく `ImasRow` を直接組む
 * (題を常にアイドル名に固定する `ImasIdolRow` では表現できない。iOS `IdolListView.idolRow` と同じ判断)。
 * 先頭のブランド色の帯は Android だけの要素 (iOS 版には無い) なのでそのまま残す。
 */
@Composable
private fun IdolRow(
    idol: Idol,
    isPick: Boolean,
    displayName: String,
    secondary: String?,
    cvLine: String?,
    /** 並び替えのキー値 (「17歳」「158cm」等)。公式順/五十音順のときは null。 */
    metric: String? = null,
    onClick: () -> Unit,
    onToggleMyPick: () -> Unit
) {
    Copyable(
        items = listOf(CopyItem("アイドル名をコピー", idol.name), CopyItem("よみをコピー", idol.nameKana)),
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        ImasRow(
            title = displayName,
            subtitle = secondary?.takeIf { it.isNotEmpty() },
            leading = ImasRowLeading.Avatar(
                label = idol.shortName, seed = idol.color, brand = idol.brandId,
                isPick = isPick, entityId = idol.id
            ),
            leadBar = ImasRowLeadBar(seed = idol.color, brand = idol.brandId),
            trailing = ImasRowTrailing.Custom {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                    // 何順で並んでいるか行から読めるようにする並べ替えの根拠 (公式順/五十音順では null)。
                    if (metric != null) ImasMetric(metric, size = ImasNumeralSize.MEDIUM)
                    ImasMarkButton(ImasMarkKind.PICK, isOn = isPick, seed = idol.color, brand = idol.brandId, onClick = onToggleMyPick)
                    ImasRowChevron()
                }
            },
            titleLineLimit = 1
        ) {
            if (cvLine != null) ImasText(cvLine, ImasTextRole.META)
        }
    }
}

/** iOS `IdolGridView` 相当: ブランド見出しを full-span アイテムとして挟んだ単一 LazyVerticalGrid。 */
@Composable
private fun IdolGrid(
    visibleBrands: List<Brand>,
    groupedByBrand: Map<String, List<Idol>>,
    /** 通し表示 (公式順以外) のアイドル。空ならブランド別表示。 */
    flatIdols: List<Idol> = emptyList(),
    flatHeader: String? = null,
    metricById: Map<String, String> = emptyMap(),
    collapsedBrands: Set<String>,
    pickIds: Set<String>,
    favoriteIds: Set<String>,
    onToggleBrand: (String) -> Unit,
    onSelect: (Idol) -> Unit
) {
    val columns = if (LocalConfiguration.current.screenWidthDp >= 600) 6 else 4
    LazyVerticalGrid(
        columns = GridCells.Fixed(columns),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(vertical = DS.Space.gap)
    ) {
        if (flatIdols.isNotEmpty()) {
            if (flatHeader != null) {
                item(key = "flat_header", span = { GridItemSpan(maxLineSpan) }) {
                    ImasSectionHeader(
                        title = flatHeader,
                        style = ImasSectionHeaderStyle.SMALL
                    )
                }
            }
            items(flatIdols, key = { it.id }) { idol ->
                IdolGridCell(
                    idol = idol,
                    isPick = pickIds.contains(idol.id),
                    isFavorite = favoriteIds.contains(idol.id),
                    metric = metricById[idol.id],
                    onClick = { onSelect(idol) }
                )
            }
        }
        visibleBrands.forEach { brand ->
            val idols = groupedByBrand[brand.id] ?: emptyList()
            val collapsed = collapsedBrands.contains(brand.id)
            item(
                key = "h_${brand.id}",
                span = { GridItemSpan(maxLineSpan) }
            ) {
                BrandSectionHeader(brand, idols.size, !collapsed) { onToggleBrand(brand.id) }
            }
            if (!collapsed) {
                items(idols, key = { it.id }) { idol ->
                    IdolGridCell(
                        idol = idol,
                        isPick = pickIds.contains(idol.id),
                        isFavorite = favoriteIds.contains(idol.id),
                        metric = metricById[idol.id],
                        onClick = { onSelect(idol) }
                    )
                }
            }
        }
    }
}

/**
 * アイドル一覧の名札セル (DS §6.6 `ImasIdolCell`)。
 * [isFavorite] は呼び出し側 (`IdolGrid`) から渡され続けている既存の引数で、現状どちらの表示にも使わない
 * (元のセルも使っていなかった。配線だけ残し、呼び出し側は変えない)。
 */
@Composable
private fun IdolGridCell(
    idol: Idol,
    isPick: Boolean,
    @Suppress("UNUSED_PARAMETER") isFavorite: Boolean,
    /** 並び替えのキー値 (「17歳」「158cm」等)。何順に並んでいるかセルから読めるように出す。 */
    metric: String? = null,
    onClick: () -> Unit
) {
    ImasIdolCell(
        idol = idol,
        isPick = isPick,
        metric = metric,
        modifier = Modifier.imasRowPress(onClickLabel = idol.name, onClick = onClick)
    )
}

/** 切替先ごとの件数。 */
private fun IdolSearchTargetCounts.of(target: IdolSearchTarget): Int = when (target) {
    IdolSearchTarget.NAME -> name.toInt()
    IdolSearchTarget.VOICE_ACTOR -> voiceActor.toInt()
}
