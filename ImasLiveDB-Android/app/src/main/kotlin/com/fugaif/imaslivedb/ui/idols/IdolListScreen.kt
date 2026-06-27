package com.fugaif.imaslivedb.ui.idols

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.ImasListSkeleton
import com.fugaif.imaslivedb.ui.components.SkeletonThumb
import com.fugaif.imaslivedb.ui.components.BrandFilterItem
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * アイドル一覧。iOS IdolListView の構成: ブランド別セクション (見出し + 行)。
 * 行 = ImasAvatar + 名前 + よみ。フィルタ/グルーピングは収集した state から純粋に算出する
 * (ViewModel が _uiState.value を直読みする旧実装は Compose が追跡できず空表示になっていた)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IdolListScreen(
    onNavigateToIdolDetail: (String) -> Unit,
    viewModel: IdolListViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()

    // 収集 state から算出 (reactive)。
    val q = state.searchText.trim().lowercase()
    fun idolsOf(brandId: String): List<Idol> =
        state.idols.filter { it.brandId == brandId }
            .filter { q.isEmpty() || it.name.lowercase().contains(q) || it.nameKana?.lowercase()?.contains(q) == true }
    val visibleBrands = state.brands.filter {
        (state.selectedBrandId == null || state.selectedBrandId == it.id) && idolsOf(it.id).isNotEmpty()
    }

    Scaffold(topBar = { TopAppBar(title = { Text("アイドル", fontWeight = FontWeight.Bold) }) }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding)) {
            BrandFilterChips(
                brands = state.brands.map { BrandFilterItem(it.id, it.shortName) },
                selectedBrandId = state.selectedBrandId,
                onBrandSelected = viewModel::selectBrand
            )
            HorizontalDivider(color = DS.sep)
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

            if (state.isLoading) {
                ImasListSkeleton(rows = 12, thumb = SkeletonThumb.Circle)
            } else {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    visibleBrands.forEach { brand ->
                        val idols = idolsOf(brand.id)
                        val collapsed = state.collapsedBrands.contains(brand.id)
                        item(key = "h_${brand.id}") {
                            BrandSectionHeader(brand, idols.size, !collapsed) { viewModel.toggleBrandCollapse(brand.id) }
                        }
                        if (!collapsed) {
                            items(idols, key = { it.id }) { idol ->
                                IdolRow(idol) { onNavigateToIdolDetail(idol.id) }
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
private fun IdolRow(idol: Idol, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 40.dp)
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Text(idol.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            idol.nameKana?.takeIf { it.isNotEmpty() }?.let {
                Text(it, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = DS.ink3, modifier = Modifier.size(16.dp))
    }
}
