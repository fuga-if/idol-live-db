package com.fugaif.imaslivedb.ui.songs

import android.app.Application
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.SongCollectFilter
import com.fugaif.imaslivedb.data.model.SongMyMarkFilter
import com.fugaif.imaslivedb.data.model.SongSearchFilter
import com.fugaif.imaslivedb.data.model.SongSortOrder
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasFilterChip
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.components.NameFilterField
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.brandColor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** 曲タイプ (songs.song_type) の内部値と表示ラベル。iOS SongFilterView の songTypeChip と同じ並び。 */
private val SONG_TYPES = listOf("solo" to "ソロ", "unit" to "ユニット", "all" to "全体曲")

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
 * 曲一覧のフィルタシート (iOS `SongFilterView` の移植)。
 *
 * 編集中の値はすべてこのシートのローカル状態に持ち、「適用」でまとめて返す。
 * 触るたびに一覧を引き直さないのは、条件を 2〜3 個いじる間ずっと再取得が走るのを避けるため。
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
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
    var showOtherBrand by remember { mutableStateOf(currentShowOtherBrand) }
    var collectFilter by remember { mutableStateOf(currentCollectFilter) }
    var myMarkFilter by remember { mutableStateOf(currentMyMarkFilter) }

    val selectedIdolNames = remember(options.idols, idolIds) {
        options.idols.filter { idolIds.contains(it.id) }.map { it.name }
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
            FilterPage.MAIN -> Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(bottom = 32.dp)
            ) {
                Text(
                    text = "フィルター・並び替え",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
                )

                HorizontalDivider()

                // 表示形式
                SectionLabel("表示形式")
                ImasSegmented(
                    labels = listOf("楽曲", "アルバム", "シリーズ"),
                    selection = SongListMode.entries.indexOf(listMode),
                    onSelect = { listMode = SongListMode.entries[it] },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
                )

                // 楽曲表示にしか効かない条件は、表示形式がアルバム/シリーズのときは出さない
                // (集計カードには回収もマイマークも掛からないので、出すと効かない設定になる)。
                val songsMode = listMode == SongListMode.SONGS

                if (songsMode) {
                    Spacer(modifier = Modifier.height(8.dp))
                    HorizontalDivider()

                    // 現地回収
                    SectionLabel("現地回収")
                    ChipRow {
                        SongCollectFilter.entries.forEach { cf ->
                            ImasFilterChip(
                                label = cf.label,
                                selected = collectFilter == cf,
                                onClick = { collectFilter = cf }
                            )
                        }
                    }

                    HorizontalDivider()

                    // マイマーク (AND 条件)
                    SectionLabel("マイマーク")
                    SwitchRow(
                        title = "担当アイドルの曲のみ",
                        subtitle = "担当アイドルが歌唱者にいる曲だけ表示",
                        checked = myMarkFilter.requireMyPick,
                        tint = DS.pick,
                        onCheckedChange = { myMarkFilter = myMarkFilter.copy(requireMyPick = it) }
                    )
                    SwitchRow(
                        title = "お気に入りのみ",
                        checked = myMarkFilter.requireFavorite,
                        tint = DS.favorite,
                        onCheckedChange = { myMarkFilter = myMarkFilter.copy(requireFavorite = it) }
                    )
                    SwitchRow(
                        title = "メモがある曲のみ",
                        subtitle = "ON にした条件すべてに該当する曲 (AND) だけ表示",
                        checked = myMarkFilter.requireNote,
                        tint = DS.warning,
                        onCheckedChange = { myMarkFilter = myMarkFilter.copy(requireNote = it) }
                    )

                    HorizontalDivider()

                    // 並び順
                    SectionLabel("並び順")
                    ChipRow {
                        SongSortOrder.entries.forEach { order ->
                            ImasFilterChip(
                                label = order.label,
                                selected = selectedSort == order,
                                onClick = {
                                    // 並び順を変えたら方向は新しい並び順の既定へ戻す
                                    // (「多い順」のまま五十音順に切り替わると ん から始まって驚く)。
                                    if (selectedSort != order) sortAscending = null
                                    selectedSort = order
                                }
                            )
                        }
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    ChipRow {
                        ImasFilterChip(label = "既定", selected = sortAscending == null, onClick = { sortAscending = null })
                        ImasFilterChip(label = "昇順", selected = sortAscending == true, onClick = { sortAscending = true })
                        ImasFilterChip(label = "降順", selected = sortAscending == false, onClick = { sortAscending = false })
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                }

                HorizontalDivider()

                // ブランド (複数選択 = OR)
                SectionLabel("ブランド")
                FlowRow(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    ImasFilterChip(label = "全て", selected = brandIds.isEmpty(), onClick = { brandIds = emptySet() })
                    options.brands.forEach { brand ->
                        ImasFilterChip(
                            label = brand.shortName,
                            selected = brandIds.contains(brand.id),
                            tintColor = brandColor(brand.id),
                            onClick = {
                                brandIds =
                                    if (brandIds.contains(brand.id)) brandIds - brand.id else brandIds + brand.id
                            }
                        )
                    }
                }
                Spacer(modifier = Modifier.height(8.dp))

                if (songsMode) {
                    HorizontalDivider()

                    SwitchRow(
                        title = "ライブ限定曲を隠す",
                        subtitle = "セトリにしか無い曲(カバー等)を一覧から隠します。既定 ON",
                        checked = excludeLiveOnly,
                        onCheckedChange = { excludeLiveOnly = it }
                    )
                    SwitchRow(
                        title = "「その他」を表示",
                        subtitle = "歌枠で歌っただけのカバー等。既定では隠しています",
                        checked = showOtherBrand,
                        onCheckedChange = { showOtherBrand = it }
                    )
                    SwitchRow(
                        title = "リミックスを含む",
                        subtitle = "アレンジ・リミックス曲を表示",
                        checked = includeRemixes,
                        onCheckedChange = { includeRemixes = it }
                    )

                    HorizontalDivider()

                    // 曲タイプ
                    SectionLabel("曲タイプ")
                    ChipRow {
                        ImasFilterChip(label = "全て", selected = songType == null, onClick = { songType = null })
                        SONG_TYPES.forEach { (value, label) ->
                            ImasFilterChip(
                                label = label,
                                selected = songType == value,
                                onClick = { songType = if (songType == value) null else value }
                            )
                        }
                    }
                    Spacer(modifier = Modifier.height(8.dp))

                    HorizontalDivider()

                    // アイドル (複数選択)
                    PickerRow(
                        label = "アイドル",
                        value = if (selectedIdolNames.isEmpty()) {
                            null
                        } else {
                            // 全員ぶん並べると行が伸びるので、3 人までは名前・それ以上は人数。
                            if (selectedIdolNames.size <= 3) {
                                selectedIdolNames.joinToString("・")
                            } else {
                                "${selectedIdolNames.take(2).joinToString("・")} 他${selectedIdolNames.size - 2}人"
                            }
                        },
                        onClick = { page = FilterPage.IDOLS }
                    )

                    // 作詞 / 作曲 / 編曲
                    SectionLabel("作詞 / 作曲 / 編曲者")
                    NameFilterField(
                        prompt = "名前を入力",
                        value = songwriter,
                        onValueChange = { songwriter = it }
                    )

                    HorizontalDivider()

                    PickerRow(label = "シリーズ", value = seriesGroup, onClick = { page = FilterPage.SERIES })
                    PickerRow(label = "CDシリーズ", value = cdSeries, onClick = { page = FilterPage.CD_SERIES })
                    PickerRow(label = "ライブで絞込", value = liveName, onClick = { page = FilterPage.LIVE })
                }

                HorizontalDivider()

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    TextButton(
                        onClick = {
                            listMode = SongListMode.SONGS
                            selectedSort = SongSortOrder.TITLE_KANA
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
                            showOtherBrand = false
                            collectFilter = SongCollectFilter.ALL
                            myMarkFilter = SongMyMarkFilter()
                        },
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("リセット")
                    }
                    Button(
                        onClick = {
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
                                    excludeLiveOnly = excludeLiveOnly
                                ),
                                selectedSort,
                                sortAscending,
                                showOtherBrand,
                                collectFilter,
                                myMarkFilter,
                                listMode
                            )
                        },
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("適用")
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelLarge,
        color = DS.ink2,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
    )
}

