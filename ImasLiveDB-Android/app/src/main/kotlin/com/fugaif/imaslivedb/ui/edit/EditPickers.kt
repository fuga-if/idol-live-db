package com.fugaif.imaslivedb.ui.edit

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as lazyGridItems
import androidx.compose.foundation.lazy.items as lazyColumnItems
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ShowWithEventName
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.BrandFilterItem
import com.fugaif.imaslivedb.ui.components.ImasIdolCell
import com.fugaif.imaslivedb.ui.components.rememberSearchFiltered
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasSearchField
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasShowRow
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.imasThemePrewarm
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.PickedSongRecord

// ---------------------------------------------------------------------------
// Show picker (セトリ編集の対象公演を選ぶ)
// ---------------------------------------------------------------------------

/** 検索語入力ごとに DB を引くだけの軽量 ViewModel。 */
class ShowPickerViewModel(app: Application) : AndroidViewModel(app) {
    private val eventRepo = AppModule.from(app).eventRepository
    private val _results = MutableStateFlow<List<ShowWithEventName>>(emptyList())
    val results: StateFlow<List<ShowWithEventName>> = _results.asStateFlow()

    init {
        viewModelScope.launch { _results.value = eventRepo.searchShows("") }
    }

    fun search(query: String) {
        viewModelScope.launch { _results.value = eventRepo.searchShows(query) }
    }
}

/**
 * iOS `ShowSearchPickerView` の移植。公演名 / イベント名で検索し、公演 1 件を選ぶ。
 * 選んだ瞬間に閉じる 1 択ピッカーなので、ツールバーは × だけ (docs/DESIGN_SYSTEM.md §2.5)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShowSearchPickerSheet(
    onDismiss: () -> Unit,
    onSelect: (ShowWithEventName) -> Unit,
    viewModel: ShowPickerViewModel = viewModel()
) {
    val results by viewModel.results.collectAsState()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var query by remember { mutableStateOf("") }

    LaunchedEffect(query) {
        kotlinx.coroutines.delay(200)
        viewModel.search(query)
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.9f)) {
            ImasSheetToolbar(kind = ImasSheetToolbarKind.Read(onClose = onDismiss), title = "公演を選択")
            ImasSearchField(
                prompt = "公演名・イベント名で検索",
                text = query,
                onTextChange = { query = it },
                modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
            )
            if (results.isEmpty()) {
                ImasEmptyState(
                    icon = Icons.Filled.ConfirmationNumber,
                    title = "見つかりません",
                    message = if (query.isEmpty()) "最近の公演がここに表示されます" else "「$query」に一致する公演がありません"
                )
            } else {
                LazyColumn(modifier = Modifier.fillMaxWidth().weight(1f)) {
                    lazyColumnItems(results, key = { it.id }) { show ->
                        ImasShowRow(
                            date = show.date.take(10),
                            title = show.eventName,
                            subtitle = "${show.name} ・ ${show.date.take(10)}",
                            showsChevron = false,
                            subtitleLineLimit = Int.MAX_VALUE,
                            modifier = Modifier.imasRowPress(onClick = { onSelect(show) })
                        )
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Song picker (セトリの1行に曲を割り当てる)
// ---------------------------------------------------------------------------

class SongPickerViewModel(app: Application) : AndroidViewModel(app) {
    private val songRepo = AppModule.from(app).songRepository
    /** null = 読み込み中。 */
    private val _songs = MutableStateFlow<List<PickedSongRecord>?>(null)
    val songs: StateFlow<List<PickedSongRecord>?> = _songs.asStateFlow()

    init {
        viewModelScope.launch { _songs.value = songRepo.fetchSongsForPicker() }
    }
}

