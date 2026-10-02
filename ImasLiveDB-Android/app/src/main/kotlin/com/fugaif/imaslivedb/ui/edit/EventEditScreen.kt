package com.fugaif.imaslivedb.ui.edit

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.edit.putClearable
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.Vocab
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import kotlinx.coroutines.launch
import uniffi.imas_core.TicketSale

/**
 * ライブ (Event) の新規作成 / 編集。iOS `EventEditView` の移植。
 *
 * 新規作成は recordName を送らずサーバ採番に任せる (Song と違い、同一 batch から
 * この ID を参照する op が無いので採番を待てる)。
 *
 * @param original null なら新規作成。
 * @param initialBrandId 新規作成時のブランド初期選択。
 */
@Composable
fun EventEditScreen(
    original: Event? = null,
    initialBrandId: String? = null,
    onDismiss: () -> Unit,
    onSaved: (String) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val isCreate = original == null
    val key = original?.id ?: "new"

    var name by rememberSaveable(key) { mutableStateOf(original?.name ?: "") }
    var brandId by rememberSaveable(key) { mutableStateOf(original?.brandId ?: initialBrandId ?: "") }
    var kind by rememberSaveable(key) { mutableStateOf(original?.kind ?: "live") }
    var jointBrandIds by rememberSaveable(key) { mutableStateOf(original?.jointBrandIds ?: "") }
    var ticketUrl by rememberSaveable(key) { mutableStateOf(original?.ticketUrl ?: "") }

    var brands by remember { mutableStateOf<List<Brand>>(emptyList()) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var requestedIssueUrl by remember { mutableStateOf<String?>(null) }
    var requestSent by remember { mutableStateOf(false) }

    // チケット受付の一覧 (既存イベントのみ)。新規作成中はまだ event_id が無いので出さない。
    var ticketSales by remember(key) { mutableStateOf<List<TicketSale>>(emptyList()) }
    var salesReloadToken by remember(key) { mutableIntStateOf(0) }
    var editingSale by remember { mutableStateOf<TicketSale?>(null) }
    var creatingSale by remember { mutableStateOf(false) }
    LaunchedEffect(key, salesReloadToken) {
        ticketSales = original?.let {
            runCatching { AppModule.from(context).eventRepository.fetchTicketSales(it.id) }.getOrDefault(emptyList())
        } ?: emptyList()
    }

    LaunchedEffect(Unit) {
        brands = runCatching { AppModule.from(context).statsRepository.fetchBrands() }.getOrDefault(emptyList())
    }
    val brandOptions = remember(brands) { listOf("" to "未指定") + brands.map { it.id to it.name } }

    fun save() {
        val trimmedName = name.trim()
        // iOS EventEditView.save() と同条件: イベント名だけが必須。
        if (trimmedName.isEmpty()) {
            errorMessage = "イベント名を入力してください"; return
        }

        // 互換フィールド (isStreaming / isSolo) は既存値を維持し、新規は既定値。
        // フォームに出さないが、サーバ側の create 必須チェックと一覧の絞り込みが見ている。
        // eventType は催しの性格なので新規は**未分類**。iOS EventEditView.save() と同じ。
        val eventType = original?.eventType ?: ""
        val isStreaming = original?.isStreaming ?: false
        val isSolo = original?.isSolo ?: false
        val resolvedBrandId = brandId.ifEmpty { null }

        val fields = mutableMapOf<String, Any?>(
            "name" to trimmedName,
            "eventType" to eventType,
            "isStreaming" to if (isStreaming) 1 else 0,
            "isSolo" to if (isSolo) 1 else 0,
            "kind" to kind
        )
        fields.putClearable("brandId", brandId, original?.brandId)
        fields.putClearable("ticketUrl", ticketUrl, original?.ticketUrl)
        fields.putClearable("jointBrandIds", jointBrandIds, original?.jointBrandIds)

        val op = EditApi.EditOperation(
            op = if (isCreate) EditApi.EditOp.CREATE else EditApi.EditOp.UPDATE,
            recordType = "Event",
            recordName = original?.id,
            fields = fields
        )

        isSaving = true
        scope.launch {
            val result = submitMasterEdit(
                context = context,
                ops = listOf(op),
                summary = if (isCreate) "イベント追加" else "イベント編集",
                fallbackRecordName = original?.id
            ) { resolvedId ->
                // nameKana はフォームに無い列。copy で引き継がないと Room の REPLACE で消える。
                val saved = (original ?: emptyEvent(resolvedId)).copy(
                    id = resolvedId,
                    brandId = resolvedBrandId,
                    name = trimmedName,
                    eventType = eventType,
                    isStreaming = isStreaming,
                    isSolo = isSolo,
                    kind = kind,
                    ticketUrl = ticketUrl.nonEmptyTrimmed(),
                    jointBrandIds = jointBrandIds.nonEmptyTrimmed()
                )
                AppModule.from(context).masterEditRepository.applyEvent(saved)
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

    MasterEditScaffold(
        title = if (isCreate) "ライブを追加" else "ライブ編集",
        canSave = name.trim().isNotEmpty(),
        isSaving = isSaving,
        onCancel = onDismiss,
        onSave = ::save
    ) {
        EditSection("基本情報", footer = "合同ブランドはブランド ID をカンマ区切りで (例: 315,283)。") {
            if (original != null) EditReadonlyRow("ID", original.id)
            EditTextField("イベント名", name, { name = it })
            EditDropdownField("ブランド", brandOptions, brandId) { brandId = it }
            EditDropdownField("種別", eventKindEditOptions(original?.kind), kind) { kind = it }
            EditTextField("合同ブランド (カンマ区切り)", jointBrandIds, { jointBrandIds = it })
        }
        EditSection("チケット") {
            EditTextField("公式チケットページ URL", ticketUrl, { ticketUrl = it })
        }
        if (original != null) {
            EditSection("チケット受付", footer = "受付ごとの日程・当落・申込リンクは各行から編集します。") {
                if (ticketSales.isEmpty()) {
                    ImasNote("受付は未登録です")
                } else {
                    ticketSales.forEach { sale ->
                        TicketSaleSummaryRow(sale, onClick = { editingSale = sale })
                    }
                }
                ImasActionRow(title = "受付を追加", onClick = { creatingSale = true }, icon = Icons.Filled.Add)
            }
        }
    }

    errorMessage?.let { EditErrorDialog(it) { errorMessage = null } }

    if (requestSent) {
        EditRequestSentDialog(requestedIssueUrl) { requestSent = false; onDismiss() }
    }

    val eventId = original?.id
    if (creatingSale && eventId != null) {
        Dialog(onDismissRequest = { creatingSale = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            TicketSaleEditScreen(
                eventId = eventId,
                suggestedSortOrder = ticketSales.size,
                onDismiss = { creatingSale = false },
                onSaved = { creatingSale = false; salesReloadToken++ }
            )
        }
    }

    val currentEditingSale = editingSale
    if (currentEditingSale != null && eventId != null) {
        Dialog(onDismissRequest = { editingSale = null }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            TicketSaleEditScreen(
                eventId = eventId,
                original = currentEditingSale,
                onDismiss = { editingSale = null },
                onSaved = { editingSale = null; salesReloadToken++ },
                onDeleted = { editingSale = null; salesReloadToken++ }
            )
        }
    }
}

/** チケット受付 1 件の要約行 (種別・段階・期間)。タップで編集を開く。 */
@Composable
private fun TicketSaleSummaryRow(sale: TicketSale, onClick: () -> Unit) {
    ImasRow(
        title = "${sale.kindLabel} ・ ${sale.name}",
        modifier = Modifier.imasRowPress(onClick = onClick),
        subtitle = listOfNotNull(sale.stageLabel, sale.periodLabel).joinToString(" ・ "),
        trailing = ImasRowTrailing.Chevron,
        density = ImasRowDensity.COMPACT,
        titleRole = ImasTextRole.ROW_LABEL
    )
}

/** 新規作成時の土台。フォームで埋める列以外は既定値にする。 */
private fun emptyEvent(id: String) = Event(
    id = id,
    brandId = null,
    name = "",
    eventType = "",
    isStreaming = false
)

/**
 * 種別の選択肢。語彙の種別から受け皿の「その他」を外し、元の値が語彙に無い (または `other`)
 * ときだけ「変更しない (元の値)」を足す。選び直さない限り、状態は元の生の値のまま送り返す
 * (黙って `other` などに書き換えると、新しい種別のイベントを直した人がその種別を消してしまう)。
 * iOS `EventEditView` と同じ。
 */
internal fun eventKindEditOptions(originalKind: String?): List<Pair<String, String>> {
    val listed = Vocab.table.eventKinds.filter { it.value != OTHER_EVENT_KIND }.map { it.value to it.shortLabel }
    val unlisted = originalKind?.takeIf { raw -> listed.none { it.first == raw } }
    return listed + listOfNotNull(unlisted?.let { it to "変更しない ($it)" })
}

/** 語彙の「その他」(知らない種別の受け皿)。選択肢には出さない。 */
private const val OTHER_EVENT_KIND = "other"

