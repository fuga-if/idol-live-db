package com.fugaif.imaslivedb.ui.mastery

import androidx.compose.foundation.background
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.ui.components.*
import com.fugaif.imaslivedb.ui.designsystem.*
import com.fugaif.imaslivedb.ui.theme.*
import com.fugaif.imaslivedb.ui.theme.imasTheme
import uniffi.imas_core.MasteryAxis
import uniffi.imas_core.MasteryBulkScope
import uniffi.imas_core.MasteryGroup
import uniffi.imas_core.MasteryGroupSort
import uniffi.imas_core.MasteryProgressFilter

private val AXIS_LABELS = listOf("CDシリーズ", "ユニット", "年代")
private val AXES = listOf(MasteryAxis.SERIES, MasteryAxis.UNIT, MasteryAxis.YEAR)

fun progressLabel(v: MasteryProgressFilter): String = when (v) {
    MasteryProgressFilter.ALL -> "すべて"
    MasteryProgressFilter.HEARD_BUT_UNSET -> "聴いたのに未設定"
    MasteryProgressFilter.HAS_UNSET -> "未設定あり"
    MasteryProgressFilter.UNTOUCHED -> "手つかず"
    MasteryProgressFilter.COMPLETE -> "完了"
}

fun sortLabel(v: MasteryGroupSort): String = when (v) {
    MasteryGroupSort.SONG_COUNT -> "曲数順"
    MasteryGroupSort.PROGRESS_ASC -> "進み具合が低い順"
    MasteryGroupSort.PROGRESS_DESC -> "進み具合が高い順"
    MasteryGroupSort.NAME -> "名前順"
}

