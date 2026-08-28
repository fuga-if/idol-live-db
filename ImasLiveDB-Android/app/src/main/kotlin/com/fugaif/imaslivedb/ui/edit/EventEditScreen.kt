package com.fugaif.imaslivedb.ui.edit

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.edit.putClearable
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.events.EVENT_KINDS
import kotlinx.coroutines.launch

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
    var ticketOpenDate by rememberSaveable(key) { mutableStateOf(original?.ticketOpenDate ?: "") }
    var ticketDeadline by rememberSaveable(key) { mutableStateOf(original?.ticketDeadline ?: "") }
    var ticketLotteryDate by rememberSaveable(key) { mutableStateOf(original?.ticketLotteryDate ?: "") }
    var ticketUrl by rememberSaveable(key) { mutableStateOf(original?.ticketUrl ?: "") }

    var brands by remember { mutableStateOf<List<Brand>>(emptyList()) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var requestedIssueUrl by remember { mutableStateOf<String?>(null) }
    var requestSent by remember { mutableStateOf(false) }

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

        // 互換フィールド (eventType / isStreaming / isSolo) は既存値を維持し、新規は既定値。
        // フォームに出さないが、サーバ側の create 必須チェックと一覧の絞り込みが見ている。
        val eventType = original?.eventType ?: "live"
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
        // 注意: サーバの FIELD_RULES (imas-live-api/src/master_validators.ts) には
        // ticketOpenDate が無く、一般ユーザーが値を入れると 400 になる。iOS EventEditView も
        // 同じものを送っているので、ここで勝手に落とすと iOS とフォームがズレる。
        // 直すのはサーバ側 (allowlist への追加) なので、揃えたまま残す。
        fields.putClearable("ticketOpenDate", ticketOpenDate, original?.ticketOpenDate)
        fields.putClearable("ticketDeadline", ticketDeadline, original?.ticketDeadline)
        fields.putClearable("ticketLotteryDate", ticketLotteryDate, original?.ticketLotteryDate)
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
                    ticketOpenDate = ticketOpenDate.nonEmptyTrimmed(),
                    ticketDeadline = ticketDeadline.nonEmptyTrimmed(),
                    ticketLotteryDate = ticketLotteryDate.nonEmptyTrimmed(),
                    ticketUrl = ticketUrl.nonEmptyTrimmed(),
                    jointBrandIds = jointBrandIds.nonEmptyTrimmed()
                )
                AppModule.from(context).database.syncDao().upsertEvents(listOf(saved))
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
            EditDropdownField("種別", EVENT_KINDS, kind) { kind = it }
            EditTextField("合同ブランド (カンマ区切り)", jointBrandIds, { jointBrandIds = it })
        }
        EditSection("チケット") {
            EditTextField("受付開始 (YYYY-MM-DD)", ticketOpenDate, { ticketOpenDate = it })
            EditTextField("先行締切 (YYYY-MM-DD)", ticketDeadline, { ticketDeadline = it })
            EditTextField("当落発表 (YYYY-MM-DD)", ticketLotteryDate, { ticketLotteryDate = it })
            EditTextField("URL", ticketUrl, { ticketUrl = it })
        }
    }

    errorMessage?.let { EditErrorDialog(it) { errorMessage = null } }

    if (requestSent) {
        EditRequestSentDialog(requestedIssueUrl) { requestSent = false; onDismiss() }
    }
}

/** 新規作成時の土台。フォームで埋める列以外は既定値にする。 */
private fun emptyEvent(id: String) = Event(
    id = id,
    brandId = null,
    name = "",
    eventType = "live",
    isStreaming = false
)
