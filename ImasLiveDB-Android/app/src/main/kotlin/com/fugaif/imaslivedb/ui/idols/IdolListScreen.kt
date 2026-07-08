package com.fugaif.imaslivedb.ui.idols

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasGridSkeleton
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.components.ImasListSkeleton
import com.fugaif.imaslivedb.ui.components.SkeletonThumb
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * アイドル一覧。iOS `IdolListView` の構成: ブランド別セクション (見出し + 行/グリッド)。
 * フィルタ/表示形式/表示モードはフィルタシートで設定する。
 * 絞り込みは収集した state から純粋に算出する (Compose の依存追跡を壊さないため)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IdolListScreen(
    onNavigateToIdolDetail: (String) -> Unit,
    viewModel: IdolListViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    var showFilterSheet by remember { mutableStateOf(false) }

    val q = state.searchText.trim().lowercase()

    fun matchesSearch(idol: Idol): Boolean {
        if (q.isEmpty()) return true
        if (idol.name.lowercase().contains(q)) return true
        if (idol.nameKana?.lowercase()?.contains(q) == true) return true
        return state.castNames[idol.id]?.lowercase()?.contains(q) == true
    }

    fun matchesFilters(idol: Idol): Boolean {
        if (state.selectedBrandIds.isNotEmpty() && idol.brandId !in state.selectedBrandIds) return false
        if (state.selectedAttribute != null && idol.attribute != state.selectedAttribute) return false
        if (state.requireMyPick && idol.id !in state.pickIds) return false
        if (state.requireFavorite && idol.id !in state.favoriteIds) return false
        if (state.requireNote && idol.id !in state.noteIds) return false
        return matchesSearch(idol)
    }

    val filteredIdols = state.idols.filter { matchesFilters(it) }
    val groupedByBrand = filteredIdols.groupBy { it.brandId }
    val visibleBrands = state.brands.filter { !groupedByBrand[it.id].isNullOrEmpty() }

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
                title = { Text("アイドル", fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = {
                        viewModel.setListMode(if (state.listMode == IdolListMode.GRID) IdolListMode.LIST else IdolListMode.GRID)
                    }) {
                        Icon(
                            if (state.listMode == IdolListMode.GRID) Icons.Filled.ViewList else Icons.Filled.GridView,
                            contentDescription = if (state.listMode == IdolListMode.GRID) "リスト表示" else "グリッド表示"
                        )
                    }
                    IconButton(onClick = { showFilterSheet = true }) {
                        BadgedBox(badge = {
                            if (state.filterBadgeCount > 0) Badge { Text("${state.filterBadgeCount}") }
                        }) {
                            Icon(Icons.Filled.FilterList, contentDescription = "フィルタ")
                        }
                    }
                }
            )
        }
    ) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).fillMaxSize()) {
            OutlinedTextField(
                value = state.searchText,
                onValueChange = viewModel::setSearchText,
                placeholder = { Text("アイドル・CV名で検索") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                trailingIcon = {
                    if (state.searchText.isNotEmpty()) {
                        IconButton(onClick = { viewModel.setSearchText("") }) {
                            Icon(Icons.Filled.Clear, contentDescription = "クリア")
                        }
                    }
                },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
            )
            HorizontalDivider(color = DS.sep)

            when {
                state.isLoading -> {
                    if (state.listMode == IdolListMode.GRID) ImasGridSkeleton(columns = 4, count = 16)
                    else ImasListSkeleton(rows = 12, thumb = SkeletonThumb.Circle)
                }
                q.isNotEmpty() && filteredIdols.isEmpty() -> {
                    ImasEmptyState(icon = Icons.Filled.Person, title = "見つかりませんでした", message = "「${state.searchText}」に一致するアイドルはいません。")
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
                            collapsedBrands = state.collapsedBrands,
                            pickIds = state.pickIds,
                            favoriteIds = state.favoriteIds,
                            onToggleBrand = viewModel::toggleBrandCollapse,
                            onToggleMyPick = viewModel::toggleMyPick,
                            onToggleFavorite = viewModel::toggleFavorite,
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
                                            isFavorite = state.favoriteIds.contains(idol.id),
                                            displayName = displayName(idol),
                                            secondary = secondaryText(idol),
                                            cvLine = cvLine(idol),
                                            onClick = { onNavigateToIdolDetail(idol.id) },
                                            onToggleMyPick = { viewModel.toggleMyPick(idol.id) },
                                            onToggleFavorite = { viewModel.toggleFavorite(idol.id) }
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
            onDismiss = { showFilterSheet = false },
            onApply = { brandIds, attribute, displayMode, showCV, requireMyPick, requireFavorite, requireNote ->
                viewModel.applyFilterSheet(brandIds, attribute, displayMode, showCV, requireMyPick, requireFavorite, requireNote)
            }
        )
    }
}

@Composable
private fun BrandSectionHeader(brand: Brand, count: Int, expanded: Boolean, onToggle: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onToggle)
            .background(DS.bg).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(brand.shortName, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DS.ink)
        Text(" $count", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3)
        Box(Modifier.weight(1f))
        Icon(if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
            contentDescription = if (expanded) "折りたたむ" else "展開", tint = DS.ink2)
    }
}