/**
 * 習熟度ダッシュボード。iOS `MasteryView` の移植。
 *
 * 体裁は回収ダッシュボード (`StatsScreen`) に倣う — 同じ「全体の進捗 + 群別の進捗 +
 * 対象の一覧」の形なので、そこだけ別の組み方にすると進捗の見せ方が 2 通りになる。
 *
 * ⚠️ 群の一覧は **[LazyColumn]**。ユニット軸は 1,000 群を超えるので、
 * 非遅延の Column に積むと開いた瞬間に固まる。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MasteryScreen(
    onOpenSong: (String) -> Unit,
    viewModel: MasteryViewModel = viewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val detail by viewModel.detail.collectAsState()
    var showFilter by remember { mutableStateOf(false) }
    // 長押しされた群 (null = シートを出さない)。まだ付けていない曲だけをまとめて付ける。
    var bulkTarget by remember { mutableStateOf<MasteryGroup?>(null) }

    // 群の詳細はナビを増やさず画面内で差し替える (StatsScreen と同じ流儀)。
    detail?.let { d ->
        MasteryGroupDetailScreen(
            group = d.group, scale = state.scale, songs = d.songs,
            collectedIds = d.collectedIds,
            onBack = viewModel::closeGroup,
            onOpenSong = onOpenSong,
            onSetLevel = viewModel::setMastery,
            onBulk = { scope, level -> viewModel.applyBulk(d.group, scope, level) },
        )
        return
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("習熟度", fontWeight = FontWeight.Bold) },
                actions = {
                    ImasToolbarButton(
                        icon = Icons.Filled.FilterList,
                        label = "フィルタ",
                        onClick = { showFilter = true },
                        tint = if (state.isFilterActive) DS.ink else DS.ink2
                    )
                }
            )
        }
    ) { padding ->
        if (state.isLoading) {
            ImasLoadingState(Modifier.padding(padding))
        } else {
            LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                item { SummarySection(state) }
                item { GroupHeader(state, viewModel) }
                itemsIndexed(state.groups) { index, group ->
                    // 右スワイプでも長押しでも同じ一括更新を出す。
                    // iOS は右スワイプに段ごとのボタンが並ぶが、Compose のスワイプは
                    // 向きしか区別できないので、段を選ぶのはシートに任せる。
                    MasterySwipeRow(
                        onStart = { bulkTarget = group },
                        startLabel = "まとめて付ける",
                        startColor = DS.fill,
                    ) {
                        GroupRow(group, state,
                                 onClick = { viewModel.openGroup(group) },
                                 onLongClick = { bulkTarget = group })
                    }
                    if (index < state.groups.size - 1) {
                        HorizontalDivider(Modifier.padding(start = DS.sp5), color = DS.sep)
                    }
                }
                if (state.groups.isEmpty()) {
                    item {
                        ImasEmptyState(Icons.Filled.FilterList, "該当するグループがありません",
                                       "絞り込みを緩めてください。")
                    }
                }
                item { Spacer(Modifier.height(DS.sp7)) }
            }
        }
    }

    bulkTarget?.let { group ->
        UnsetBulkSheet(group, state.scale,
                       onPick = { level ->
                           viewModel.applyBulk(group, MasteryBulkScope.UNSET_ONLY, level)
                           bulkTarget = null
                       },
                       onDismiss = { bulkTarget = null })
    }

    if (showFilter) {
        MasteryFilterSheet(state, viewModel) { showFilter = false }
    }
}

/**
 * 群の長押しで出す一括更新。**未設定の曲だけ**を対象にする。
 *
 * 既に付いている記録に触らない操作だけを置いているので、誤って押しても失うものがない。
 * 段を塗り替える/未設定に戻すのは、直前の 1 回を戻せる群の詳細に残す。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun UnsetBulkSheet(group: MasteryGroup, scale: MasteryScale,
                           onPick: (UByte) -> Unit, onDismiss: () -> Unit) {
    val unset = group.levels.count { it.toInt() == 0 }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = DS.bg) {
        Column(Modifier.padding(horizontal = DS.sp5).padding(bottom = DS.sp7)) {
            ImasText(group.label, ImasTextRole.CARD_TITLE, maxLines = 2)
            Spacer(Modifier.height(DS.sp4))
            if (unset == 0) {
                ImasText("全部に段階が付いています", ImasTextRole.ROW_SUBTITLE)
            } else {
                ImasText("未設定の $unset 曲だけ", ImasTextRole.META)
                Spacer(Modifier.height(DS.sp2))
                for (i in scale.steps.toInt() downTo 1) {
                    val level = i.toUByte()
                    Row(
                        Modifier.fillMaxWidth().clickable { onPick(level) }.padding(vertical = DS.sp4),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(DS.sp4),
                    ) {
                        Box(Modifier.size(14.dp).clip(RoundedCornerShape(DS.rTag))
                                .background(MasteryPalette.fill(level, scale.steps)))
                        ImasText(scale.label(level), ImasTextRole.VALUE)
                    }
                }
            }
        }
    }
}

@Composable
private fun SummarySection(state: MasteryUiState) {
    val s = state.summary
    Column {
        ImasSectionHeader("あなたの習熟度", tight = true)
        ImasCard(modifier = Modifier.padding(horizontal = DS.sp5)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(DS.sp5),
            ) {
                ImasProgressRing(s.percent.toInt() / 100.0)
                Column(verticalArrangement = Arrangement.spacedBy(DS.sp3)) {
                    ImasMetric("${s.setCount}", unit = "/ ${s.total}曲", size = ImasNumeralSize.LARGE, emphasized = true)
                    ImasText("段階を付けた曲", ImasTextRole.NOTE)
                    ImasText("${state.scale.label(state.scale.steps)} ${s.doneCount} 曲", ImasTextRole.EYEBROW, color = DS.ink3)
                }
            }
        }
        Spacer(Modifier.height(DS.sp4))
        ImasCard(modifier = Modifier.padding(horizontal = DS.sp5), padding = 0.dp) {
            Column(Modifier.padding(horizontal = DS.sp4)) {
                for (level in state.scale.steps.toInt() downTo 1) {
                    val c = state.stageCounts.getOrElse(level - 1) { 0 }
                    ImasStatBar(
                        state.scale.label(level.toUByte()), "$c",
                        c * 100.0 / maxOf(state.scopedCount, 1),
                        contentPadding = PaddingValues(vertical = DS.Space.gap)
                    )
                }
            }
        }
        Spacer(Modifier.height(DS.sp6))
    }
}

@Composable
private fun GroupHeader(state: MasteryUiState, vm: MasteryViewModel) {
    Column {
        ImasSectionHeader("グループ別", count = "${state.groups.size} 件", tight = true)

        // ブランドは**常に見える位置**に置く。この一覧はブランドで絞らないと
        // 群が数百件並んで用を成さないので、シートの中に畳んではいけない。
        ImasChipRow {
            ImasFilterChip("全て", state.brandIds.isEmpty(), { vm.clearBrands() })
            state.brands.forEach { b ->
                ImasFilterChip(b.shortName, state.brandIds.contains(b.id),
                               { vm.toggleBrand(b.id) }, brand = b.id)
            }
        }
        Spacer(Modifier.height(DS.sp3))

        ImasSegmented(AXIS_LABELS, AXES.indexOf(state.axis), { vm.setAxis(AXES[it]) },
                      Modifier.padding(horizontal = DS.sp5))
        Spacer(Modifier.height(DS.sp3))

        NameFilterField(
            prompt = "${AXIS_LABELS[AXES.indexOf(state.axis)]}名で絞り込み",
            value = state.nameFilter,
            onValueChange = vm::setNameFilter
        )
    }
}

/**
 * 群 1 行。タップで中の曲一覧へ、**長押しでまだ付けていない曲だけをまとめて**付けられる。
 *
 * 「このシリーズは一通り聞いた」を一覧から 2 手で終わらせるための口。
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun GroupRow(g: MasteryGroup, state: MasteryUiState,
                     onClick: () -> Unit, onLongClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().background(DS.surface)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = DS.sp5, vertical = DS.sp3),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DS.sp4),
    ) {
        ImasLeadBar(height = 36.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            ImasText(g.label, ImasTextRole.ROW_TITLE, maxLines = 2)
            ImasText(subtitle(g, state), ImasTextRole.ROW_SUBTITLE, maxLines = 1)
        }
        ImasMetricBadge("${g.percent}", "%", emphasized = g.percent > 0u)
    }
}

private fun subtitle(g: MasteryGroup, state: MasteryUiState): String {
    val parts = mutableListOf<String>()
    if (g.discCount > 1u) parts += "${g.discCount}枚"
    parts += "${g.total}曲"
    val unset = g.levels.count { it.toInt() == 0 }
    if (unset > 0) parts += "未設定 $unset"
    // 「聴いたのにまだ未設定」は覚える優先度が高いので、そこだけ名指しで出す。
    if (g.heardButUnsetCount > 0u) parts += "聴いたのに未設定 ${g.heardButUnsetCount}"
    else if (g.collectedCount > 0u) parts += "聴いた ${g.collectedCount}"
    if (g.doneCount > 0u) parts += "${state.scale.label(state.scale.steps)} ${g.doneCount}"
    return parts.joinToString(" ・ ")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MasteryFilterSheet(state: MasteryUiState, vm: MasteryViewModel, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = DS.bg) {
        Column(Modifier.padding(bottom = DS.sp7)) {
            ImasFilterSheetToolbar(
                canReset = state.isFilterActive,
                onReset = { vm.resetFilters() },
                onApply = onDismiss
            )
            Spacer(Modifier.height(DS.sp4))

            Column(Modifier.padding(horizontal = DS.sp5)) {
                ImasText("進み具合", ImasTextRole.SECTION_LABEL)
                Spacer(Modifier.height(DS.sp2))
            }
            ImasChipRow {
                listOf(MasteryProgressFilter.ALL, MasteryProgressFilter.HEARD_BUT_UNSET,
                       MasteryProgressFilter.HAS_UNSET, MasteryProgressFilter.UNTOUCHED,
                       MasteryProgressFilter.COMPLETE).forEach { v ->
                    ImasFilterChip(progressLabel(v), state.progress == v, { vm.setProgress(v) })
                }
            }
            Spacer(Modifier.height(DS.sp5))

            Column(Modifier.padding(horizontal = DS.sp5)) {
                ImasText("並び", ImasTextRole.SECTION_LABEL)
                Spacer(Modifier.height(DS.sp2))
            }
            ImasChipRow {
                listOf(MasteryGroupSort.SONG_COUNT, MasteryGroupSort.PROGRESS_ASC,
                       MasteryGroupSort.PROGRESS_DESC, MasteryGroupSort.NAME).forEach { v ->
                    ImasFilterChip(sortLabel(v), state.sort == v, { vm.setSort(v) })
                }
            }
        }
    }
}
