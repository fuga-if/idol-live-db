package com.fugaif.imaslivedb.ui.units

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasGridSkeleton
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.components.ImasListSkeleton
import com.fugaif.imaslivedb.ui.components.SkeletonThumb
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * ユニット一覧の本体 (曲ありユニットのみ)。`ui.idols.IdolListScreen` の「アイドル」タブと同じ骨格
 * (ブランド別グルーピング + list/grid 切替 + 検索) を踏襲。ユニットには担当/お気に入りマークが無いため
 * フィルタシートは持たない。
 *
 * Scaffold/TopAppBar は持たない (list/grid 切替は呼び出し側の TopAppBar が担う)。
 * `IdolListScreen` の「ユニット」タブに埋め込んで使う。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UnitListBody(
    onNavigateToUnitDetail: (String) -> Unit,
    viewModel: UnitListViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()

    val q = state.searchText.trim().lowercase()

    fun matchesSearch(unit: ImasUnit): Boolean {
        if (q.isEmpty()) return true
        if (unit.name.lowercase().contains(q)) return true
        return unit.nameAlt?.lowercase()?.contains(q) == true
    }

    val filteredUnits = state.units.filter { matchesSearch(it) }
    val groupedByBrand = filteredUnits.groupBy { it.brandId }
    val visibleBrands = state.brands.filter { !groupedByBrand[it.id].isNullOrEmpty() }

    Column(modifier = Modifier.fillMaxSize()) {
        OutlinedTextField(
            value = state.searchText,
            onValueChange = viewModel::setSearchText,
            placeholder = { Text("ユニット名で検索") },
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
                if (state.listMode == UnitListMode.GRID) ImasGridSkeleton(columns = 4, count = 16)
                else ImasListSkeleton(rows = 12, thumb = SkeletonThumb.Circle)
            }
            q.isNotEmpty() && filteredUnits.isEmpty() -> {
                ImasEmptyState(
                    icon = Icons.Filled.Groups,
                    title = "見つかりませんでした",
                    message = "「${state.searchText}」に一致するユニットはいません。"
                )
            }
            filteredUnits.isEmpty() -> {
                ImasEmptyState(
                    icon = Icons.Filled.Groups,
                    title = "ユニットがありません",
                    message = "登録されているユニットがまだありません。"
                )
            }
            state.listMode == UnitListMode.GRID -> {
                PullToRefreshBox(
                    isRefreshing = state.isRefreshing,
                    onRefresh = { viewModel.refresh() },
                    modifier = Modifier.fillMaxSize()
                ) {
                    UnitGrid(
                        visibleBrands = visibleBrands,
                        groupedByBrand = groupedByBrand,
                        collapsedBrands = state.collapsedBrands,
                        onToggleBrand = viewModel::toggleBrandCollapse,
                        onSelect = { onNavigateToUnitDetail(it.id) }
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
                            val units = groupedByBrand[brand.id] ?: emptyList()
                            val collapsed = state.collapsedBrands.contains(brand.id)
                            item(key = "h_${brand.id}") {
                                BrandSectionHeader(brand, units.size, !collapsed) { viewModel.toggleBrandCollapse(brand.id) }
                            }
                            if (!collapsed) {
                                items(units, key = { it.id }) { unit ->
                                    UnitRow(unit = unit, onClick = { onNavigateToUnitDetail(unit.id) })
                                }
                            }
                        }
                    }
                }
            }
        }
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
private fun UnitRow(unit: ImasUnit, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasLeadBar(seed = unit.id, brand = unit.brandId, height = 36.dp)
        Box(Modifier.padding(start = 8.dp)) {
            ImasAvatar(label = unit.name, seed = unit.id, brand = unit.brandId, size = 40.dp)
        }
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Text(unit.displayName, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = DS.ink3, modifier = Modifier.size(16.dp))
    }
}

/** ブランド見出しを full-span アイテムとして挟んだ単一 LazyVerticalGrid (`IdolGrid` と同型)。 */
@Composable
private fun UnitGrid(
    visibleBrands: List<Brand>,
    groupedByBrand: Map<String, List<ImasUnit>>,
    collapsedBrands: Set<String>,
    onToggleBrand: (String) -> Unit,
    onSelect: (ImasUnit) -> Unit
) {
    val columns = if (LocalConfiguration.current.screenWidthDp >= 600) 6 else 4
    LazyVerticalGrid(
        columns = GridCells.Fixed(columns),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(vertical = 8.dp)
    ) {
        visibleBrands.forEach { brand ->
            val units = groupedByBrand[brand.id] ?: emptyList()
            val collapsed = collapsedBrands.contains(brand.id)
            item(
                key = "h_${brand.id}",
                span = { GridItemSpan(maxLineSpan) }
            ) {
                BrandSectionHeader(brand, units.size, !collapsed) { onToggleBrand(brand.id) }
            }
            if (!collapsed) {
                items(units, key = { it.id }) { unit ->
                    UnitGridCell(unit = unit, onClick = { onSelect(unit) })
                }
            }
        }
    }
}

@Composable
private fun UnitGridCell(unit: ImasUnit, onClick: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth()
            .clickable(onClickLabel = unit.displayName, role = Role.Button, onClick = onClick)
            .padding(4.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        ImasAvatar(label = unit.name, seed = unit.id, brand = unit.brandId, size = 60.dp)
        Text(unit.displayName, fontSize = 12.sp, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 2.dp))
    }
}
