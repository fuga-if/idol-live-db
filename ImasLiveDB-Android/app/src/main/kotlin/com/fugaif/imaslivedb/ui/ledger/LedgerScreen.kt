package com.fugaif.imaslivedb.ui.ledger

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Expense
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasChipRow
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasMetric
import com.fugaif.imaslivedb.ui.designsystem.ImasRecordRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasStatBar
import com.fugaif.imaslivedb.ui.designsystem.ImasTicketRow
import com.fugaif.imaslivedb.ui.mastery.MasterySwipeRow
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import uniffi.imas_core.LedgerBucket
import uniffi.imas_core.LedgerLinkage
import uniffi.imas_core.expenseCategoryLabel
import uniffi.imas_core.formatYen

private val PERIOD_LABELS = listOf("月別", "年別", "全期間")

/**
 * アイマス関連の収支 (家計簿)。iOS `LedgerView` の移植。
 *
 * 「この趣味にいくら使ったか」を、月/年でまとめて出す。1 件は日付・費目・金額を持ち、
 * 公演に紐づけると「この遠征でいくら使ったか」が出る。紐づけない支出 (課金・通販) も
 * 同じ帳簿に並ぶ。集計・絞り込み・並び・金額の表記は**共有コア**一本。
 *
 * 行のスワイプ (削除) は [MasterySwipeRow] を再利用する (習熟度画面と同じ理由: 左端から
 * 引くと OS の「戻る」に取られるので、右スワイプだけに削除を割り当てる)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LedgerScreen(viewModel: LedgerViewModel = viewModel()) {
    val state by viewModel.uiState.collectAsState()
    var editorTarget by remember { mutableStateOf<EditorTarget?>(null) }
    var showingBackfill by remember { mutableStateOf(false) }
    var showingStoreImport by remember { mutableStateOf(false) }
    var addMenuOpen by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("収支") },
                actions = {
                    // 入口は + 1 つ。何を足すかをメニューで選ぶ (アイコンを並べると意味が伝わらない)。iOS と対。
                    Box {
                        IconButton(onClick = { addMenuOpen = true }) {
                            Icon(Icons.Filled.Add, "支出を足す")
                        }
                        DropdownMenu(expanded = addMenuOpen, onDismissRequest = { addMenuOpen = false }) {
                            DropdownMenuItem(
                                text = { Text("支出を入力") },
                                leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
                                onClick = { addMenuOpen = false; editorTarget = EditorTarget(null) }
                            )
                            DropdownMenuItem(
                                text = { Text("アソビストアの明細を入力") },
                                leadingIcon = { Icon(Icons.Filled.ShoppingBag, contentDescription = null) },
                                onClick = { addMenuOpen = false; showingStoreImport = true }
                            )
                        }
                    }
                }
            )
        }
    ) { padding ->
        if (state.isLoading) {
            ImasLoadingState(modifier = Modifier.padding(padding))
        } else {
            LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                item { SummarySection(state) }
                if (state.backfillRows.isNotEmpty()) {
                    item { BackfillBanner(state.backfillRows.size) { showingBackfill = true } }
                }
                item { ControlsSection(state, viewModel) }
                if (state.expenses.isEmpty()) {
                    item {
                        ImasEmptyState(
                            Icons.Filled.AttachMoney, "まだ記録がありません",
                            "右上の + から、チケット代や遠征費を足してください。アソビストアのグッズ代は「アソビストアの明細を入力」から購入履歴をまとめて取り込めます。"
                        )
                    }
                } else {
                    state.summary.buckets.forEach { bucket ->
                        item(key = "header_${bucket.key}") { BucketHeader(bucket) }
                        val rows = state.entries(bucket)
                        rows.forEachIndexed { index, expense ->
                            item(key = expense.id) {
                                MasterySwipeRow(
                                    onStart = { viewModel.delete(expense) },
                                    startLabel = "削除",
                                    startColor = DS.danger,
                                ) {
                                    ExpenseRow(
                                        expense = expense,
                                        showLabel = expense.showId?.let { state.showLabels[it] },
                                        onClick = { editorTarget = EditorTarget(expense) }
                                    )
                                }
                            }
                            if (index < rows.size - 1) {
                                item(key = "${expense.id}_div") {
                                    ImasRowDivider(inset = DS.Space.rowH, modifier = Modifier.background(DS.surface))
                                }
                            }
                        }
                    }
                }
                item { Spacer(Modifier.height(DS.Space.section)) }
            }
        }
    }

    editorTarget?.let { target ->
        ExpenseEditorSheet(
            expense = target.expense,
            showOptions = state.showOptions,
            onSave = { saved -> viewModel.save(saved) { editorTarget = null } },
            onDismiss = { editorTarget = null }
        )
    }

    if (showingBackfill) {
        TicketBackfillSheet(
            rows = state.backfillRows,
            onSave = { expenses -> viewModel.saveBackfill(expenses) { showingBackfill = false } },
            onDismiss = { showingBackfill = false }
        )
    }

    if (showingStoreImport) {
        StoreOrderImportSheet(
            existingNotes = state.expenses.mapNotNull { it.note },
            showOptions = state.showOptions,
            onSave = { expenses -> viewModel.saveStoreOrders(expenses) { showingStoreImport = false } },
            onDismiss = { showingStoreImport = false }
        )
    }
}

@Composable
private fun BackfillBanner(count: Int, onClick: () -> Unit) {
    ImasTicketRow(
        title = "過去の参加からチケット代を取り込む",
        icon = Icons.Filled.ConfirmationNumber,
        subtitle = "チケット代が未記録の公演が${count}件あります",
        onClick = onClick,
        modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
    )
}

/** シートの対象。expense が null なら新規作成。 */
private data class EditorTarget(val expense: Expense?)

