package com.fugaif.imaslivedb.ui.edit

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.edit.putClearable
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.Vocab
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch
import uniffi.imas_core.TicketSale
import uniffi.imas_core.TicketSaleDraft
import uniffi.imas_core.TicketSaleKind
import uniffi.imas_core.normalizeTicketSaleMoment
import uniffi.imas_core.ticketSaleIssueMessage
import uniffi.imas_core.ticketSaleKindRaw
import uniffi.imas_core.validateTicketSaleDraft

/**
 * チケット受付 (TicketSale) の新規作成 / 編集 / 削除。iOS `TicketSaleEditView` の移植。
 *
 * 判定・並び・検査の文言は一切ここに持たせない。入力検査 ([validateTicketSaleDraft]) と
 * その文言 ([ticketSaleIssueMessage]) は共有コアが持ち、ここは材料を集めて 1 回呼ぶだけ。
 * 新規作成は必ず親イベントの編集画面から開く ([eventId] が必須のため)。
 *
 * @param original null なら新規作成。
 * @param eventId 親イベント ID。編集時は original.eventId と同じ値を渡すこと。
 * @param suggestedSortOrder 新規作成時の並び順初期値 (既存受付数を渡す想定)。
 */
@Composable
fun TicketSaleEditScreen(
    eventId: String,
    original: TicketSale? = null,
    suggestedSortOrder: Int = 0,
    onDismiss: () -> Unit,
    onSaved: (String) -> Unit,
    onDeleted: () -> Unit = {}
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val isCreate = original == null
    val key = original?.id ?: "new"

    // TicketSaleKind の raw 値はコアが決める (lottery / first_come / resale / same_day)。
    // 表示名だけコアの vocabulary から引き、選択肢の並びは enum の宣言順に揃える。
    val kindByRaw = remember { TicketSaleKind.entries.associateBy { ticketSaleKindRaw(it) } }
    val kindOptions = remember {
        TicketSaleKind.entries.map { k ->
            val raw = ticketSaleKindRaw(k)
            raw to (Vocab.ticketSaleKind(raw)?.label ?: raw)
        }
    }
    fun kindOf(raw: String): TicketSaleKind = kindByRaw[raw] ?: TicketSaleKind.LOTTERY

    var kindRaw by rememberSaveable(key) { mutableStateOf(original?.let { ticketSaleKindRaw(it.kind) } ?: kindOptions.first().first) }
    var name by rememberSaveable(key) { mutableStateOf(original?.name ?: "") }
    var startsAt by rememberSaveable(key) { mutableStateOf(original?.startsAt ?: "") }
    var endsAt by rememberSaveable(key) { mutableStateOf(original?.endsAt ?: "") }
    var resultAt by rememberSaveable(key) { mutableStateOf(original?.resultAt ?: "") }
    var url by rememberSaveable(key) { mutableStateOf(original?.url ?: "") }
    var note by rememberSaveable(key) { mutableStateOf(original?.note ?: "") }
    var sourceUrl by rememberSaveable(key) { mutableStateOf(original?.sourceUrl ?: "") }
    var sortOrder by rememberSaveable(key) { mutableStateOf(original?.sortOrder?.toInt() ?: suggestedSortOrder) }
    // 空 = 全公演対象。Set は既定の Saver が無いので rememberSaveable ではなく remember にする
    // (設定変更での復元は諦めるが、公演の選び直しは軽い操作なので実害は小さい)。
    var selectedShowIds by remember(key) { mutableStateOf(original?.showIds?.toSet() ?: emptySet()) }

    var shows by remember { mutableStateOf<List<Show>>(emptyList()) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var requestedIssueUrl by remember { mutableStateOf<String?>(null) }
    var requestSent by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(eventId) {
        shows = runCatching { AppModule.from(context).eventRepository.fetchShows(eventId) }.getOrDefault(emptyList())
    }

    /** ゆるい表記 ("2026/4/12 23:59" 等) をコアの正規形に直す。直せなければそのまま渡し、検査に任せる。 */
    fun normalizedMoment(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        return normalizeTicketSaleMoment(trimmed) ?: trimmed
    }

    fun buildDraft(): TicketSaleDraft = TicketSaleDraft(
        eventId = eventId,
        showIds = selectedShowIds.toList(),
        kind = kindOf(kindRaw),
        name = name.trim(),
        startsAt = normalizedMoment(startsAt),
        endsAt = normalizedMoment(endsAt),
        resultAt = normalizedMoment(resultAt),
        url = url.trim().ifEmpty { null },
        note = note.trim().ifEmpty { null },
        sourceUrl = sourceUrl.trim(),
        sortOrder = sortOrder.toLong()
    )

    fun save() {
        val draft = buildDraft()
        val issues = validateTicketSaleDraft(draft, shows.map { it.id })
        if (issues.isNotEmpty()) {
            errorMessage = issues.joinToString("\n") { ticketSaleIssueMessage(it) }
            return
        }

        val fields = mutableMapOf<String, Any?>(
            "eventId" to draft.eventId,
            "kind" to ticketSaleKindRaw(draft.kind),
            "name" to draft.name,
            "sourceUrl" to draft.sourceUrl,
            "sortOrder" to draft.sortOrder
        )
        fields.putClearable(
            "showIds",
            draft.showIds.joinToString(","),
            original?.showIds?.takeIf { it.isNotEmpty() }?.joinToString(",")
        )
        fields.putClearable("startsAt", draft.startsAt.orEmpty(), original?.startsAt)
        fields.putClearable("endsAt", draft.endsAt.orEmpty(), original?.endsAt)
        fields.putClearable("resultAt", draft.resultAt.orEmpty(), original?.resultAt)
        fields.putClearable("url", draft.url.orEmpty(), original?.url)
        fields.putClearable("note", draft.note.orEmpty(), original?.note)

        val op = EditApi.EditOperation(
            op = if (isCreate) EditApi.EditOp.CREATE else EditApi.EditOp.UPDATE,
            recordType = "TicketSale",
            recordName = original?.id,
            fields = fields
        )

        isSaving = true
        scope.launch {
            val result = submitMasterEdit(
                context = context,
                ops = listOf(op),
                summary = if (isCreate) "チケット受付追加" else "チケット受付編集",
                fallbackRecordName = original?.id
            ) { resolvedId ->
                val row = com.fugaif.imaslivedb.data.model.TicketSale(
                    id = resolvedId,
                    eventId = draft.eventId,
                    showIds = draft.showIds.takeIf { it.isNotEmpty() }?.joinToString(","),
                    kind = ticketSaleKindRaw(draft.kind),
                    name = draft.name,
                    startsAt = draft.startsAt,
                    endsAt = draft.endsAt,
                    resultAt = draft.resultAt,
                    url = draft.url,
                    note = draft.note,
                    sourceUrl = draft.sourceUrl,
                    sortOrder = draft.sortOrder
                )
                AppModule.from(context).masterEditRepository.applyTicketSale(row)
            }
            isSaving = false
            when (result) {
                is MasterEditSubmitResult.Applied -> onSaved(result.recordName)
                is MasterEditSubmitResult.Requested -> {
                    requestedIssueUrl = result.issueUrl
                    requestSent = true
                }
                is MasterEditSubmitResult.Failed -> errorMessage = result.message
            }
        }
    }

    fun delete() {
        val id = original?.id ?: return
        val op = EditApi.EditOperation(op = EditApi.EditOp.DELETE, recordType = "TicketSale", recordName = id)
        isSaving = true
        scope.launch {
            val result = submitMasterEdit(
                context = context,
                ops = listOf(op),
                summary = "チケット受付削除",
                fallbackRecordName = id
            ) {
                AppModule.from(context).masterEditRepository.deleteTicketSale(id)
            }
            isSaving = false
            when (result) {
                is MasterEditSubmitResult.Applied -> onDeleted()
                is MasterEditSubmitResult.Requested -> {
                    requestedIssueUrl = result.issueUrl
                    requestSent = true
                }
                is MasterEditSubmitResult.Failed -> errorMessage = result.message
            }
        }
    }

    MasterEditScaffold(
        title = if (isCreate) "受付を追加" else "受付を編集",
        canSave = name.trim().isNotEmpty() && sourceUrl.trim().isNotEmpty(),
        isSaving = isSaving,
        onCancel = onDismiss,
        onSave = ::save
    ) {
        EditSection("基本情報") {
            if (original != null) EditReadonlyRow("ID", original.id)
            EditDropdownField("種別", kindOptions, kindRaw) { kindRaw = it }
            EditTextField("受付名 (例: 先行抽選)", name, { name = it })
        }
        EditSection(
            "対象公演",
            footer = "選択が無ければ全公演が対象になります。"
        ) {
            if (shows.isEmpty()) {
                Text("この公演の一覧を読み込めませんでした", fontSize = 12.sp, color = DS.ink3)
            } else {
                shows.forEach { show ->
                    ShowCheckRow(
                        show = show,
                        checked = selectedShowIds.contains(show.id),
                        onToggle = {
                            selectedShowIds = if (selectedShowIds.contains(show.id)) {
                                selectedShowIds - show.id
                            } else {
                                selectedShowIds + show.id
                            }
                        }
                    )
                }
            }
        }
        EditSection(
            "日程",
            footer = "YYYY-MM-DD または YYYY-MM-DD HH:MM で入力してください。"
        ) {
            EditTextField("受付開始", startsAt, { startsAt = it })
            EditTextField("申込締切", endsAt, { endsAt = it })
            EditTextField("当落発表 (抽選のみ)", resultAt, { resultAt = it })
        }
        EditSection("リンク") {
            EditTextField("申込 URL", url, { url = it })
            EditTextField("出典 URL (必須)", sourceUrl, { sourceUrl = it })
            EditTextField("メモ", note, { note = it }, singleLine = false, minLines = 2)
        }
        EditSection("並び順") {
            EditStepperRow("並び順", sortOrder, 0..999) { sortOrder = it }
        }
        if (!isCreate) {
            EditSection("削除") {
                TextButton(onClick = { showDeleteConfirm = true }) {
                    Text("この受付を削除", color = DS.danger)
                }
            }
        }
    }

    errorMessage?.let { EditErrorDialog(it) { errorMessage = null } }

    if (requestSent) {
        EditRequestSentDialog(requestedIssueUrl) { requestSent = false; onDismiss() }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("受付を削除しますか？") },
            text = { Text("この操作は取り消せません。") },
            confirmButton = {
                TextButton(onClick = { showDeleteConfirm = false; delete() }) { Text("削除", color = DS.danger) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("キャンセル") }
            }
        )
    }
}

@Composable
private fun ShowCheckRow(show: Show, checked: Boolean, onToggle: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onToggle).padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (checked) {
            Icon(Icons.Filled.Check, contentDescription = null, tint = DS.pick, modifier = Modifier.padding(end = 8.dp))
        } else {
            Spacer(Modifier.padding(end = 8.dp).size(24.dp))
        }
        Text("${show.name} ・ ${show.date.take(10)}", color = DS.ink)
    }
}
