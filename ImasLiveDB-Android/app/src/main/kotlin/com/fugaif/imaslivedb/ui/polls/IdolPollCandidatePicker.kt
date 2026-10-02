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
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.BrandFilterItem
import com.fugaif.imaslivedb.ui.components.ImasIdolCell
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
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.imasThemePrewarm
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import com.fugaif.imaslivedb.ui.components.rememberSearchFiltered

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
            val idols = runCatching { idolRepo.fetchIdols() }.getOrDefault(emptyList())
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

    // 数百件を一気にスクロールするピッカー。行ごとに derive すると、その間ずっと 1 行 1 回
    // FFI を跨ぐ。行が組まれる前に母集団ぶんを 1 往復で温め、行はメモに当てる。
    // 鍵を filtered ではなく母集団にするのは、行が引く色が絞り込みで変わらないため
    // (打鍵のたびに温め直しても新しい組は 1 件も無い)。
    imasThemePrewarm(state.idols) { state.idols.map { it.color to it.brandId } }

    // 語で絞ってからブランドで絞る (索引は母集団全体で組んであるため)。並びは入力順のまま。
    // CV 名・別名でも引けるようにする (声優名で探すのは主要な導線)。
    val matched = rememberSearchFiltered(state.idols, query) {
        listOf(it.name, it.nameKana, it.currentVoiceActor, it.aliases)
    }
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

    fun toggle(idol: Idol) {
        selection = if (selection.contains(idol.id)) selection - idol.id else selection + idol.id
    }

    fun confirm() {
        // 選択は選択肢の表示順 (ブランド順 → 一覧の並び) で返す。
        // 何を入れて何を取り消すか・残りの票数での打ち切りはコア (planVoteSelection)。
        val ordered = state.brands
            .flatMap { brand -> state.idols.filter { it.brandId == brand.id } }
            .map { it.id }
            .filter { it in selection }
        onConfirm(ordered + (selection - ordered.toSet()))
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            ImasSheetToolbar(
                kind = ImasSheetToolbarKind.Select(canFinish = selection != alreadySelected, onCancel = onDismiss, onFinish = ::confirm),
                title = "出演者を選択 (${selection.size})"
            )
            Row(Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen), horizontalArrangement = Arrangement.End) {
                ImasIconButton(
                    icon = if (displayMode == PickerDisplayMode.GRID) Icons.Filled.ViewList else Icons.Filled.GridView,
                    label = if (displayMode == PickerDisplayMode.GRID) "リスト表示" else "グリッド表示",
                    size = ImasIconButtonSize.SMALL,
                    style = ImasIconButtonStyle.PLAIN,
                    onClick = {
                        displayMode = if (displayMode == PickerDisplayMode.GRID) PickerDisplayMode.LIST else PickerDisplayMode.GRID
                    }
                )
            }

            BrandFilterChips(
                brands = state.brands.map { BrandFilterItem(it.id, it.shortName) },
                selectedBrandId = selectedBrandId,
                onBrandSelected = { selectedBrandId = it }
            )

            ImasSearchField(
                prompt = "アイドル名 / CV名で検索",
                text = query,
                onTextChange = { query = it },
                modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
            )

            if (overRemaining) {
                ImasNotice(
                    kind = ImasNoticeKind.WARNING,
                    message = "残り${remaining}人まで選べます (現在+${newlyAddedCount}人)",
                    modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
                )
            }

            if (state.isLoading) {
                Box(Modifier.fillMaxSize().weight(1f), contentAlignment = Alignment.Center) { ImasLoadingState() }
            } else if (displayMode == PickerDisplayMode.GRID) {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(4),
                    modifier = Modifier.fillMaxWidth().weight(1f).padding(horizontal = DS.Space.gap),
                    contentPadding = PaddingValues(vertical = DS.Space.gap)
                ) {
                    grouped.forEach { (brand, idols) ->
                        item(key = "h_${brand.id}", span = { GridItemSpan(maxLineSpan) }) {
                            ImasSectionHeader(title = "${brand.shortName} (${idols.size})", style = ImasSectionHeaderStyle.SMALL)
                        }
                        lazyGridItems(idols, key = { it.id }) { idol ->
                            ImasIdolCell(
                                idol = idol,
                                isPick = false,
                                isSelected = selection.contains(idol.id),
                                modifier = Modifier.padding(DS.Space.gapTight).imasPress { toggle(idol) }
                            )
                        }
                    }
                }
            } else {
                LazyColumn(modifier = Modifier.fillMaxWidth().weight(1f)) {
                    grouped.forEach { (brand, idols) ->
                        item(key = "h_${brand.id}") {
                            ImasSectionHeader(
                                title = "${brand.shortName} (${idols.size})",
                                style = ImasSectionHeaderStyle.SMALL,
                                contentPadding = PaddingValues(horizontal = DS.Space.screen, vertical = DS.Space.header)
                            )
                        }
                        lazyColumnItems(idols, key = { it.id }) { idol ->
                            ImasSelectableRow(
                                title = idol.name,
                                isSelected = selection.contains(idol.id),
                                onClick = { toggle(idol) },
                                leading = ImasRowLeading.Avatar(label = idol.shortName, seed = idol.color, brand = idol.brandId, entityId = idol.id),
                                seed = idol.color
                            )
                        }
                    }
                }
            }
        }
    }
}