@Composable
private fun IdolRow(
    idol: Idol,
    isPick: Boolean,
    isFavorite: Boolean,
    displayName: String,
    secondary: String?,
    cvLine: String?,
    onClick: () -> Unit,
    onToggleMyPick: () -> Unit,
    onToggleFavorite: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasLeadBar(seed = idol.color, brand = idol.brandId, height = 36.dp)
        Box(Modifier.padding(start = 8.dp)) {
            ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 40.dp, isPick = isPick)
        }
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Text(displayName, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            secondary?.takeIf { it.isNotEmpty() }?.let {
                Text(it, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            cvLine?.let {
                Text(it, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        MarkIconButton(active = isPick, activeIcon = Icons.Filled.Favorite, inactiveIcon = Icons.Filled.FavoriteBorder,
            tint = DS.pick, contentDescription = if (isPick) "担当解除" else "担当に追加", onClick = onToggleMyPick)
        MarkIconButton(active = isFavorite, activeIcon = Icons.Filled.Star, inactiveIcon = Icons.Filled.StarBorder,
            tint = DS.favorite, contentDescription = if (isFavorite) "お気に入り解除" else "お気に入りに追加", onClick = onToggleFavorite)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = DS.ink3, modifier = Modifier.size(16.dp))
    }
}

@Composable
private fun MarkIconButton(
    active: Boolean,
    activeIcon: ImageVector,
    inactiveIcon: ImageVector,
    tint: Color,
    contentDescription: String,
    onClick: () -> Unit
) {
    IconButton(onClick = onClick, modifier = Modifier.size(36.dp)) {
        Icon(
            if (active) activeIcon else inactiveIcon,
            contentDescription = contentDescription,
            tint = if (active) tint else DS.ink3,
            modifier = Modifier.size(18.dp)
        )
    }
}

/** iOS `IdolGridView` 相当: ブランド見出しを full-span アイテムとして挟んだ単一 LazyVerticalGrid。 */
@Composable
private fun IdolGrid(
    visibleBrands: List<Brand>,
    groupedByBrand: Map<String, List<Idol>>,
    collapsedBrands: Set<String>,
    pickIds: Set<String>,
    favoriteIds: Set<String>,
    onToggleBrand: (String) -> Unit,
    onToggleMyPick: (String) -> Unit,
    onToggleFavorite: (String) -> Unit,
    onSelect: (Idol) -> Unit
) {
    val columns = if (LocalConfiguration.current.screenWidthDp >= 600) 6 else 4
    LazyVerticalGrid(
        columns = GridCells.Fixed(columns),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(vertical = 8.dp)
    ) {
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
                        onClick = { onSelect(idol) },
                        onToggleMyPick = { onToggleMyPick(idol.id) },
                        onToggleFavorite = { onToggleFavorite(idol.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun IdolGridCell(
    idol: Idol,
    isPick: Boolean,
    isFavorite: Boolean,
    onClick: () -> Unit,
    onToggleMyPick: () -> Unit,
    onToggleFavorite: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(4.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box {
            ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 60.dp, isPick = isPick)
            Row(modifier = Modifier.align(Alignment.TopEnd).offset(x = 6.dp, y = (-4).dp)) {
                MarkIconButton(active = isPick, activeIcon = Icons.Filled.Favorite, inactiveIcon = Icons.Filled.FavoriteBorder,
                    tint = DS.pick, contentDescription = if (isPick) "担当解除" else "担当に追加", onClick = onToggleMyPick)
                MarkIconButton(active = isFavorite, activeIcon = Icons.Filled.Star, inactiveIcon = Icons.Filled.StarBorder,
                    tint = DS.favorite, contentDescription = if (isFavorite) "お気に入り解除" else "お気に入りに追加", onClick = onToggleFavorite)
            }
        }
        Text(idol.name, fontSize = 12.sp, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 2.dp))
    }
}
