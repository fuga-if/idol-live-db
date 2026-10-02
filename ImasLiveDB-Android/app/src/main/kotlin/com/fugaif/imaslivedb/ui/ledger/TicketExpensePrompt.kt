package com.fugaif.imaslivedb.ui.ledger

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.local.localWrite
import com.fugaif.imaslivedb.data.model.Expense
import com.fugaif.imaslivedb.data.repository.AttendanceMarkedEvent
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasFormAmount
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectableRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
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
    // 出番待ちの確認 (先頭を出す)。**2days をまとめて付けると通知が続けて届く**ので、
    // 1 つの枠に入れると後の公演で前の公演が上書きされ、片方しか聞けない。
    val queue = remember { mutableStateListOf<TicketExpenseRequest>() }

    LaunchedEffect(Unit) {
        module.userMarkRepository.attendanceMarked.collect { event ->
            val next = prepare(module, event) ?: return@collect
            // 同じ公演は 1 度だけ聞く (付け外しを繰り返したときに同じ確認を重ねない)。
            if (queue.any { it.showId == next.showId }) return@collect
            queue.add(next)
        }
    }

    queue.firstOrNull()?.let { req ->
        val done = { queue.remove(req) }
        // 公演ごとに別のシートとして作り直す (前の公演の閉じた状態を引き継がない)。
        key(req.showId) {
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
                        done()
                    }
                },
                onDismiss = { done() }
            )
        }
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
    var amount by remember(request) {
        mutableStateOf(request.tickets.firstOrNull()?.price?.toInt())
    }
    val ticket = selected ?: request.tickets.firstOrNull()

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = DS.bg) {
        Column(Modifier.fillMaxWidth().padding(bottom = DS.Space.section)) {
            ImasSheetToolbar(
                ImasSheetToolbarKind.Prompt(
                    canRecord = ticket != null && (amount ?: 0) > 0,
                    onLater = onDismiss,
                    onRecord = { ticket?.let { onSave(it, (amount ?: 0).toLong()) } }
                ),
                title = "チケット代を記録"
            )

            Column(
                Modifier.padding(horizontal = DS.Space.screen),
                verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                    Text(request.showLabel, style = ImasTextRole.SECTION_TITLE.style, color = ImasTextRole.SECTION_TITLE.color)
                    Text("${ticketKindLabel(request.kind)}で参加", style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color)
                }

                ImasSection("券種", style = ImasSectionHeaderStyle.SMALL) {
                    ImasCardList(items = request.tickets, key = { it.id }) { candidate ->
                        ImasSelectableRow(
                            title = candidate.name,
                            subtitle = if (candidate.isEstimate) "推定" else null,
                            trailing = ImasRowTrailing.Custom {
                                Text(formatYen(candidate.price), style = ImasTextRole.VALUE.style, color = DS.ink2)
                            },
                            isSelected = candidate.id == ticket?.id,
                            isSingle = true,
                            onClick = {
                                selected = candidate
                                amount = candidate.price.toInt()
                            }
                        )
                    }
                }

                ImasFormCard {
                    ImasFormAmount(
                        label = "記録する金額",
                        imprint = "AMOUNT",
                        icon = Icons.Filled.AttachMoney,
                        amount = amount,
                        onAmountChange = { amount = it }
                    )
                }
                ImasNote("手数料や先行の差額を含めたいときは、ここで直してください。")
            }
        }
    }
}
