package com.fugaif.imaslivedb.ui.ledger

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.Expense
import com.fugaif.imaslivedb.data.repository.LedgerShowOption
import com.fugaif.imaslivedb.ui.theme.DS
import java.time.LocalDate
import uniffi.imas_core.StoreExpenseDraft
import uniffi.imas_core.StoreOrder
import uniffi.imas_core.StoreOrderItem
import uniffi.imas_core.StoreShowCandidate
import uniffi.imas_core.expenseCategories
import uniffi.imas_core.expenseCategoryLabel
import uniffi.imas_core.formatYen
import uniffi.imas_core.parseStoreOrders
import uniffi.imas_core.storeOrderAiLinks
import uniffi.imas_core.storeOrderAiPrompt
import uniffi.imas_core.storeOrderExpenses

/** 画面で直せる注文 1 件 (含めるか・紐づけ先・品目ごとの費目と含めるか)。iOS `DraftOrder` と対。 */
private data class DraftOrder(
    val order: StoreOrder,
    val include: Boolean,
    val showId: String?,
    val eventId: String?,
)

/**
 * 通販の購入明細 (アソビストアの「購入完了のご連絡」メール) を貼り付けて、
 * グッズ代・チケット代をまとめて帳簿に入れるシート。iOS `StoreOrderImportView` の移植。
 *
 * 明細の読み方・費目の推し方・送料や値引きの寄せ方・記録済みの判定・紐づけ先の推し方は
 * **共有コア** (`domain/store_order.rs`) 一本。ここは貼り付けを受けて、
 * 返ってきた注文を見せて、選んだ分を書くだけ。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StoreOrderImportSheet(
    /** 帳簿にある支出のメモ (同じ注文を 2 度入れないための判定に渡す)。 */
    existingNotes: List<String>,
    showOptions: List<LedgerShowOption>,
    onSave: (List<Expense>) -> Unit,
    onDismiss: () -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    var text by remember { mutableStateOf("") }
    val drafts = remember { mutableStateListOf<DraftOrder>() }
    var pickingIndex by remember { mutableStateOf<Int?>(null) }
    // 書き終わるまで閉じないので、その間の二度押しで同じ注文が 2 セット入らないように止める。
    var saving by remember { mutableStateOf(false) }

    fun parse(value: String) {
        text = value
        val candidates = showOptions.map {
            StoreShowCandidate(showId = it.id, eventId = it.eventId, eventName = it.eventName, date = it.date)
        }
        drafts.clear()
        parseStoreOrders(value, LocalDate.now().toString(), candidates, existingNotes).forEach { order ->
            // 記録済みの注文は最初から外しておく (2 度貼っても二重にならない)。
            drafts += DraftOrder(order, !order.alreadyRecorded, order.suggestedShowId, order.suggestedEventId)
        }
    }

    val planned: List<StoreExpenseDraft> = drafts.filter { it.include }
        .flatMap { storeOrderExpenses(it.order, it.showId, it.eventId) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = DS.bg,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            Text("明細の取り込み", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            Spacer(Modifier.height(12.dp))

            if (drafts.isEmpty()) Column(Modifier.heightIn(max = 560.dp).verticalScroll(rememberScrollState())) {
                AiSection(onCopyPrompt = { clipboard.setText(AnnotatedString(storeOrderAiPrompt())) })
                Spacer(Modifier.height(20.dp))
                Text("貼り付け", fontSize = 12.sp, color = DS.ink2)
                Spacer(Modifier.height(6.dp))
                Text(
                    "AI の結果か、アソビストアから届く「購入完了のご連絡」メールの本文を貼り付けてください。",
                    fontSize = 13.sp, color = DS.ink2
                )
                Spacer(Modifier.height(12.dp))
                OutlinedButton(onClick = { clipboard.getText()?.text?.let(::parse) }) {
                    Icon(Icons.Filled.ContentPaste, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text("ペースト")
                }
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = text, onValueChange = ::parse,
                    placeholder = { Text("または、ここに直接貼り付け") },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 160.dp),
                    textStyle = androidx.compose.ui.text.TextStyle(fontSize = 13.sp),
                )
                Text(
                    if (text.isNotEmpty()) {
                        "注文を読み取れませんでした。AI の結果はコードブロックの中身ごと、メールは「【注文番号】」から「【お買上金額】」までが入るように貼ってください。"
                    } else {
                        "何通ぶんでも続けて貼れます。送料やポイントの値引きも含めて、実際に払った額で記録します。"
                    },
                    fontSize = 11.sp, color = if (text.isNotEmpty()) DS.danger else DS.ink3,
                    modifier = Modifier.padding(top = 6.dp)
                )
            } else {
                LazyColumn(Modifier.fillMaxWidth().heightIn(max = 520.dp)) {
                    drafts.forEachIndexed { index, draft ->
                        item(key = "order_$index") {
                            OrderCard(
                                draft = draft,
                                showLabel = draft.showId?.let { id -> showOptions.firstOrNull { it.id == id }?.label },
                                onChange = { drafts[index] = it },
                                onPickShow = { pickingIndex = index },
                            )
                        }
                    }
                    item {
                        TextButton(onClick = { text = ""; drafts.clear() }) { Text("別の明細を貼り直す") }
                    }
                }
            }

            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                if (planned.isNotEmpty()) {
                    Column(Modifier.weight(1f)) {
                        Text("記録する額", fontSize = 12.sp, color = DS.ink2)
                        Text(formatYen(planned.sumOf { it.amount }), fontSize = 17.sp,
                            fontWeight = FontWeight.Bold, color = DS.ink)
                    }
                } else {
                    Spacer(Modifier.weight(1f))
                }
                TextButton(onClick = onDismiss) { Text("キャンセル") }
                Spacer(Modifier.width(8.dp))
                Button(
                    onClick = {
                        saving = true
                        onSave(planned.map {
                            Expense.make(it.date, it.category, it.amount, it.showId, it.eventId, it.note)
                        })
                    },
                    enabled = planned.isNotEmpty() && !saving
                ) { Text(if (planned.isEmpty()) "記録" else "${planned.size}件を記録") }
            }
        }
    }

    pickingIndex?.let { index ->
        LedgerShowPickerSheet(
            options = showOptions,
            onPick = { option ->
                drafts.getOrNull(index)?.let { drafts[index] = it.copy(showId = option?.id, eventId = option?.eventId) }
                pickingIndex = null
            },
            onDismiss = { pickingIndex = null }
        )
    }
}