/**
 * 曲を 1 件選ぶだけの軽量ピッカー (iOS `SongPickerView` と同じ)。
 *
 * 母集団は全曲 (派生曲も選べる)。絞り込みはコアの索引で、読みでも引ける。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongPickerSheet(
    onDismiss: () -> Unit,
    onSelect: (PickedSongRecord) -> Unit,
    viewModel: SongPickerViewModel = viewModel()
) {
    val songs by viewModel.songs.collectAsState()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var query by remember { mutableStateOf("") }
    val results = rememberSearchFiltered(songs.orEmpty(), query) { listOf(it.title, it.titleKana) }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.9f)) {
            ImasSheetToolbar(kind = ImasSheetToolbarKind.Read(onClose = onDismiss), title = "曲を選択")
            ImasSearchField(
                prompt = "曲名で検索",
                text = query,
                onTextChange = { query = it },
                modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
            )
            if (songs == null) {
                ImasLoadingState(Modifier.weight(1f))
            } else if (results.isEmpty()) {
                ImasEmptyState(Icons.Filled.MusicNote, "見つかりません", "「$query」に一致する楽曲がありません")
            } else {
                LazyColumn(modifier = Modifier.fillMaxWidth().weight(1f)) {
                    lazyColumnItems(results, key = { it.id }) { song ->
                        ImasRow(
                            title = song.title,
                            leading = ImasRowLeading.Icon(Icons.Filled.MusicNote, tone = ImasIconTileTone.NEUTRAL),
                            titleLineLimit = 2,
                            modifier = Modifier.imasRowPress(onClick = { onSelect(song) })
                        )
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Idol multi-select (セトリの1行の出演者を選ぶ。追加も解除も自由)
// ---------------------------------------------------------------------------

data class IdolMultiPickerUiState(
    val idols: List<Idol> = emptyList(),
    val brands: List<Brand> = emptyList(),
    val isLoading: Boolean = true
)

class IdolMultiSelectViewModel(app: Application) : AndroidViewModel(app) {
    private val idolRepo = AppModule.from(app).idolRepository
    private val statsRepo = AppModule.from(app).statsRepository
    private val _uiState = MutableStateFlow(IdolMultiPickerUiState())
    val uiState: StateFlow<IdolMultiPickerUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val idols = runCatching { idolRepo.fetchIdols() }.getOrDefault(emptyList())
            val brands = runCatching { statsRepo.fetchBrands() }.getOrDefault(emptyList())
            _uiState.value = IdolMultiPickerUiState(idols = idols, brands = brands, isLoading = false)
        }
    }
}

/**
 * アイドルを複数選ぶ。既存選択の解除も含め自由にトグルできる (お題ピッカーと違い一方通行ではない)。
 *
 * セトリ 1 行の出演者と、曲の歌唱アイドル (SongArtist role=original) の両方で使うので、
 * 見出しだけ [title] で差し替える。中身は同じ母集団・同じ絞り込みでよい。
 * 複数選択シートなのでツールバーは左 = キャンセル、右 = 完了 (docs/DESIGN_SYSTEM.md §2.5)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IdolMultiSelectSheet(
    selected: Set<String>,
    onDismiss: () -> Unit,
    onConfirm: (Set<String>) -> Unit,
    title: String = "出演者を選択",
    viewModel: IdolMultiSelectViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var current by remember { mutableStateOf(selected) }
    var query by remember { mutableStateOf("") }
    var selectedBrandId by remember { mutableStateOf<String?>(null) }

    // 数百件を一気にスクロールするピッカー。行ごとに derive すると、その間ずっと 1 行 1 回
    // FFI を跨ぐ。行が組まれる前に母集団ぶんを 1 往復で温め、行はメモに当てる。
    // 鍵を filtered ではなく母集団にするのは、行が引く色が絞り込みで変わらないため
    // (打鍵のたびに温め直しても新しい組は 1 件も無い)。
    imasThemePrewarm(state.idols) { state.idols.map { it.color to it.brandId } }

    // 語で絞ってからブランドで絞る (索引は母集団全体で組んであるため)。並びは入力順のまま。
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

    fun toggle(idol: Idol) {
        current = if (current.contains(idol.id)) current - idol.id else current + idol.id
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            ImasSheetToolbar(
                kind = ImasSheetToolbarKind.Select(canFinish = true, onCancel = onDismiss, onFinish = { onConfirm(current) }),
                title = "$title (${current.size})"
            )
            BrandFilterChips(
                brands = state.brands.map { BrandFilterItem(it.id, it.shortName) },
                selectedBrandId = selectedBrandId,
                onBrandSelected = { selectedBrandId = it }
            )
            ImasSearchField(
                prompt = "アイドル名で検索",
                text = query,
                onTextChange = { query = it },
                modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
            )
            if (state.isLoading) {
                ImasLoadingState(Modifier.weight(1f))
            } else {
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
                                isSelected = current.contains(idol.id),
                                modifier = Modifier.padding(DS.Space.gapTight).imasPress { toggle(idol) }
                            )
                        }
                    }
                }
            }
        }
    }
}
