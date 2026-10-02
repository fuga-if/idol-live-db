package com.fugaif.imaslivedb.ui.polls

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items as lazyColumnItems
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as lazyGridItems
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.ViewList
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.BrandFilterItem
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasSearchField
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectableRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasUnitAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasUnitCell
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.imasThemePrewarm
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import com.fugaif.imaslivedb.ui.components.rememberSearchFiltered

data class UnitPickerUiState(
    val units: List<ImasUnit> = emptyList(),
    val brands: List<Brand> = emptyList(),
    val isLoading: Boolean = true
)

/** 曲ありユニットをロードするだけの軽量 ViewModel。ピッカー表示中だけ生存する。 */
class UnitPickerViewModel(app: Application) : AndroidViewModel(app) {
    private val unitRepo = AppModule.from(app).unitRepository
    private val statsRepo = AppModule.from(app).statsRepository
    private val _uiState = MutableStateFlow(UnitPickerUiState())
    val uiState: StateFlow<UnitPickerUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val units = runCatching { unitRepo.fetchUnitsForList() }.getOrDefault(emptyList())
            val brands = runCatching { statsRepo.fetchBrands() }.getOrDefault(emptyList())
            _uiState.value = UnitPickerUiState(units = units, brands = brands, isLoading = false)
        }
    }
}

private enum class UnitPickerDisplayMode { GRID, LIST }

/**
 * お題(投票)に新しい候補ユニットを追加するピッカー。IdolPollCandidatePicker のユニット版。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UnitPollCandidatePicker(
    alreadySelected: Set<String>,
    remaining: Int,
    onDismiss: () -> Unit,
    onConfirm: (List<String>) -> Unit,
    viewModel: UnitPickerViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var selection by remember { mutableStateOf(alreadySelected) }
    var query by remember { mutableStateOf("") }
    var selectedBrandId by remember { mutableStateOf<String?>(null) }
    var displayMode by remember { mutableStateOf(UnitPickerDisplayMode.GRID) }

    // 数百件を一気にスクロールするピッカー。行ごとに derive すると、その間ずっと 1 行 1 回
    // FFI を跨ぐ。行が組まれる前に母集団ぶんを 1 往復で温め、行はメモに当てる。
    // 鍵を filtered ではなく母集団にするのは、行が引く色が絞り込みで変わらないため
    // (打鍵のたびに温め直しても新しい組は 1 件も無い)。
    imasThemePrewarm(state.units) { state.units.map { it.id to it.brandId } }

    val matched = rememberSearchFiltered(state.units, query) { listOf(it.name, it.nameAlt, it.nameKana) }
    val filtered = remember(matched, selectedBrandId) {
        matched.filter { selectedBrandId == null || it.brandId == selectedBrandId }
    }
    val grouped = remember(filtered, state.brands) {
        state.brands.mapNotNull { brand ->
            val list = filtered.filter { it.brandId == brand.id }
            if (list.isEmpty()) null else brand to list
        }
    }
    val newlyAddedCount = (selection - alreadySelected).size
    val overRemaining = newlyAddedCount > remaining

    fun toggle(unit: ImasUnit) {
        selection = if (selection.contains(unit.id)) selection - unit.id else selection + unit.id
    }

    fun confirm() {
        // 選択は選択肢の表示順 (ブランド順 → 一覧の並び) で返す。
        // 何を入れて何を取り消すか・残りの票数での打ち切りはコア (planVoteSelection)。
        val ordered = state.brands
            .flatMap { brand -> state.units.filter { it.brandId == brand.id } }
            .map { it.id }
            .filter { it in selection }
        onConfirm(ordered + (selection - ordered.toSet()))
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            ImasSheetToolbar(
                kind = ImasSheetToolbarKind.Select(canFinish = selection != alreadySelected, onCancel = onDismiss, onFinish = ::confirm),
                title = "ユニットを選択 (${selection.size})"
            )
            Row(Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen), horizontalArrangement = Arrangement.End) {
                ImasIconButton(
                    icon = if (displayMode == UnitPickerDisplayMode.GRID) Icons.Filled.ViewList else Icons.Filled.GridView,
                    label = if (displayMode == UnitPickerDisplayMode.GRID) "リスト表示" else "グリッド表示",
                    size = ImasIconButtonSize.SMALL,
                    style = ImasIconButtonStyle.PLAIN,
                    onClick = {
                        displayMode = if (displayMode == UnitPickerDisplayMode.GRID) UnitPickerDisplayMode.LIST else UnitPickerDisplayMode.GRID
                    }
                )
            }

            BrandFilterChips(
                brands = state.brands.map { BrandFilterItem(it.id, it.shortName) },
                selectedBrandId = selectedBrandId,
                onBrandSelected = { selectedBrandId = it }
            )

            ImasSearchField(
                prompt = "ユニット名で検索",
                text = query,
                onTextChange = { query = it },
                modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
            )

            if (overRemaining) {
                ImasNotice(
                    kind = ImasNoticeKind.WARNING,
                    message = "残り${remaining}件まで選べます (現在+${newlyAddedCount}件)",
                    modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
                )
            }

            if (state.isLoading) {
                Box(Modifier.fillMaxSize().weight(1f), contentAlignment = Alignment.Center) { ImasLoadingState() }
            } else if (displayMode == UnitPickerDisplayMode.GRID) {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(4),
                    modifier = Modifier.fillMaxWidth().weight(1f).padding(horizontal = DS.Space.gap),
                    contentPadding = PaddingValues(vertical = DS.Space.gap)
                ) {
                    grouped.forEach { (brand, units) ->
                        item(key = "h_${brand.id}", span = { GridItemSpan(maxLineSpan) }) {
                            ImasSectionHeader(title = "${brand.shortName} (${units.size})", style = ImasSectionHeaderStyle.SMALL)
                        }
                        lazyGridItems(units, key = { it.id }) { unit ->
                            ImasUnitCell(
                                unit = unit,
                                isSelected = selection.contains(unit.id),
                                modifier = Modifier.padding(DS.Space.gapTight).imasPress { toggle(unit) }
                            )
                        }
                    }
                }
            } else {
                LazyColumn(modifier = Modifier.fillMaxWidth().weight(1f)) {
                    grouped.forEach { (brand, units) ->
                        item(key = "h_${brand.id}") {
                            ImasSectionHeader(
                                title = "${brand.shortName} (${units.size})",
                                style = ImasSectionHeaderStyle.SMALL,
                                contentPadding = PaddingValues(horizontal = DS.Space.screen, vertical = DS.Space.header)
                            )
                        }
                        lazyColumnItems(units, key = { it.id }) { unit ->
                            ImasSelectableRow(
                                title = unit.displayName,
                                isSelected = selection.contains(unit.id),
                                onClick = { toggle(unit) },
                                leading = ImasRowLeading.Custom(width = 40.dp) { ImasUnitAvatar(unit, size = 40.dp) }
                            )
                        }
                    }
                }
            }
        }
    }
}