/**
 * チップ置き場。セクションごとに同じ余白で並べる。
 * 並び順のように 5 個並ぶ列があるので、はみ出したら折り返す (横スクロールにすると
 * 端のチップが隠れて「並び順が 3 つしかない」ように見える)。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChipRow(content: @Composable () -> Unit) {
    FlowRow(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        content()
    }
}

/** 選択ページへ降りる行。選択中はその値を、未選択なら「選択なし」を出す。 */
@Composable
private fun PickerRow(label: String, value: String?, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = label, style = MaterialTheme.typography.bodyMedium, color = DS.ink)
        Spacer(modifier = Modifier.weight(1f))
        Text(
            text = value ?: "選択なし",
            style = MaterialTheme.typography.bodyMedium,
            color = if (value == null) DS.ink3 else DS.ink2,
            maxLines = 1
        )
        Icon(Icons.Filled.ChevronRight, contentDescription = null, tint = DS.ink3)
    }
    HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
}

@Composable
private fun SwitchRow(
    title: String,
    subtitle: String? = null,
    checked: Boolean,
    tint: Color? = null,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, style = MaterialTheme.typography.bodyMedium)
            if (subtitle != null) {
                Text(text = subtitle, style = MaterialTheme.typography.bodySmall, color = DS.ink2)
            }
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = if (tint != null) {
                SwitchDefaults.colors(checkedTrackColor = tint, checkedThumbColor = DS.surface)
            } else {
                SwitchDefaults.colors()
            }
        )
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