@Composable
private fun SummarySection(state: LedgerUiState) {
    val s = state.summary
    ImasSection("使った額", style = ImasSectionHeaderStyle.SMALL) {
        ImasCard {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                ImasMetric(value = formatYen(s.total), unit = "${s.count}件", size = ImasNumeralSize.LARGE, emphasized = true)
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.section)) {
                    Metric("遠征費", formatYen(s.travelTotal))
                    if (s.showCount > 0u) {
                        Metric("1公演あたり", formatYen(s.averagePerShow))
                        Metric("公演数", "${s.showCount}")
                    }
                }
            }
        }
        if (s.byCategory.isNotEmpty()) {
            ImasCard {
                Column {
                    s.byCategory.forEach { row ->
                        ImasStatBar(
                            label = row.label,
                            value = formatYen(row.total),
                            percent = row.percent.toDouble(),
                            valueWidth = 76.dp,
                            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 0.dp, vertical = DS.Space.gap)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun Metric(label: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        Text(label, style = ImasTextRole.META.style, color = ImasTextRole.META.color)
        Text(value, style = ImasType.text(13.sp, FontWeight.Bold), color = DS.ink)
    }
}

@Composable
private fun ControlsSection(state: LedgerUiState, vm: LedgerViewModel) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        ImasSegmented(PERIOD_LABELS, state.periodIndex, vm::setPeriodIndex, Modifier.padding(horizontal = DS.Space.screen))
        ImasChipRow {
            ImasFilterChip("全期間", state.yearFilter.isEmpty(), { vm.setYearFilter("") })
            state.years.forEach { year ->
                ImasFilterChip("${year}年", state.yearFilter == year, { vm.setYearFilter(year) })
            }
        }
        ImasChipRow {
            ImasFilterChip("すべて", state.linkage == LedgerLinkage.ALL, { vm.setLinkage(LedgerLinkage.ALL) })
            ImasFilterChip("公演あり", state.linkage == LedgerLinkage.LINKED_ONLY, { vm.setLinkage(LedgerLinkage.LINKED_ONLY) })
            ImasFilterChip("公演なし", state.linkage == LedgerLinkage.UNLINKED_ONLY, { vm.setLinkage(LedgerLinkage.UNLINKED_ONLY) })
        }
    }
}

@Composable
private fun BucketHeader(bucket: LedgerBucket) {
    Row(
        Modifier.fillMaxWidth().background(DS.bg).padding(horizontal = DS.Space.screen, vertical = DS.Space.header),
        verticalAlignment = Alignment.Bottom
    ) {
        Text(bucket.label, style = ImasType.text(15.sp, FontWeight.Bold), color = DS.ink)
        Spacer(Modifier.weight(1f))
        Text(formatYen(bucket.total), style = ImasTextRole.META.style.copy(fontWeight = FontWeight.Bold), color = ImasTextRole.META.color)
    }
}

@Composable
private fun ExpenseRow(expense: Expense, showLabel: String?, onClick: () -> Unit) {
    // 費目・日付は常に出す (題にする)。公演名かメモは、あるときだけ下にもう1行足す
    // (無ければ何も足さない。費目を題の代わりに使うような分岐は作らない)。
    val detail = showLabel ?: expense.note
    ImasRecordRow(
        title = expenseCategoryLabel(expense.categoryValue),
        subtitle = shortDate(expense.date),
        trailing = ImasRowTrailing.Custom {
            Text(
                formatYen(expense.amount),
                style = ImasType.text(17.sp, FontWeight.SemiBold).copy(fontFeatureSettings = "tnum"),
                color = DS.ink
            )
        },
        modifier = Modifier.background(DS.surface).imasRowPress(onClick = onClick)
    ) {
        if (!detail.isNullOrEmpty()) {
            Text(detail, style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color)
        }
    }
}

private fun shortDate(date: String): String {
    if (date.length != 10) return date
    val month = date.substring(5, 7).toIntOrNull() ?: 0
    val day = date.substring(8, 10).toIntOrNull() ?: 0
    return "$month/$day"
}
