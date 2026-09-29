package com.fugaif.imaslivedb.ui.ledger

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.local.localWrite
import com.fugaif.imaslivedb.data.model.Expense
import com.fugaif.imaslivedb.data.repository.AttendanceMarkedEvent
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.launch
import uniffi.imas_core.ExpenseCategory
import uniffi.imas_core.ShowTicket
import uniffi.imas_core.TicketKind
import uniffi.imas_core.formatYen
import uniffi.imas_core.ticketExpenseNote
import uniffi.imas_core.ticketExpensePrompt
import uniffi.imas_core.ticketKindLabel

private val DATE_FORMAT: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE

/**
 * 参加を付けた直後に「チケット代を記録しますか」を出す。iOS
 * `TicketExpensePromptModifier` の 1:1 移植。アプリのルート ([com.fugaif.imaslivedb.MainActivity])
 * に 1 度だけ置く。
 *
 * 参加登録の入口は複数 (行のスワイプ / 公演の参加シート / セトリ画面) あるが、
 * どこから付けても [com.fugaif.imaslivedb.data.repository.UserMarkRepository.setAttendance] を
 * 必ず通り、その通知 ([com.fugaif.imaslivedb.data.repository.UserMarkRepository.attendanceMarked])
 * に集めてあるので、ここ 1 箇所で受ける。入口ごとにこのロジックを書くと出し分けの
 * 規則がすぐ二重になる。
 */
@Composable
fun TicketExpensePrompt() {
    val context = LocalContext.current
    val module = remember(context) { AppModule.from(context) }
    val scope = rememberCoroutineScope()
    var request by remember { mutableStateOf<TicketExpenseRequest?>(null) }

    LaunchedEffect(Unit) {
        module.userMarkRepository.attendanceMarked.collect { event ->
            request = prepare(module, event)
        }
    }

    request?.let { req ->
        TicketExpenseSheet(
            request = req,
            onSave = { ticket, amount ->
                scope.launch {
                    val note = ticketExpenseNote(ticket)
                    val expense = Expense.make(
                        date = req.date.ifEmpty { DATE_FORMAT.format(Instant.now().atZone(ZoneOffset.UTC)) },
                        category = ExpenseCategory.TICKET,
                        amount = amount,
                        showId = req.showId,
                        eventId = req.eventId,
                        note = note
                    )
                    // 保存できたときだけ閉じる (書けなかったら知らせて、シートは残す)。
                    localWrite("チケット代の記録") { module.expenseRepository.save(expense) } ?: return@launch
                    request = null
                }
            },
            onDismiss = { request = null }
        )
    }
}

/**
 * 出す条件を調べる。**出さない理由が 1 つでもあれば黙って終わる**
 * (参加を付けただけなのに毎回シートが出ると、付ける作業が止まる)。
 * 聞くかどうか (その形態の券があるか・この公演のチケット代を付けていないか) はコア
 * (ticketExpensePrompt)。付けたかどうかを**読めなかった**ときは聞かない (iOS と同じ)。
 */
private suspend fun prepare(module: AppModule, event: AttendanceMarkedEvent): TicketExpenseRequest? {
    val tickets = module.showTicketRepository.forShow(event.showId).map { it.toCore() }
    val existing = runCatching { module.expenseRepository.forShow(event.showId) }.getOrNull() ?: return null
    val prompt = ticketExpensePrompt(tickets, event.type.raw, existing.map { it.category }) ?: return null

    val option = module.expenseRepository.attendedShowOptions().firstOrNull { it.id == event.showId }
    return TicketExpenseRequest(
        showId = event.showId,
        showLabel = option?.label ?: "この公演",
        eventId = option?.eventId,
        date = option?.date.orEmpty(),
        kind = prompt.kind,
        tickets = prompt.tickets
    )
}

/** シートに渡す内容。 */
private data class TicketExpenseRequest(
    val showId: String,
    val showLabel: String,
    val eventId: String?,
    val date: String,
    val kind: TicketKind,
    val tickets: List<ShowTicket>
)

/** 確認シートの中身。金額はその場で直せる (手数料や先行の差額を含めたい人がいる)。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TicketExpenseSheet(
    request: TicketExpenseRequest,
    onSave: (ShowTicket, Long) -> Unit,
    onDismiss: () -> Unit
) {
    // 候補が 1 つなら決め打ちでよい。複数あるときは先頭 (公式の表記順) を初期値にする。
    var selected by remember(request) {
        mutableStateOf(if (request.tickets.size == 1) request.tickets.first() else null)
    }
    var amountText by remember(request) {
        mutableStateOf(request.tickets.firstOrNull()?.price?.toString().orEmpty())
    }
    val ticket = selected ?: request.tickets.firstOrNull()
    val amount = amountText.filter { it.isDigit() }.toLongOrNull() ?: 0L

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = DS.bg) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            Text("チケット代を記録", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            Spacer(Modifier.height(4.dp))
            Text(request.showLabel, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 2)
            Text(
                "${ticketKindLabel(request.kind)}で参加",
                fontSize = 12.sp, color = DS.ink2, modifier = Modifier.padding(top = 2.dp)
            )
            Spacer(Modifier.height(16.dp))

            Text("券種", fontSize = 12.sp, color = DS.ink2)
            Column(
                Modifier.padding(top = 6.dp).fillMaxWidth()
                    .background(DS.fill, RoundedCornerShape(10.dp))
            ) {
                request.tickets.forEachIndexed { index, candidate ->
                    if (index > 0) HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 14.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth()
                            .clickable {
                                selected = candidate
                                amountText = candidate.price.toString()
                            }
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(candidate.name, fontSize = 15.sp, color = DS.ink)
                            if (candidate.isEstimate) {
                                Text("推定", fontSize = 11.sp, color = DS.ink3)
                            }
                        }
                        Text(
                            formatYen(candidate.price), fontSize = 14.sp, color = DS.ink2,
                            modifier = Modifier.padding(end = 8.dp)
                        )
                        if (candidate.id == ticket?.id) {
                            Icon(Icons.Filled.Check, contentDescription = null, tint = DS.ink2)
                        }
                    }
                }
            }
            Spacer(Modifier.height(16.dp))

            Text("記録する金額", fontSize = 12.sp, color = DS.ink2)
            Spacer(Modifier.height(6.dp))
            OutlinedTextField(
                value = amountText,
                onValueChange = { amountText = it.filter(Char::isDigit) },
                placeholder = { Text("0") },
                leadingIcon = { Text("¥", color = DS.ink2) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                "手数料や先行の差額を含めたいときは、ここで直してください。",
                fontSize = 11.sp, color = DS.ink3, modifier = Modifier.padding(top = 6.dp)
            )
            Spacer(Modifier.height(20.dp))

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss) { Text("あとで") }
                Spacer(Modifier.width(8.dp))
                Button(
                    onClick = {
                        ticket?.let { onSave(it, amount) }
                    },
                    enabled = ticket != null && amount > 0
                ) { Text("記録する") }
            }
        }
    }
}
