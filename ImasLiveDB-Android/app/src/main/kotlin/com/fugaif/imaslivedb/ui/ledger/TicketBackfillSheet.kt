package com.fugaif.imaslivedb.ui.ledger

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.Expense
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.data.repository.LedgerShowOption
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import java.time.LocalDate
import uniffi.imas_core.ExpenseCategory
import uniffi.imas_core.ShowTicket
import uniffi.imas_core.TicketBackfillInput
import uniffi.imas_core.TicketBackfillItem
import uniffi.imas_core.formatYen
import uniffi.imas_core.ticketExpenseBackfill
import uniffi.imas_core.ticketExpenseNote
import uniffi.imas_core.ticketKindLabel

/** 取り込み候補の公演 1 つ (コアの候補 + 画面に出す公演名と日付)。iOS `TicketBackfillRow` と対。 */
data class TicketBackfillRow(val item: TicketBackfillItem, val option: LedgerShowOption) {
    val id: String get() = item.showId
}

/**
 * 過去の参加からチケット代を取り込む候補を集める。iOS `TicketBackfill` の移植。
 *
 * 参加を付けた直後の確認 ([TicketExpensePrompt]) は、確認が入る前に付けた参加を
 * 拾わない。それを後からまとめて入れるための入口。候補にするかはコア
 * (ticketExpenseBackfill) で、直後の確認と同じ規則。
 */
object TicketBackfill {
    suspend fun candidates(module: AppModule): List<TicketBackfillRow> {
        val options = module.expenseRepository.attendedShowOptions()
        // 記録済みかは全件を 1 回読んで公演ごとに束ねる (公演ごとに引くと参加数ぶん往復する)。
        val recorded = module.expenseRepository.getAll().groupBy { it.showId.orEmpty() }
        val inputs = options.mapNotNull { option ->
            val type = module.userMarkRepository.attendance(UserMark.SHOW, option.id) ?: return@mapNotNull null
            val tickets = module.showTicketRepository.forShow(option.id).map { it.toCore() }
            if (tickets.isEmpty()) return@mapNotNull null
            TicketBackfillInput(
                showId = option.id,
                attendanceType = type.raw,
                tickets = tickets,
                existingExpenseCategories = recorded[option.id].orEmpty().map { it.category }
            )
        }
        val byId = options.associateBy { it.id }
        return ticketExpenseBackfill(inputs).mapNotNull { item ->
            byId[item.showId]?.let { TicketBackfillRow(item, it) }
        }
    }

    /** 選んだ券を支出にする。日付は公演の日 (分からなければ今日)。 */
    fun expense(row: TicketBackfillRow, ticket: ShowTicket): Expense = Expense.make(
        date = row.option.date.ifEmpty { LocalDate.now().toString() },
        category = ExpenseCategory.TICKET,
        amount = ticket.price,
        showId = row.item.showId,
        eventId = row.option.eventId,
        note = ticketExpenseNote(ticket)
    )
}

/**
 * 過去の参加からチケット代をまとめて取り込むシート。iOS `TicketBackfillView` の移植。
 *
 * **券種が 1 つの公演だけ最初から選んでおく**。S席と立見のように複数あるときは
 * 選ばれるまで記録しない (先頭を黙って入れると差額が帳簿に乗る)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketBackfillSheet(
    rows: List<TicketBackfillRow>,
    onSave: (List<Expense>) -> Unit,
    onDismiss: () -> Unit,
) {
    // 公演 id → 選んだ券。無い公演は記録しない。
    val selection = remember(rows) {
        mutableStateMapOf<String, ShowTicket>().apply {
            rows.forEach { row -> row.item.preselected?.let { put(row.id, it) } }
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = DS.bg) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            Text("チケット代を取り込む", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            Spacer(Modifier.height(12.dp))
            LazyColumn(
                Modifier.fillMaxWidth().heightIn(max = 480.dp)
                    .background(DS.surface, RoundedCornerShape(10.dp))
            ) {
                items(rows, key = { it.id }) { row ->
                    BackfillRow(
                        row = row,
                        chosen = selection[row.id],
                        onChoose = { ticket ->
                            if (ticket == null) selection.remove(row.id) else selection[row.id] = ticket
                        }
                    )
                    if (row != rows.last()) HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 14.dp))
                }
            }
            Text(
                "券種が複数ある公演は、選んだものだけ記録します。金額はあとから明細で直せます。",
                fontSize = 11.sp, color = DS.ink3, modifier = Modifier.padding(top = 6.dp)
            )
            Spacer(Modifier.height(20.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss) { Text("キャンセル") }
                Spacer(Modifier.width(8.dp))
                Button(
                    onClick = {
                        onSave(rows.mapNotNull { row -> selection[row.id]?.let { TicketBackfill.expense(row, it) } })
                    },
                    enabled = selection.isNotEmpty()
                ) { Text("${selection.size}件を記録") }
            }
        }
    }
}

@Composable
private fun BackfillRow(row: TicketBackfillRow, chosen: ShowTicket?, onChoose: (ShowTicket?) -> Unit) {
    var menuOpen by remember { mutableStateOf(false) }
    // 券種が複数あって未選択のときは、丸を押しても選べない (右のメニューで選ぶ)。
    val toggleEnabled = chosen != null || row.item.preselected != null
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(
            if (chosen != null) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
            contentDescription = if (chosen != null) "記録しない" else "記録する",
            tint = if (chosen != null) DS.ink else DS.ink3,
            modifier = Modifier.clickable(enabled = toggleEnabled) {
                onChoose(if (chosen != null) null else row.item.preselected)
            }
        )
        Column(Modifier.weight(1f)) {
            Text(row.option.label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 2)
            Text("${row.option.date}・${ticketKindLabel(row.item.kind)}", fontSize = 11.sp, color = DS.ink3)
        }
        if (row.item.tickets.size > 1) {
            Box {
                Text(
                    chosen?.let(::ticketLabel) ?: "券種を選ぶ",
                    fontSize = 12.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.End,
                    color = if (chosen != null) DS.ink else DS.ink2,
                    modifier = Modifier.clickable { menuOpen = true }
                )
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    row.item.tickets.forEach { ticket ->
                        DropdownMenuItem(
                            text = { Text("${ticket.name}  ${formatYen(ticket.price)}") },
                            onClick = { onChoose(ticket); menuOpen = false }
                        )
                    }
                    if (chosen != null) {
                        DropdownMenuItem(
                            text = { Text("記録しない", color = DS.danger) },
                            onClick = { onChoose(null); menuOpen = false }
                        )
                    }
                }
            }
        } else {
            row.item.tickets.firstOrNull()?.let { ticket ->
                Text(
                    ticketLabel(ticket), fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.End, color = if (chosen != null) DS.ink else DS.ink3
                )
            }
        }
    }
}

private fun ticketLabel(ticket: ShowTicket): String = "${ticketExpenseNote(ticket)}\n${formatYen(ticket.price)}"
