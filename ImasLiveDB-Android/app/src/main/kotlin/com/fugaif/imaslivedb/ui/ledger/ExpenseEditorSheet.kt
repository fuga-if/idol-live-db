package com.fugaif.imaslivedb.ui.ledger

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.model.Expense
import com.fugaif.imaslivedb.data.repository.LedgerShowOption
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasFormAmount
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormField
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextArea
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowChevron
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import uniffi.imas_core.ExpenseCategory
import uniffi.imas_core.ExpenseInputError
import uniffi.imas_core.expenseCategories
import uniffi.imas_core.expenseCategoryKey
import uniffi.imas_core.textSearchMatchRange
import uniffi.imas_core.validateExpense

private val DATE_FORMAT: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE

/**
 * 支出 1 件の入力。追加も編集も同じシート。iOS `ExpenseEditorView` の移植。
 *
 * 入力の検査 (日付の形・金額の範囲) は**共有コア** (`validateExpense`) 一本。
 * ここは弾かれた理由を日本語に直して出すだけで、条件は Kotlin に書かない。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExpenseEditorSheet(
    expense: Expense?,
    showOptions: List<LedgerShowOption>,
    onSave: (Expense) -> Unit,
    onDismiss: () -> Unit
) {
    var dateText by rememberSaveable { mutableStateOf(expense?.date ?: DATE_FORMAT.format(Instant.now().atZone(ZoneOffset.UTC))) }
    var category by remember { mutableStateOf(expense?.categoryValue ?: ExpenseCategory.TICKET) }
    var amount by rememberSaveable { mutableStateOf(expense?.amount?.toInt()) }
    var note by rememberSaveable { mutableStateOf(expense?.note ?: "") }
    var showId by rememberSaveable { mutableStateOf(expense?.showId) }
    var eventId by rememberSaveable { mutableStateOf(expense?.eventId) }
    var showDatePicker by remember { mutableStateOf(false) }
    var showShowPicker by remember { mutableStateOf(false) }

    val validation = validateExpense(dateText, (amount ?: 0).toLong())

    fun save() {
        if (validation != null) return
        val saved = expense?.copy(
            date = dateText, category = expenseCategoryKey(category), amount = (amount ?: 0).toLong(),
            showId = showId, eventId = eventId, note = note.ifEmpty { null }
        ) ?: Expense.make(dateText, category, (amount ?: 0).toLong(), showId, eventId, note)
        onSave(saved)
    }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = DS.bg) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
            ImasSheetToolbar(
                ImasSheetToolbarKind.Edit(canSave = validation == null, onCancel = onDismiss, onSave = ::save),
                title = if (expense == null) "支出を足す" else "支出を直す"
            )

            Column(
                Modifier.padding(horizontal = DS.Space.screen),
                verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
            ) {
                ImasFormCard {
                    ImasFormAmount(label = "金額", imprint = "AMOUNT", icon = Icons.Filled.AttachMoney, amount = amount, onAmountChange = { amount = it })
                }
                if (validation == ExpenseInputError.NOT_POSITIVE || validation == ExpenseInputError.TOO_LARGE) {
                    Text(message(validation), style = ImasTextRole.NOTE.style, color = DS.danger)
                }

                ImasFormCard {
                    ImasFormField(label = "費目", imprint = "CATEGORY") {
                        CategoryGrid(selected = category, onSelect = { category = it })
                    }
                }

                ImasFormCard {
                    ImasFormField(label = "日付", imprint = "DATE") {
                        Row(
                            Modifier.fillMaxWidth().imasRowPress(onClick = { showDatePicker = true }),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(dateText)
                            ImasRowChevron()
                        }
                    }
                }

                ImasFormCard {
                    ImasFormField(label = "公演", imprint = "SHOW") {
                        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                            val label = showOptions.firstOrNull { it.id == showId }?.label ?: "公演に紐づけない"
                            Row(
                                Modifier.fillMaxWidth().imasRowPress(onClick = { showShowPicker = true }),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(label, color = if (showId == null) DS.ink2 else DS.ink)
                                ImasRowChevron()
                            }
                        }
                    }
                }
                ImasNote("紐づけると「この遠征でいくら使ったか」が出ます。課金やグッズの通販は紐づけなくて構いません。")

                ImasFormCard {
                    ImasFormTextArea(label = "メモ", imprint = "NOTE", text = note, onTextChange = { note = it }, prompt = "任意")
                }
            }
        }
    }

    if (showDatePicker) {
        val initialMillis = runCatching {
            java.time.LocalDate.parse(dateText, DATE_FORMAT).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        }.getOrNull()
        val pickerState = rememberDatePickerState(initialSelectedDateMillis = initialMillis)
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    pickerState.selectedDateMillis?.let { millis ->
                        dateText = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).format(DATE_FORMAT)
                    }
                    showDatePicker = false
                }) { Text("決定") }
            },
            dismissButton = { TextButton(onClick = { showDatePicker = false }) { Text("キャンセル") } }
        ) { DatePicker(state = pickerState) }
    }

    if (showShowPicker) {
        LedgerShowPickerSheet(
            options = showOptions,
            onPick = { option ->
                showId = option?.id
                eventId = option?.eventId
                // 日付を入れ直していなければ公演の日に合わせる (遠征費は当日が大半)。
                if (option != null && expense == null && amount == null) dateText = option.date
                showShowPicker = false
            },
            onDismiss = { showShowPicker = false }
        )
    }
}

@Composable
private fun CategoryGrid(selected: ExpenseCategory, onSelect: (ExpenseCategory) -> Unit) {
    // 並びはコアが決める。画面ごとに並べ替えない。
    val categories = remember { expenseCategories() }
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        categories.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                row.forEach { info ->
                    ImasFilterChip(info.label, info.category == selected, { onSelect(info.category) })
                }
            }
        }
    }
}

private fun message(error: ExpenseInputError?): String = when (error) {
    ExpenseInputError.BAD_DATE -> "日付を選んでください"
    ExpenseInputError.NOT_POSITIVE -> "金額を入れてください"
    ExpenseInputError.TOO_LARGE -> "桁が多すぎます (1 億円未満)"
    null -> ""
}

/** 紐づける公演を選ぶ。参加を付けた公演だけが並ぶ。iOS `LedgerShowPicker` の移植。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LedgerShowPickerSheet(
    options: List<LedgerShowOption>,
    onPick: (LedgerShowOption?) -> Unit,
    onDismiss: () -> Unit
) {
    var query by rememberSaveable { mutableStateOf("") }
    // 照合の規則はコア一本 (画面で contains を書かない)。
    val shown = if (query.isEmpty()) options else options.filter {
        textSearchMatchRange(it.label, query) != null
    }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = DS.bg) {
        Column(Modifier.fillMaxWidth()) {
            ImasSheetToolbar(ImasSheetToolbarKind.Read(onClose = onDismiss), title = "公演を選ぶ")
            OutlinedTextField(
                value = query, onValueChange = { query = it }, placeholder = { Text("公演を探す") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
            )
            LazyColumn(Modifier.padding(bottom = DS.Space.section)) {
                item {
                    ImasListSection {
                        ImasActionRow(title = "公演に紐づけない", icon = Icons.Filled.Close, onClick = { onPick(null) })
                        if (options.isEmpty()) {
                            ImasEmptyState(
                                icon = Icons.Filled.Mic,
                                title = "参加した公演がありません。ライブに「参加」を付けると、ここに並びます。"
                            )
                        }
                        shown.forEach { option ->
                            ImasRow(
                                title = option.label,
                                subtitle = option.date,
                                titleRole = ImasTextRole.ROW_LABEL,
                                modifier = Modifier.imasRowPress(onClick = { onPick(option) })
                            )
                        }
                    }
                }
            }
        }
    }
}