/**
 * 指示文を入れて AI を開く。メール・マイページのスクリーンショットなど形の揃わない材料は
 * 利用者の AI に読ませ、アプリは決まった形の結果だけを読む (指示文と形はコアが持つ)。iOS `aiSection` と対。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AiSection(onCopyPrompt: () -> Unit) {
    val uriHandler = LocalUriHandler.current
    var copied by remember { mutableStateOf(false) }
    var pasteHint by remember { mutableStateOf<String?>(null) }
    Text("AI にまとめてもらう", fontSize = 12.sp, color = DS.ink2)
    Spacer(Modifier.height(6.dp))
    Column(Modifier.fillMaxWidth().background(DS.surface, RoundedCornerShape(10.dp)).padding(14.dp)) {
        Text(
            "メールやマイページのスクリーンショットから、AI に明細をまとめてもらえます。開いたら送信して、返ってきた結果をコピーして下に貼ってください。",
            fontSize = 13.sp, color = DS.ink2
        )
        Spacer(Modifier.height(10.dp))
        // 狭い画面では 3 つ並ばないので折り返す。
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            storeOrderAiLinks().forEach { link ->
                OutlinedButton(onClick = {
                    // 指示文を URL で渡せない AI には、先にクリップボードへ入れておく。
                    if (link.needsPaste) {
                        onCopyPrompt()
                        pasteHint = link.label
                    }
                    uriHandler.openUri(link.url)
                }) {
                    Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null)
                    Spacer(Modifier.width(4.dp))
                    Text(link.label)
                }
            }
        }
        pasteHint?.let {
            Text("指示文をコピーしました。${it}の入力欄に貼り付けて送信してください。",
                fontSize = 12.sp, color = DS.ink2, modifier = Modifier.padding(top = 6.dp))
        }
        TextButton(onClick = { onCopyPrompt(); copied = true }) {
            Icon(if (copied) Icons.Filled.Check else Icons.Filled.ContentCopy, contentDescription = null)
            Spacer(Modifier.width(6.dp))
            Text(if (copied) "指示文をコピーしました" else "ほかの AI 用に指示文をコピー", fontSize = 13.sp)
        }
    }
}

@Composable
private fun OrderCard(
    draft: DraftOrder,
    showLabel: String?,
    onChange: (DraftOrder) -> Unit,
    onPickShow: () -> Unit,
) {
    val order = draft.order
    Column(Modifier.padding(bottom = 16.dp)) {
        Text("${longDate(order.date)}　${order.store}", fontSize = 12.sp, color = DS.ink2,
            modifier = Modifier.padding(start = 4.dp, bottom = 6.dp))
        Column(Modifier.fillMaxWidth().background(DS.surface, RoundedCornerShape(10.dp))) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(formatYen(order.paidTotal), fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                    if (order.alreadyRecorded) {
                        Text("この注文は記録済みです", fontSize = 12.sp, color = DS.danger)
                    }
                    if (order.hasUnreadItems) {
                        Text("読み取れなかった品目があります。額は合計に含めています", fontSize = 12.sp, color = DS.danger)
                    }
                }
                Switch(checked = draft.include, onCheckedChange = { onChange(draft.copy(include = it)) })
            }
            if (draft.include) {
                order.items.forEachIndexed { i, item ->
                    HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 14.dp))
                    ItemRow(item) { updated ->
                        onChange(draft.copy(order = order.copy(items = order.items.toMutableList().also { it[i] = updated })))
                    }
                }
                if (order.adjustment != 0L) {
                    HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 14.dp))
                    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(
                                when {
                                    order.hasUnreadItems -> "その他の品目・送料など"
                                    order.adjustment > 0 -> "送料・手数料"
                                    else -> "ポイント・値引き"
                                },
                                fontSize = 13.sp, color = DS.ink
                            )
                            Text("一番多い費目に含めて記録します", fontSize = 11.sp, color = DS.ink3)
                        }
                        Text((if (order.adjustment > 0) "+" else "") + formatYen(order.adjustment),
                            fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
                    }
                }
                HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 14.dp))
                Row(Modifier.fillMaxWidth().clickable(onClick = onPickShow).padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(showLabel ?: "公演に紐づけない", fontSize = 13.sp,
                        color = if (showLabel == null) DS.ink2 else DS.ink, maxLines = 2, modifier = Modifier.weight(1f))
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = DS.ink3)
                }
            }
        }
        if (order.orderNumber.isNotEmpty()) {
            Text("注文番号 ${order.orderNumber}", fontSize = 11.sp, color = DS.ink3,
                modifier = Modifier.padding(start = 4.dp, top = 4.dp))
        }
    }
}

@Composable
private fun ItemRow(item: StoreOrderItem, onChange: (StoreOrderItem) -> Unit) {
    var menuOpen by remember { mutableStateOf(false) }
    val categories = remember { expenseCategories() }
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(
            if (item.included) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
            contentDescription = if (item.included) "記録から外す" else "記録に含める",
            tint = if (item.included) DS.ink else DS.ink3,
            modifier = Modifier.clickable { onChange(item.copy(included = !item.included)) }
        )
        Column(Modifier.weight(1f)) {
            Text(item.name, fontSize = 13.sp, color = if (item.included) DS.ink else DS.ink3, maxLines = 3)
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box {
                    Row(
                        Modifier.background(DS.fill, RoundedCornerShape(50))
                            .clickable(enabled = item.included) { menuOpen = true }
                            .padding(start = 10.dp, end = 4.dp, top = 2.dp, bottom = 2.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(expenseCategoryLabel(item.category), fontSize = 12.sp,
                            fontWeight = FontWeight.Bold, color = DS.ink2)
                        Icon(Icons.Filled.ArrowDropDown, contentDescription = null, tint = DS.ink2)
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        categories.forEach { info ->
                            DropdownMenuItem(
                                text = { Text(info.label) },
                                onClick = { onChange(item.copy(category = info.category)); menuOpen = false }
                            )
                        }
                    }
                }
                Spacer(Modifier.weight(1f))
                Text(
                    if (item.quantity > 1u) "${item.quantity}点 ${formatYen(item.subtotal)}" else formatYen(item.subtotal),
                    fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                    color = if (item.included) DS.ink else DS.ink3,
                    textDecoration = if (item.included) null else TextDecoration.LineThrough
                )
            }
        }
    }
}

private fun longDate(date: String): String {
    val parts = date.split("-").mapNotNull { it.toIntOrNull() }
    return if (parts.size == 3) "${parts[0]}年${parts[1]}月${parts[2]}日" else date
}
