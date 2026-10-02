package com.fugaif.imaslivedb.ui.songs

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import com.fugaif.imaslivedb.data.model.SongCollectFilter
import com.fugaif.imaslivedb.data.model.SongMyMarkFilter
import com.fugaif.imaslivedb.data.model.SongSearchFilter
import com.fugaif.imaslivedb.data.model.SongSortOrder
import com.fugaif.imaslivedb.data.model.Vocab
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasBrandPicker
import com.fugaif.imaslivedb.ui.designsystem.ImasChipFlow
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasMenuRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasTextFieldRow
import com.fugaif.imaslivedb.ui.designsystem.ImasToggleRow
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** 曲タイプの絞り込み。今までどおり先頭の 3 種 (ソロ / ユニット / 全体曲)。語はコアの vocabulary。 */
private val SONG_TYPES: List<Pair<String, String>>
    get() = Vocab.table.songTypes.take(3).map { it.value to it.shortLabel }

/** フィルタシートで開いている「ページ」。[FilterPickerPage] の push/pop 相当。 */
private enum class FilterPage { MAIN, IDOLS, SERIES, CD_SERIES, LIVE }

/** ピッカーの候補 (ブランド/アイドル/シリーズ/CDシリーズ/ライブ名) をまとめて読む。 */
data class SongFilterOptions(
    val brands: List<Brand> = emptyList(),
    val idols: List<Idol> = emptyList(),
    val cdSeries: List<String> = emptyList(),
    val seriesGroups: List<String> = emptyList(),
    val eventNames: List<String> = emptyList()
)

class SongFilterOptionsViewModel(app: Application) : AndroidViewModel(app) {
    private val _options = MutableStateFlow(SongFilterOptions())
    val options: StateFlow<SongFilterOptions> = _options.asStateFlow()

    init {
        val module = AppModule.from(app)
        viewModelScope.launch {
            _options.value = SongFilterOptions(
                brands = runCatching { module.statsRepository.fetchBrands() }.getOrDefault(emptyList()),
                idols = runCatching { module.idolRepository.fetchIdolsForList() }.getOrDefault(emptyList()),
                cdSeries = runCatching { module.songRepository.fetchCdSeriesList() }.getOrDefault(emptyList()),
                seriesGroups = runCatching { module.songRepository.fetchSeriesGroupList() }.getOrDefault(emptyList()),
                eventNames = runCatching { module.songRepository.fetchEventNames() }.getOrDefault(emptyList())
            )
        }
    }
}

