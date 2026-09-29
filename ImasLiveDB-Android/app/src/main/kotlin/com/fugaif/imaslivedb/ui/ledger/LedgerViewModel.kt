package com.fugaif.imaslivedb.ui.ledger

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.local.localWrite
import com.fugaif.imaslivedb.data.model.Expense
import com.fugaif.imaslivedb.data.repository.LedgerShowOption
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.ExpenseEntry
import uniffi.imas_core.LedgerBucket
import uniffi.imas_core.LedgerFilter
import uniffi.imas_core.LedgerLinkage
import uniffi.imas_core.LedgerPeriod
import uniffi.imas_core.LedgerSummary
import uniffi.imas_core.buildLedgerSummary

private fun emptySummary() = LedgerSummary(
    total = 0L, count = 0u, travelTotal = 0L, linkedTotal = 0L,
    showCount = 0u, averagePerShow = 0L, buckets = emptyList(), byCategory = emptyList()
)

data class LedgerUiState(
    val isLoading: Boolean = true,
    val expenses: List<Expense> = emptyList(),
    /** 公演 id → 表記 (明細/入力シートの公演名解決に使う)。 */
    val showLabels: Map<String, String> = emptyMap(),
    /** 参加を付けた公演だけ。支出を紐づける候補。 */
    val showOptions: List<LedgerShowOption> = emptyList(),
    /** 過去の参加でチケット代がまだ無い公演 (取り込みの候補)。 */
    val backfillRows: List<TicketBackfillRow> = emptyList(),
    val summary: LedgerSummary = emptySummary(),
    val periodIndex: Int = 0,
    val yearFilter: String = "",
    val linkage: LedgerLinkage = LedgerLinkage.ALL
) {
    val period: LedgerPeriod get() = when (periodIndex) {
        1 -> LedgerPeriod.YEAR
        2 -> LedgerPeriod.ALL
        else -> LedgerPeriod.MONTH
    }

    /** 記録のある年だけ、新しい順。**無い年のチップは出さない**。 */
    val years: List<String> get() = expenses
        .map { it.date.take(4) }
        .filter { it.length == 4 }
        .distinct()
        .sortedDescending()

    /** id → 支出。`entries(bucket:)` の引き直し用。 */
    private val expensesById: Map<String, Expense> get() = expenses.associateBy { it.id }

    /**
     * その箱に入る明細。絞り込みも「どの箱に入るか」もコアが `bucket.entryIds` として
     * 既に決めている ([buildLedgerSummary])。ここは id を引くだけで、条件を書き直さない
     * (書き直すと iOS と Android で必ず食い違う)。
     */
    fun entries(bucket: LedgerBucket): List<Expense> = bucket.entryIds.mapNotNull { expensesById[it] }
}

/**
 * 収支 (家計簿) 画面の状態管理。iOS `LedgerView` の移植。
 *
 * 集計・絞り込み・並び・金額の表記は**共有コア** (`domain/ledger.rs`) 一本。
 * ここは返ってきた集計結果を保持するのと、入力を受けて DB に書くところだけ。
 */
class LedgerViewModel(app: Application) : AndroidViewModel(app) {

    private val module = AppModule.from(app)
    private val repository = module.expenseRepository

    private val _uiState = MutableStateFlow(LedgerUiState())
    val uiState: StateFlow<LedgerUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            val expenses = repository.getAll()
            val showOptions = repository.attendedShowOptions()
            val showLabels = showOptions.associate { it.id to it.label }
            val backfillRows = runCatching { TicketBackfill.candidates(module) }.getOrDefault(emptyList())
            _uiState.value = _uiState.value.copy(
                isLoading = false,
                expenses = expenses,
                showLabels = showLabels,
                showOptions = showOptions,
                backfillRows = backfillRows
            )
            recompute()
        }
    }

    fun setPeriodIndex(index: Int) {
        _uiState.value = _uiState.value.copy(periodIndex = index)
        recompute()
    }

    fun setYearFilter(year: String) {
        val current = _uiState.value.yearFilter
        _uiState.value = _uiState.value.copy(yearFilter = if (current == year) "" else year)
        recompute()
    }

    fun setLinkage(linkage: LedgerLinkage) {
        val current = _uiState.value.linkage
        _uiState.value = _uiState.value.copy(linkage = if (current == linkage) LedgerLinkage.ALL else linkage)
        recompute()
    }

    /** 保存できたときだけ [onSaved] (編集を閉じる)。書けなかったら入力を捨てない。 */
    fun save(expense: Expense, onSaved: () -> Unit) {
        viewModelScope.launch {
            localWrite("支出の保存") { repository.save(expense) } ?: return@launch
            onSaved()
            val state = _uiState.value
            val updated = if (state.expenses.any { it.id == expense.id }) {
                state.expenses.map { if (it.id == expense.id) expense else it }
            } else {
                state.expenses + expense
            }.sortedWith(compareByDescending<Expense> { it.date }.thenByDescending { it.id })
            _uiState.value = state.copy(expenses = updated)
            recompute()
        }
    }

    /**
     * 取り込んだ分を 1 件ずつ書く。書けたものだけ一覧に足し、候補を読み直す
     * (途中で失敗しても、書けた公演が候補に残って二重に入らないように)。iOS `saveBackfill` と対。
     */
    fun saveBackfill(expenses: List<Expense>, onDone: () -> Unit) {
        viewModelScope.launch {
            val written = mutableListOf<Expense>()
            for (expense in expenses) {
                localWrite("チケット代の記録") { repository.save(expense) } ?: break
                written += expense
            }
            onDone()
            val state = _uiState.value
            val updated = (state.expenses + written)
                .sortedWith(compareByDescending<Expense> { it.date }.thenByDescending { it.id })
            val backfillRows = runCatching { TicketBackfill.candidates(module) }.getOrDefault(state.backfillRows)
            _uiState.value = state.copy(expenses = updated, backfillRows = backfillRows)
            recompute()
        }
    }

    fun delete(expense: Expense) {
        viewModelScope.launch {
            localWrite("支出の削除") { repository.delete(expense.id) } ?: return@launch
            val state = _uiState.value
            _uiState.value = state.copy(expenses = state.expenses.filterNot { it.id == expense.id })
            recompute()
        }
    }

    private fun recompute() {
        val state = _uiState.value
        val filter = LedgerFilter(
            year = state.yearFilter, categories = emptyList(), linkage = state.linkage, eventId = ""
        )
        val projected = state.expenses.map { expense ->
            ExpenseEntry(
                id = expense.id,
                date = expense.date,
                category = expense.categoryValue,
                amount = expense.amount,
                showId = expense.showId,
                eventId = expense.eventId,
                showLabel = expense.showId?.let { state.showLabels[it] },
                note = expense.note
            )
        }
        _uiState.value = state.copy(summary = buildLedgerSummary(projected, state.period, filter))
    }
}
