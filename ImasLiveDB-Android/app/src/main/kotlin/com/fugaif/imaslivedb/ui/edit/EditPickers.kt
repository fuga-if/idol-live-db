package com.fugaif.imaslivedb.ui.edit

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as lazyGridItems
import androidx.compose.foundation.lazy.items as lazyColumnItems
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.ConfirmationNumber
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
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
import com.fugaif.imaslivedb.data.model.ShowWithEventName
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.BrandFilterItem
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import com.fugaif.imaslivedb.ui.components.rememberSearchFiltered

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

/** iOS `ShowSearchPickerView` の移植。公演名 / イベント名で検索し、公演 1 件を選ぶ。 */
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
            Text(
                "公演を選択", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
            )
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text("公演名・イベント名で検索") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                trailingIcon = {
                    if (query.isNotEmpty()) {
                        IconButton(onClick = { query = "" }) { Icon(Icons.Filled.Clear, contentDescription = "クリア") }
                    }
                },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
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
                        Row(
                            modifier = Modifier.fillMaxWidth()
                                .clickable { onSelect(show) }
                                .padding(horizontal = 16.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Box(
                                modifier = Modifier.size(36.dp).clip(RoundedCornerShape(18.dp)).background(DS.fill),
                                contentAlignment = Alignment.Center
                            ) { Icon(Icons.Filled.ConfirmationNumber, contentDescription = null, tint = DS.ink2, modifier = Modifier.size(18.dp)) }
                            Column(Modifier.weight(1f)) {
                                Text(show.eventName, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = DS.ink,
                                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text("${show.name} ・ ${show.date.take(10)}", fontSize = 12.sp, color = DS.ink2,
                                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
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
    private val _results = MutableStateFlow<List<Song>>(emptyList())
    val results: StateFlow<List<Song>> = _results.asStateFlow()

    init {
        viewModelScope.launch { _results.value = songRepo.fetchSongs().map { it.song } }
    }

    fun search(query: String) {
        viewModelScope.launch {
            val filter = com.fugaif.imaslivedb.data.model.SongSearchFilter(
                title = query.ifBlank { null },
                excludeLiveOnly = false
            )
            _results.value = songRepo.fetchSongs(filter).map { it.song }.take(50)
        }
    }
}

/** 曲を 1 件選ぶだけの軽量ピッカー (iOS `SongSearchPickerView` の単一選択版)。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongPickerSheet(
    onDismiss: () -> Unit,
    onSelect: (Song) -> Unit,
    viewModel: SongPickerViewModel = viewModel()
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
            Text(
                "曲を選択", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
            )
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text("曲名で検索") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                trailingIcon = {
                    if (query.isNotEmpty()) {
                        IconButton(onClick = { query = "" }) { Icon(Icons.Filled.Clear, contentDescription = "クリア") }
                    }
                },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
            )
            if (results.isEmpty()) {
                ImasEmptyState(Icons.Filled.MusicNote, "見つかりません", "「$query」に一致する楽曲がありません")
            } else {
                LazyColumn(modifier = Modifier.fillMaxWidth().weight(1f)) {
                    lazyColumnItems(results, key = { it.id }) { song ->
                        Row(
                            modifier = Modifier.fillMaxWidth()
                                .clickable { onSelect(song) }
                                .padding(horizontal = 16.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Icon(Icons.Filled.MusicNote, contentDescription = null, tint = DS.ink2)
                            Text(song.title, fontSize = 15.sp, color = DS.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        }
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
            val idols = runCatching { idolRepo.fetchIdols(null) }.getOrDefault(emptyList())
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
    remember(state.idols) {
        ImasTheme.prewarm(state.idols.map { it.color to it.brandId })
    }

    // 語で絞ってからブランドで絞る (索引は母集団全体で組んであるため)。並びは入力順のまま。
    val matched = rememberSearchFiltered(state.idols, query) {
        listOf(it.name, it.nameKana, it.voiceActors, it.aliases)
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
            Text(
                "$title (${current.size})",
                fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
            )
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
            if (state.isLoading) {
                Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            } else {
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
                            Column(
                                modifier = Modifier.fillMaxWidth().padding(6.dp).clickable { toggle(idol) },
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Box(contentAlignment = Alignment.BottomEnd) {
                                    Box(modifier = Modifier.background(
                                        if (current.contains(idol.id)) DS.fill else androidx.compose.ui.graphics.Color.Transparent,
                                        CircleShape
                                    )) {
                                        ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 56.dp)
                                    }
                                    Icon(
                                        if (current.contains(idol.id)) Icons.Filled.CheckCircle else Icons.Filled.Circle,
                                        contentDescription = null,
                                        tint = if (current.contains(idol.id)) DS.success else DS.ink3,
                                        modifier = Modifier.size(16.dp).background(DS.bg, CircleShape)
                                    )
                                }
                                Text(
                                    idol.name, fontSize = 11.sp, color = DS.ink, maxLines = 1,
                                    overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center,
                                    modifier = Modifier.fillMaxWidth()
                                )
                            }
                        }
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("キャンセル") }
                Button(onClick = { onConfirm(current) }, modifier = Modifier.weight(1f)) { Text("決定") }
            }
        }
    }
}
