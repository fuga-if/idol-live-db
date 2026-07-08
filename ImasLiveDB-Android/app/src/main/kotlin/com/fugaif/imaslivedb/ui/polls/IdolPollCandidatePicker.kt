package com.fugaif.imaslivedb.ui.polls

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items as lazyColumnItems
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as lazyGridItems
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.Clear
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
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.BrandFilterItem
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class IdolPickerUiState(
    val idols: List<Idol> = emptyList(),
    val brands: List<Brand> = emptyList(),
    val isLoading: Boolean = true
)

/** 全アイドルをロードするだけの軽量 ViewModel。ピッカー表示中だけ生存する。 */
class IdolPickerViewModel(app: Application) : AndroidViewModel(app) {
    private val idolRepo = AppModule.from(app).idolRepository
    private val statsRepo = AppModule.from(app).statsRepository
    private val _uiState = MutableStateFlow(IdolPickerUiState())
    val uiState: StateFlow<IdolPickerUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val idols = runCatching { idolRepo.fetchIdols(null) }.getOrDefault(emptyList())
            val brands = runCatching { statsRepo.fetchBrands() }.getOrDefault(emptyList())
            _uiState.value = IdolPickerUiState(idols = idols, brands = brands, isLoading = false)
        }
    }
}

private enum class PickerDisplayMode { GRID, LIST }

/**
 * お題(投票)に新しい候補アイドルを追加するピッカー。iOS `IdolMultiPickerView` の移植。
 * 顔写真(モノグラム)グリッドをデフォルト表示にし、全ブランド数百人規模のお題でも見渡しやすくする。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IdolPollCandidatePicker(
    alreadySelected: Set<String>,
    remaining: Int,
    onDismiss: () -> Unit,
    onConfirm: (List<String>) -> Unit,
    viewModel: IdolPickerViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var selection by remember { mutableStateOf(alreadySelected) }
    var query by remember { mutableStateOf("") }
    var selectedBrandId by remember { mutableStateOf<String?>(null) }
    var displayMode by remember { mutableStateOf(PickerDisplayMode.GRID) }

    val filtered = remember(state.idols, query, selectedBrandId) {
        val q = query.trim().lowercase()
        state.idols.filter { idol ->
            (selectedBrandId == null || idol.brandId == selectedBrandId) &&
                (q.isEmpty() || idol.name.lowercase().contains(q) || idol.nameKana?.lowercase()?.contains(q) == true)
        }
    }
    val grouped = remember(filtered, state.brands) {
        state.brands.mapNotNull { brand ->
            val list = filtered.filter { it.brandId == brand.id }
            if (list.isEmpty()) null else brand to list
        }
    }
    val newlyAddedCount = (selection - alreadySelected).size
    val overRemaining = newlyAddedCount > remaining

    fun toggle(idol: Idol) {
        selection = if (selection.contains(idol.id)) selection - idol.id else selection + idol.id
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            // ヘッダー: タイトル + グリッド/リスト切替
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "出演者を選択 (${selection.size})",
                    fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = {
                    displayMode = if (displayMode == PickerDisplayMode.GRID) PickerDisplayMode.LIST else PickerDisplayMode.GRID
                }) {
                    Icon(
                        if (displayMode == PickerDisplayMode.GRID) Icons.Filled.ViewList else Icons.Filled.GridView,
                        contentDescription = if (displayMode == PickerDisplayMode.GRID) "リスト表示" else "グリッド表示"
                    )
                }
            }

            BrandFilterChips(
                brands = state.brands.map { BrandFilterItem(it.id, it.shortName) },
                selectedBrandId = selectedBrandId,
                onBrandSelected = { selectedBrandId = it }
            )

            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text("アイドル名で検索") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                trailingIcon = {
                    if (query.isNotEmpty()) {
                        IconButton(onClick = { query = "" }) { Icon(Icons.Filled.Clear, contentDescription = "クリア") }
                    }
                },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
            )

            if (overRemaining) {
                Text(
                    "残り${remaining}人まで選べます (現在+${newlyAddedCount}人)",
                    fontSize = 12.sp, color = DS.danger,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp)
                )
            }

            if (state.isLoading) {
                Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            } else if (displayMode == PickerDisplayMode.GRID) {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(4),
                    modifier = Modifier.fillMaxWidth().weight(1f).padding(horizontal = 12.dp),
                    contentPadding = PaddingValues(vertical = 8.dp)
                ) {
                    grouped.forEach { (brand, idols) ->
                        item(key = "h_${brand.id}", span = { GridItemSpan(maxLineSpan) }) {
                            Text(
                                "${brand.shortName} (${idols.size})",
                                fontSize = 14.sp, fontWeight = FontWeight.Bold, color = DS.ink2,
                                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)
                            )
                        }
                        lazyGridItems(idols, key = { it.id }) { idol ->
                            IdolGridCell(idol = idol, isSelected = selection.contains(idol.id)) { toggle(idol) }
                        }
                    }
                }
            } else {
                LazyColumn(modifier = Modifier.fillMaxWidth().weight(1f)) {
                    grouped.forEach { (brand, idols) ->
                        item(key = "h_${brand.id}") {
                            Text(
                                "${brand.shortName} (${idols.size})",
                                fontSize = 14.sp, fontWeight = FontWeight.Bold, color = DS.ink2,
                                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)
                            )
                        }
                        lazyColumnItems(idols, key = { it.id }) { idol ->
                            IdolListRow(idol = idol, isSelected = selection.contains(idol.id)) { toggle(idol) }
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
}

@Composable
private fun IdolGridCell(idol: Idol, isSelected: Boolean, onClick: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(6.dp).clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(contentAlignment = Alignment.BottomEnd) {
            Box(modifier = Modifier.background(if (isSelected) DS.fill else Color.Transparent, CircleShape)) {
                ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 56.dp)
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
            idol.name, fontSize = 11.sp, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun IdolListRow(idol: Idol, isSelected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 40.dp)
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Text(idol.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Icon(
            if (isSelected) Icons.Filled.CheckCircle else Icons.Filled.Circle,
            contentDescription = null,
            tint = if (isSelected) DS.success else DS.ink3
        )
    }
}