/**
 * 曲一覧のフィルタシート (iOS `SongFilterView` の移植)。地は `ModalBottomSheet` のまま
 * (iOS の NavigationStack+List に当たる Android の慣習は `ModalBottomSheet` + `ImasListSection` の
 * 組み合わせ。`ui/mastery/MasteryScreen.kt` の絞り込みシートと同じ組み方)。
 *
 * 編集中の値はすべてこのシートのローカル状態に持ち、「適用」でまとめて返す。
 * 触るたびに一覧を引き直さないのは、条件を 2〜3 個いじる間ずっと再取得が走るのを避けるため。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongFilterSheet(
    currentFilter: SongSearchFilter,
    currentSortOrder: SongSortOrder,
    currentSortAscending: Boolean?,
    currentShowOtherBrand: Boolean,
    currentCollectFilter: SongCollectFilter,
    currentMyMarkFilter: SongMyMarkFilter,
    currentListMode: SongListMode,
    onDismiss: () -> Unit,
    onApply: (
        filter: SongSearchFilter,
        sortOrder: SongSortOrder,
        sortAscending: Boolean?,
        showOtherBrand: Boolean,
        collectFilter: SongCollectFilter,
        myMarkFilter: SongMyMarkFilter,
        listMode: SongListMode
    ) -> Unit,
    optionsViewModel: SongFilterOptionsViewModel = viewModel()
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val options by optionsViewModel.options.collectAsState()

    var page by remember { mutableStateOf(FilterPage.MAIN) }
    var listMode by remember { mutableStateOf(currentListMode) }
    var selectedSort by remember { mutableStateOf(currentSortOrder) }
    var sortAscending by remember { mutableStateOf(currentSortAscending) }
    var brandIds by remember { mutableStateOf(currentFilter.brandIds) }
    var idolIds by remember { mutableStateOf(currentFilter.idolIds.orEmpty().toSet()) }
    var songwriter by remember { mutableStateOf(currentFilter.songwriter.orEmpty()) }
    var seriesGroup by remember { mutableStateOf(currentFilter.seriesGroup) }
    var cdSeries by remember { mutableStateOf(currentFilter.cdSeries) }
    var liveName by remember { mutableStateOf(currentFilter.liveName) }
    var songType by remember { mutableStateOf(currentFilter.songType) }
    var includeRemixes by remember { mutableStateOf(currentFilter.includeRemixes) }
    var excludeLiveOnly by remember { mutableStateOf(currentFilter.excludeLiveOnly) }
    var kamisabiOnly by remember { mutableStateOf(currentFilter.kamisabiOnly) }
    var showOtherBrand by remember { mutableStateOf(currentShowOtherBrand) }
    var collectFilter by remember { mutableStateOf(currentCollectFilter) }
    var myMarkFilter by remember { mutableStateOf(currentMyMarkFilter) }

    val selectedIdolNames = remember(options.idols, idolIds) {
        options.idols.filter { idolIds.contains(it.id) }.map { it.name }
    }

    fun resetAll() {
        listMode = SongListMode.SONGS
        selectedSort = SONG_LIST_DEFAULT_SORT
        sortAscending = null
        brandIds = emptySet()
        idolIds = emptySet()
        songwriter = ""
        seriesGroup = null
        cdSeries = null
        liveName = null
        songType = null
        includeRemixes = false
        excludeLiveOnly = true
        kamisabiOnly = false
        showOtherBrand = false
        collectFilter = SongCollectFilter.ALL
        myMarkFilter = SongMyMarkFilter()
    }

    fun apply() {
        onApply(
            currentFilter.copy(
                brandIds = brandIds,
                idolIds = idolIds.takeIf { it.isNotEmpty() }?.toList(),
                songwriter = songwriter.ifBlank { null },
                seriesGroup = seriesGroup,
                cdSeries = cdSeries,
                liveName = liveName,
                songType = songType,
                includeRemixes = includeRemixes,
                excludeLiveOnly = excludeLiveOnly,
                kamisabiOnly = kamisabiOnly
            ),
            selectedSort,
            sortAscending,
            showOtherBrand,
            collectFilter,
            myMarkFilter,
            listMode
        )
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        when (page) {
            FilterPage.IDOLS -> IdolMultiPickerPage(
                idols = options.idols,
                brands = options.brands,
                selected = idolIds,
                onBack = { page = FilterPage.MAIN },
                onToggle = { id -> idolIds = if (idolIds.contains(id)) idolIds - id else idolIds + id },
                onClear = { idolIds = emptySet() }
            )
            FilterPage.SERIES -> SingleValuePickerPage(
                title = "シリーズ",
                items = options.seriesGroups,
                selected = seriesGroup,
                onBack = { page = FilterPage.MAIN },
                onSelect = { seriesGroup = it; page = FilterPage.MAIN }
            )
            FilterPage.CD_SERIES -> SingleValuePickerPage(
                title = "CDシリーズ",
                items = options.cdSeries,
                selected = cdSeries,
                onBack = { page = FilterPage.MAIN },
                onSelect = { cdSeries = it; page = FilterPage.MAIN }
            )
            FilterPage.LIVE -> SingleValuePickerPage(
                title = "ライブ",
                items = options.eventNames,
                selected = liveName,
                onBack = { page = FilterPage.MAIN },
                onSelect = { liveName = it; page = FilterPage.MAIN }
            )
            FilterPage.MAIN -> Column(modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
                // 左=リセット・右=適用はこの帯にだけ置く (DS §2.6)。
                ImasFilterSheetToolbar(canReset = true, onReset = ::resetAll, onApply = ::apply, title = "フィルタ・並び替え")

                // 表示形式
                ImasListSection("表示形式") {
                    ImasSegmented(
                        labels = listOf("楽曲", "アルバム", "シリーズ"),
                        selection = SongListMode.entries.indexOf(listMode),
                        onSelect = { listMode = SongListMode.entries[it] },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)
                    )
                }

                // 楽曲表示にしか効かない条件は、表示形式がアルバム/シリーズのときは出さない
                // (集計カードには回収もマイマークも掛からないので、出すと効かない設定になる)。
                val songsMode = listMode == SongListMode.SONGS

                if (songsMode) {
                    // 現地回収
                    ImasListSection("現地回収") {
                        ImasChipFlow(Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)) {
                            SongCollectFilter.entries.forEach { cf ->
                                ImasFilterChip(label = cf.label, selected = collectFilter == cf, onClick = { collectFilter = cf })
                            }
                        }
                    }

                    // マイマーク (AND 条件)。アイコンは今の Android の SwitchRow に無かったので足さない
                    // (iOS は heart.fill 等を付けるが、見た目の移し替えだけに留める)。
                    ImasListSection("マイマーク", footer = "チェック ON で AND 条件絞り込み") {
                        ImasToggleRow(
                            title = "担当アイドルの曲のみ",
                            subtitle = "担当アイドルが歌唱者にいる曲だけ表示",
                            isOn = myMarkFilter.requireMyPick,
                            onCheckedChange = { myMarkFilter = myMarkFilter.copy(requireMyPick = it) }
                        )
                        ImasToggleRow(
                            title = "お気に入りのみ",
                            isOn = myMarkFilter.requireFavorite,
                            onCheckedChange = { myMarkFilter = myMarkFilter.copy(requireFavorite = it) }
                        )
                        ImasToggleRow(
                            title = "メモがある曲のみ",
                            isOn = myMarkFilter.requireNote,
                            onCheckedChange = { myMarkFilter = myMarkFilter.copy(requireNote = it) }
                        )
                    }

                    // 並び順
                    ImasListSection("並び順") {
                        ImasMenuRow(
                            title = "並び順",
                            options = SongSortOrder.entries,
                            selection = selectedSort,
                            onSelect = {
                                // 並び順を変えたら方向は新しい並び順の既定へ戻す
                                // (「多い順」のまま五十音順に切り替わると ん から始まって驚く)。
                                if (selectedSort != it) sortAscending = null
                                selectedSort = it
                            },
                            label = { it.label }
                        )
                        SortDirectionRow(sortAscending = sortAscending, onChange = { sortAscending = it })
                    }
                }

                // ブランド (複数選択 = OR)
                ImasListSection("ブランド") {
                    ImasBrandPicker(
                        brands = options.brands,
                        selection = brandIds,
                        onSelectionChange = { brandIds = it },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)
                    )
                }

                ImasListSection {
                    ImasToggleRow(
                        title = "ライブ限定曲を隠す",
                        subtitle = "セトリにしか無い曲(カバー等)を一覧から隠します。既定 ON",
                        isOn = excludeLiveOnly,
                        onCheckedChange = { excludeLiveOnly = it }
                    )
                    ImasToggleRow(
                        title = "「その他」を表示",
                        subtitle = "歌枠で歌っただけのカバー等。既定では隠しています",
                        isOn = showOtherBrand,
                        onCheckedChange = { showOtherBrand = it }
                    )
                }

                if (songsMode) {
                    ImasListSection {
                        ImasToggleRow(
                            title = "リミックスを含む",
                            subtitle = "アレンジ・リミックス曲を表示",
                            isOn = includeRemixes,
                            onCheckedChange = { includeRemixes = it }
                        )
                    }

                    ImasListSection(footer = "音楽カードゲーム KAMISABI にカードがある曲だけ表示します。") {
                        ImasToggleRow(
                            title = "KAMISABI収録のみ",
                            isOn = kamisabiOnly,
                            onCheckedChange = { kamisabiOnly = it }
                        )
                    }

                    // 曲タイプ
                    ImasListSection("曲タイプ") {
                        ImasChipFlow(Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)) {
                            ImasFilterChip(label = "全て", selected = songType == null, onClick = { songType = null })
                            SONG_TYPES.forEach { (value, label) ->
                                ImasFilterChip(
                                    label = label,
                                    selected = songType == value,
                                    onClick = { songType = if (songType == value) null else value }
                                )
                            }
                        }
                    }

                    // アイドル (複数選択)
                    ImasListSection("アイドル") {
                        ImasNavRow(
                            title = "アイドル",
                            value = if (selectedIdolNames.isEmpty()) {
                                "選択なし"
                            } else if (selectedIdolNames.size <= 3) {
                                // 全員ぶん並べると行が伸びるので、3 人までは名前・それ以上は人数。
                                selectedIdolNames.joinToString("・")
                            } else {
                                "${selectedIdolNames.take(2).joinToString("・")} 他${selectedIdolNames.size - 2}人"
                            },
                            onClick = { page = FilterPage.IDOLS }
                        )
                    }

                    // 作詞 / 作曲 / 編曲
                    ImasListSection("作詞 / 作曲 / 編曲者") {
                        ImasTextFieldRow(title = "名前", text = songwriter, onTextChange = { songwriter = it }, prompt = "名前を入力")
                    }

                    ImasListSection("シリーズ") {
                        ImasNavRow(title = "シリーズ", value = seriesGroup ?: "選択なし", onClick = { page = FilterPage.SERIES })
                    }
                    ImasListSection("CDシリーズ") {
                        ImasNavRow(title = "CDシリーズ", value = cdSeries ?: "選択なし", onClick = { page = FilterPage.CD_SERIES })
                    }
                    ImasListSection("ライブで絞込") {
                        ImasNavRow(title = "ライブ", value = liveName ?: "選択なし", onClick = { page = FilterPage.LIVE })
                    }
                }
            }
        }
    }
}

/** 並び順の方向 (既定・昇順・降順)。「既定」は Android だけの 3 つ目の選択肢 (null = その並び順自身の既定)。 */
@Composable
private fun SortDirectionRow(sortAscending: Boolean?, onChange: (Boolean?) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = DS.Size.touch).padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowVCompact),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasText("方向", ImasTextRole.ROW_LABEL, modifier = Modifier.weight(1f))
        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            ImasFilterChip(label = "既定", selected = sortAscending == null, onClick = { onChange(null) })
            ImasFilterChip(label = "昇順", selected = sortAscending == true, onClick = { onChange(true) })
            ImasFilterChip(label = "降順", selected = sortAscending == false, onClick = { onChange(false) })
        }
    }
}

private val SongSortOrder.label: String
    get() = when (this) {
        SongSortOrder.TITLE_KANA -> "五十音順"
        SongSortOrder.RELEASE_DATE -> "リリース日順"
        SongSortOrder.PERFORMANCE_COUNT -> "披露回数順"
        SongSortOrder.COLLECTED_COUNT -> "現地回収回数順"
        SongSortOrder.COLLECTED_RATE -> "回収率順"
    }

private val SongCollectFilter.label: String
    get() = when (this) {
        SongCollectFilter.ALL -> "すべて"
        SongCollectFilter.COLLECTED -> "回収済のみ"
        SongCollectFilter.UNCOLLECTED -> "未回収のみ"
    }
