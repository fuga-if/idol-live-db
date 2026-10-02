package com.fugaif.imaslivedb.ui.ledger

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.Expense
import com.fugaif.imaslivedb.data.repository.LedgerShowOption
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextArea
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRowChevron
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectionMark
import com.fugaif.imaslivedb.ui.designsystem.ImasStep
import com.fugaif.imaslivedb.ui.designsystem.ImasStepList
import com.fugaif.imaslivedb.ui.designsystem.ImasSwitch
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import java.time.LocalDate
import uniffi.imas_core.StoreExpenseDraft
import uniffi.imas_core.StoreOrder
import uniffi.imas_core.StoreOrderItem
import uniffi.imas_core.StoreShowCandidate
import uniffi.imas_core.asobiOrderHistoryUrl
import uniffi.imas_core.expenseCategories
import uniffi.imas_core.expenseCategoryLabel
import uniffi.imas_core.formatYen
import uniffi.imas_core.parseStoreOrders
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
            // 記録済みの注文・チケットだけの注文は最初から外しておく (判断はコア)。
            drafts += DraftOrder(order, order.includeByDefault, order.suggestedShowId, order.suggestedEventId)
        }
    }

    val planned: List<StoreExpenseDraft> = drafts.filter { it.include }
        .flatMap { storeOrderExpenses(it.order, it.showId, it.eventId) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = DS.bg,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(Modifier.padding(horizontal = DS.Space.screen).padding(bottom = DS.Space.section)) {
            Text("アソビストアの明細", style = ImasType.heading(17.sp, FontWeight.Bold), color = DS.ink)
            Spacer(Modifier.height(DS.Space.card))

            if (drafts.isEmpty()) {
                Column(
                    Modifier.heightIn(max = 560.dp).verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(DS.Space.header)
                ) {
                    GuideCard()
                    ImasNote("「購入完了のご連絡」メールの本文を貼っても読めます。メールなら品名まで入ります。")
                    ImasFormCard {
                        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                            OutlinedButton(onClick = { clipboard.getText()?.text?.let(::parse) }) {
                                Icon(Icons.Filled.ContentPaste, contentDescription = null)
                                Spacer(Modifier.width(DS.Space.gapTight))
                                Text("ペースト")
                            }
                            ImasFormTextArea(
                                label = "貼り付け",
                                imprint = "PASTE",
                                text = text,
                                onTextChange = ::parse,
                                prompt = "または、ここに直接貼り付け"
                            )
                        }
                    }
                    Text(
                        if (text.isNotEmpty()) {
                            "注文を読み取れませんでした。購入履歴は表の見出しの行から、メールは「【注文番号】」から「【お買上金額】」までが入るように貼ってください。"
                        } else {
                            "送料やポイントの値引きも含めて、実際に払った額で記録します。チケット代は公演の参加から記録するので、チケットは最初から外してあります。"
                        },
                        style = ImasTextRole.NOTE.style,
                        color = if (text.isNotEmpty()) DS.danger else ImasTextRole.NOTE.color
                    )
                }
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

            Spacer(Modifier.height(DS.Space.gapLoose))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                if (planned.isNotEmpty()) {
                    Column(Modifier.weight(1f)) {
                        Text("記録する額", style = ImasTextRole.META.style, color = ImasTextRole.META.color)
                        Text(
                            formatYen(planned.sumOf { it.amount }),
                            style = ImasType.heading(17.sp, FontWeight.Bold),
                            color = DS.ink
                        )
                    }
                } else {
                    Spacer(Modifier.weight(1f))
                }
                TextButton(onClick = onDismiss) { Text("キャンセル") }
                Spacer(Modifier.width(DS.Space.gap))
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

/** 手順の案内。購入履歴一覧の表をコピーするのが一番手早い (1 画面で全注文が出る)。iOS `guideCard` と対。 */
@Composable
private fun GuideCard() {
    val uriHandler = LocalUriHandler.current
    ImasFormCard {
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
            Text("取り込み方", style = ImasTextRole.SECTION_LABEL.style, color = ImasTextRole.SECTION_LABEL.color)
            ImasStepList(
                steps = listOf(
                    ImasStep(
                        title = "アソビストアの購入履歴を開く",
                        media = {
                            OutlinedButton(onClick = { uriHandler.openUri(asobiOrderHistoryUrl()) }) {
                                Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null)
                                Spacer(Modifier.width(DS.Space.gapTight))
                                Text("購入履歴を開く")
                            }
                        }
                    ),
                    ImasStep(title = "「購入履歴一覧」の表を、見出しから最後の行まで選んでコピーする"),
                    ImasStep(title = "下の「ペースト」を押す")
                )
            )
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
    Column(Modifier.padding(bottom = DS.Space.card), verticalArrangement = Arrangement.spacedBy(DS.Space.header)) {
        Text(
            "${longDate(order.date)}　${order.store}",
            style = ImasTextRole.SECTION_LABEL.style,
            color = ImasTextRole.SECTION_LABEL.color
        )
        ImasFormCard {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.rowGap)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                        Text(
                            formatYen(order.paidTotal),
                            style = ImasType.text(17.sp, FontWeight.Bold).copy(fontFeatureSettings = "tnum"),
                            color = DS.ink
                        )
                        if (order.alreadyRecorded) {
                            Text("この注文は記録済みです", style = ImasTextRole.NOTE.style, color = DS.danger)
                        }
                        if (order.hasUnreadItems) {
                            Text("読み取れなかった品目があります。額は合計に含めています", style = ImasTextRole.NOTE.style, color = DS.danger)
                        }
                    }
                    ImasSwitch(checked = draft.include, onCheckedChange = { onChange(draft.copy(include = it)) })
                }
                if (draft.include) {
                    order.items.forEachIndexed { i, item ->
                        ItemRow(item) { updated ->
                            onChange(draft.copy(order = order.copy(items = order.items.toMutableList().also { it[i] = updated })))
                        }
                    }
                    if (order.adjustment != 0L) {
                        AdjustmentRow(order)
                    }
                    ShowRow(showLabel, onPickShow)
                }
            }
        }
        if (order.orderNumber.isNotEmpty()) {
            ImasNote("注文番号 ${order.orderNumber}")
        }
    }
}

