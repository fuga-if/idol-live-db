package com.fugaif.imaslivedb.ui.ledger

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Expense
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasFilterChip
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.components.ImasStatBar
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.mastery.MasterySwipeRow
import com.fugaif.imaslivedb.ui.theme.DS
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("収支", fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = { editorTarget = EditorTarget(null) }) {
                        Icon(Icons.Filled.Add, "支出を足す")
                    }
                }
            )
        }
    ) { padding ->
        if (state.isLoading) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
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
                            "右上の + から、チケット代や遠征費を足してください。"
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
                                    HorizontalDivider(Modifier.padding(start = 16.dp), color = DS.sep)
                                }
                            }
                        }
                    }
                }
                item { Spacer(Modifier.height(24.dp)) }
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
}

@Composable
private fun BackfillBanner(count: Int, onClick: () -> Unit) {
    Row(
        Modifier.padding(horizontal = 16.dp).padding(bottom = 12.dp).fillMaxWidth()
            .clip(RoundedCornerShape(14.dp)).background(DS.surface).clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(Icons.Filled.ConfirmationNumber, contentDescription = null, tint = DS.ink2)
        Column(Modifier.weight(1f)) {
            Text("過去の参加からチケット代を取り込む", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
            Text("チケット代が未記録の公演が${count}件あります", fontSize = 12.sp, color = DS.ink3)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = DS.ink3)
    }
}

/** シートの対象。expense が null なら新規作成。 */
private data class EditorTarget(val expense: Expense?)

@Composable
private fun SummarySection(state: LedgerUiState) {
    val s = state.summary
    Column {
        ImasSectionHeader("使った額", tight = true)
        Column(
            Modifier.padding(horizontal = 16.dp).fillMaxWidth()
                .clip(RoundedCornerShape(14.dp)).background(DS.surface).padding(16.dp),
        ) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(formatYen(s.total), fontSize = 30.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                Text(
                    "  ${s.count}件", fontSize = 15.sp, color = DS.ink2,
                    modifier = Modifier.padding(bottom = 4.dp)
                )
            }
            Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                Metric("遠征費", formatYen(s.travelTotal))
                if (s.showCount > 0u) {
                    Metric("1公演あたり", formatYen(s.averagePerShow))
                    Metric("公演数", "${s.showCount}")
                }
            }
        }
        if (s.byCategory.isNotEmpty()) {
            Spacer(Modifier.height(10.dp))
            Column(
                Modifier.padding(horizontal = 16.dp).fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp)).background(DS.surface)
            ) {
                s.byCategory.forEach { row ->
                    ImasStatBar(row.label, formatYen(row.total), row.percent.toDouble())
                }
            }
        }
        Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun Metric(label: String, value: String) {
    Column {
        Text(label, fontSize = 12.sp, color = DS.ink3)
        Text(value, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = DS.ink)
    }
}

@Composable
private fun ControlsSection(state: LedgerUiState, vm: LedgerViewModel) {
    Column {
        ImasSegmented(PERIOD_LABELS, state.periodIndex, vm::setPeriodIndex, Modifier.padding(horizontal = 16.dp))
        Spacer(Modifier.height(10.dp))
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ImasFilterChip("全期間", state.yearFilter.isEmpty(), { vm.setYearFilter("") })
            state.years.forEach { year ->
                ImasFilterChip("${year}年", state.yearFilter == year, { vm.setYearFilter(year) })
            }
        }
        Spacer(Modifier.height(8.dp))
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ImasFilterChip("すべて", state.linkage == LedgerLinkage.ALL, { vm.setLinkage(LedgerLinkage.ALL) })
            ImasFilterChip("公演あり", state.linkage == LedgerLinkage.LINKED_ONLY, { vm.setLinkage(LedgerLinkage.LINKED_ONLY) })
            ImasFilterChip("公演なし", state.linkage == LedgerLinkage.UNLINKED_ONLY, { vm.setLinkage(LedgerLinkage.UNLINKED_ONLY) })
        }
        Spacer(Modifier.height(4.dp))
    }
}

@Composable
private fun BucketHeader(bucket: LedgerBucket) {
    Row(
        Modifier.fillMaxWidth().background(DS.bg).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.Bottom
    ) {
        Text(bucket.label, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink)
        Spacer(Modifier.weight(1f))
        Text(formatYen(bucket.total), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = DS.ink2)
    }
}

@Composable
private fun ExpenseRow(expense: Expense, showLabel: String?, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().background(DS.surface).clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    expenseCategoryLabel(expense.categoryValue), fontSize = 11.sp, fontWeight = FontWeight.Bold,
                    color = DS.ink2,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(DS.fill)
                        .padding(horizontal = 8.dp, vertical = 2.dp)
                )
                Text(shortDate(expense.date), fontSize = 11.sp, color = DS.ink3)
            }
            // 公演名かメモ。両方あれば公演名 (どの遠征の支出かが先に要る)。
            val subLabel = showLabel ?: expense.note
            if (!subLabel.isNullOrEmpty()) {
                Text(subLabel, fontSize = 13.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Text(formatYen(expense.amount), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
    }
}

private fun shortDate(date: String): String {
    if (date.length != 10) return date
    val month = date.substring(5, 7).toIntOrNull() ?: 0
    val day = date.substring(8, 10).toIntOrNull() ?: 0
    return "$month/$day"
}
