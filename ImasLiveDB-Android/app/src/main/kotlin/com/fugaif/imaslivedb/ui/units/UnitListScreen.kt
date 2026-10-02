package com.fugaif.imaslivedb.ui.units

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasGridSkeleton
import com.fugaif.imaslivedb.ui.designsystem.ImasListSkeleton
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeadBar
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasUnitAvatar
import com.fugaif.imaslivedb.ui.designsystem.SkeletonThumb
import com.fugaif.imaslivedb.ui.components.NameFilterField
import com.fugaif.imaslivedb.ui.designsystem.ImasUnitCell
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.imasThemePrewarm
import uniffi.imas_core.TextSearchCatalog

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

    val q = state.searchText.trim()

    // 照合はコア (`domain/text_search_index.rs`) に一任する。ここで `lowercase().contains()`
    // を書いていたせいで、曲・アイドル・ライブは「あるすとろめりあ」で当たるのに
    // ユニットだけ当たらなかった (かなを畳んでいなかった)。同じ検索欄に打つ人からは
    // 説明の付かない差になる。
    //
    // 索引は units が変わった時だけ組み直す (1 打鍵 = matchingIndices 1 回で、
    // 項目ごとに FFI を跨がない)。名前と別名の両方を綴りに入れるので
    // 「Cleasky」でも「クレスカイ」でも当たる。
    val searchCatalog = remember(state.units) {
        TextSearchCatalog(state.units.map { listOfNotNull(it.name, it.nameAlt, it.nameKana) })
    }
    // 索引の実体は Rust 側にある。画面を離れたら (または units が入れ替わったら) 明示的に返す。
    // Cleaner 任せでも最後には解放されるが、それは GC の都合で、いつかは決まらない。
    DisposableEffect(searchCatalog) { onDispose { searchCatalog.close() } }
    val filteredUnits = remember(searchCatalog, q) {
        if (q.isEmpty()) state.units
        else searchCatalog.matchingIndices(q).mapNotNull { state.units.getOrNull(it.toInt()) }
    }
    val groupedByBrand = filteredUnits.groupBy { it.brandId }
    val visibleBrands = state.brands.filter { !groupedByBrand[it.id].isNullOrEmpty() }

    // 行の色を行ごとに derive すると LazyColumn / LazyVerticalGrid の初回スクロール中に
    // 1 行 1 回 FFI を跨ぐ。行が組まれる前に 1 往復で温めておき、行はメモに当てる。
    // 温めは remember の中で行う。LaunchedEffect / SideEffect はコンポーズの後なので、
    // 初回に組まれる行には間に合わない (埋めるのは純粋計算のメモだけなので再コンポーズも誘発しない)。
    //
    // 鍵に filteredUnits を使わないのは、これが再コンポーズのたびに組み直される新しい List で、
    // 突き合わせに全件ぶんの equals が走るため。母集団が変わる条件そのもの (元データと検索語) を鍵にする。
    //
    // 1 行が引く組は 2 通り。ImasLeadBar は brandId をブランド色 hex に解決してから derive し、
    // ImasAvatar は brandId をそのまま渡す。両方温めないと片方が行ごとに跨ぐ。
    imasThemePrewarm(state.units, q) {
        filteredUnits.flatMap {
            listOf<Pair<String?, String?>>(null to it.brandId, it.id to it.brandId)
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NameFilterField(
            prompt = "ユニット名で絞り込み",
            value = state.searchText,
            onValueChange = viewModel::setSearchText
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
                                item(key = "c_${brand.id}") {
                                    ImasCardList(items = units, key = { it.id }) { unit ->
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
}

/** ブランドの区切り見出し (iOS `BrandSectionHeader` + 開閉シェブロン)。見た目は [ImasSectionHeader] (小)。 */
@Composable
private fun BrandSectionHeader(brand: Brand, count: Int, expanded: Boolean, onToggle: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth()
            .imasRowPress(onClickLabel = if (expanded) "折りたたむ" else "展開", onClick = onToggle)
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

/** ユニットの行。先頭にブランドの色の帯を立てるのは Android だけの要素 (iOS の `ImasUnitRow` 単体には無い)。 */
@Composable
private fun UnitRow(unit: ImasUnit, onClick: () -> Unit) {
    val size = ImasRowDensity.REGULAR.avatarSize
    ImasRow(
        title = unit.displayName,
        leading = ImasRowLeading.Custom(width = size) { ImasUnitAvatar(unit, size = size) },
        leadBar = ImasRowLeadBar(brand = unit.brandId),
        trailing = ImasRowTrailing.Chevron,
        titleLineLimit = 1,
        modifier = Modifier.imasRowPress(onClick = onClick)
    )
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
        contentPadding = PaddingValues(vertical = DS.Space.gap, horizontal = DS.Space.screen),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
        verticalArrangement = Arrangement.spacedBy(DS.Space.gap)
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
                    ImasUnitCell(unit = unit, modifier = Modifier.imasRowPress(onClick = { onSelect(unit) }))
                }
            }
        }
    }
}