@Composable
private fun ItemRow(item: StoreOrderItem, onChange: (StoreOrderItem) -> Unit) {
    var menuOpen by remember { mutableStateOf(false) }
    val categories = remember { expenseCategories() }
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)
    ) {
        Box(
            Modifier
                .clickable(onClickLabel = if (item.included) "記録から外す" else "記録に含める") {
                    onChange(item.copy(included = !item.included))
                }
                .semantics { contentDescription = if (item.included) "記録から外す" else "記録に含める" }
        ) {
            ImasSelectionMark(isSelected = item.included)
        }
        Column(Modifier.weight(1f)) {
            Text(
                item.name,
                style = ImasType.text(13.sp),
                color = if (item.included) DS.ink else DS.ink3,
                maxLines = 3
            )
            Spacer(Modifier.height(DS.Space.gapTight))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Row(
                    Modifier.clickable(enabled = item.included) { menuOpen = true },
                    horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(expenseCategoryLabel(item.category), style = ImasTextRole.VALUE.style, color = DS.ink2)
                    Icon(
                        Icons.Filled.UnfoldMore,
                        contentDescription = "費目: ${expenseCategoryLabel(item.category)}",
                        tint = DS.ink3
                    )
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    categories.forEach { info ->
                        DropdownMenuItem(
                            text = { Text(info.label) },
                            onClick = { onChange(item.copy(category = info.category)); menuOpen = false }
                        )
                    }
                }
                Spacer(Modifier.weight(1f))
                Text(
                    if (item.quantity > 1u) "${item.quantity}点 ${formatYen(item.subtotal)}" else formatYen(item.subtotal),
                    style = ImasType.text(13.sp, FontWeight.SemiBold).copy(fontFeatureSettings = "tnum"),
                    color = if (item.included) DS.ink else DS.ink3,
                    textDecoration = if (item.included) null else TextDecoration.LineThrough
                )
            }
        }
    }
}

@Composable
private fun AdjustmentRow(order: StoreOrder) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
            Text(
                when {
                    order.hasUnreadItems -> "その他の品目・送料など"
                    order.adjustment > 0 -> "送料・手数料"
                    else -> "ポイント・値引き"
                },
                style = ImasType.text(13.sp),
                color = DS.ink
            )
            Text("一番多い費目に含めて記録します", style = ImasTextRole.META.style, color = ImasTextRole.META.color)
        }
        Text(
            (if (order.adjustment > 0) "+" else "") + formatYen(order.adjustment),
            style = ImasType.text(13.sp, FontWeight.SemiBold).copy(fontFeatureSettings = "tnum"),
            color = DS.ink2
        )
    }
}

@Composable
private fun ShowRow(showLabel: String?, onPickShow: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onPickShow),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)
    ) {
        Icon(Icons.Filled.Mic, contentDescription = null, tint = DS.ink3)
        Text(
            showLabel ?: "公演に紐づけない",
            style = ImasType.text(13.sp),
            color = if (showLabel == null) DS.ink2 else DS.ink,
            maxLines = 2,
            modifier = Modifier.weight(1f)
        )
        ImasRowChevron()
    }
}

private fun longDate(date: String): String {
    val parts = date.split("-").mapNotNull { it.toIntOrNull() }
    return if (parts.size == 3) "${parts[0]}年${parts[1]}月${parts[2]}日" else date
}
