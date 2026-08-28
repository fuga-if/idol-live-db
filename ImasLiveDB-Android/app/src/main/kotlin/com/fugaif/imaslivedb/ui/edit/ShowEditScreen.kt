package com.fugaif.imaslivedb.ui.edit

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.edit.putClearable
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.launch

/** 出演形態。iOS `ShowEditView.performerTypes` と同じ 4 択 (空 = 未指定)。 */
private val PERFORMER_TYPES = listOf(
    "" to "未指定",
    "character" to "character",
    "cast" to "cast",
    "mixed" to "mixed"
)

/**
 * 公演 (Show) の新規作成 / 編集。iOS `ShowEditView` の移植。
 *
 * 新規作成は必ず親イベントの詳細画面から開く ([eventId] が必須のため)。
 * recordName はサーバ採番に任せる。
 *
 * @param original null なら新規作成。
 * @param eventId 親イベント ID。編集時は original.eventId と同じ値を渡すこと。
 * @param suggestedSortOrder 新規作成時の並び順初期値 (既存公演数を渡す想定)。
 */
@Composable
fun ShowEditScreen(
    original: Show? = null,
    eventId: String,
    suggestedSortOrder: Int = 0,
    onDismiss: () -> Unit,
    onSaved: (String) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val isCreate = original == null
    val key = original?.id ?: "new"

    var name by rememberSaveable(key) { mutableStateOf(original?.name ?: "") }
    var date by rememberSaveable(key) { mutableStateOf(original?.date ?: "") }
    var venue by rememberSaveable(key) { mutableStateOf(original?.venue ?: "") }
    var venueCity by rememberSaveable(key) { mutableStateOf(original?.venueCity ?: "") }
    var startTime by rememberSaveable(key) { mutableStateOf(original?.startTime ?: "") }
    var sortOrder by rememberSaveable(key) { mutableIntStateOf(original?.sortOrder ?: suggestedSortOrder) }
    var performerType by rememberSaveable(key) { mutableStateOf(original?.performerType ?: "") }

    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var requestedIssueUrl by remember { mutableStateOf<String?>(null) }
    var requestSent by remember { mutableStateOf(false) }

    fun save() {
        val trimmedName = name.trim()
        val trimmedDate = date.trim()
        // iOS ShowEditView.save() と同条件: 公演名と日付が必須、日付は YYYY-MM-DD。
        if (trimmedName.isEmpty() || trimmedDate.isEmpty()) {
            errorMessage = "公演名と日付は必須です"; return
        }
        if (!isValidShowDate(trimmedDate)) {
            errorMessage = "日付は YYYY-MM-DD 形式で入力してください"; return
        }

        val fields = mutableMapOf<String, Any?>(
            "eventId" to eventId,
            "name" to trimmedName,
            "date" to trimmedDate,
            "sortOrder" to sortOrder
        )
        fields.putClearable("venue", venue, original?.venue)
        fields.putClearable("venueCity", venueCity, original?.venueCity)
        fields.putClearable("startTime", startTime, original?.startTime)
        fields.putClearable("performerType", performerType, original?.performerType)

        val op = EditApi.EditOperation(
            op = if (isCreate) EditApi.EditOp.CREATE else EditApi.EditOp.UPDATE,
            recordType = "Show",
            recordName = original?.id,
            fields = fields
        )

        isSaving = true
        scope.launch {
            val result = submitMasterEdit(
                context = context,
                ops = listOf(op),
                summary = if (isCreate) "公演追加" else "公演編集",
                fallbackRecordName = original?.id
            ) { resolvedId ->
                // venueId / hall / streamPlatform はフォームに無い列。copy で引き継がないと
                // Room の REPLACE で消え、会場の同一性 (venue_id) まで失われる。
                val saved = (original ?: emptyShow(resolvedId, eventId)).copy(
                    id = resolvedId,
                    eventId = eventId,
                    name = trimmedName,
                    date = trimmedDate,
                    venue = venue.nonEmptyTrimmed(),
                    venueCity = venueCity.nonEmptyTrimmed(),
                    startTime = startTime.nonEmptyTrimmed(),
                    sortOrder = sortOrder,
                    performerType = performerType.nonEmptyTrimmed()
                )
                AppModule.from(context).database.syncDao().upsertShows(listOf(saved))
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
        title = if (isCreate) "公演を追加" else "公演編集",
        canSave = name.trim().isNotEmpty() && date.trim().isNotEmpty(),
        isSaving = isSaving,
        onCancel = onDismiss,
        onSave = ::save
    ) {
        EditSection("基本情報") {
            if (original != null) EditReadonlyRow("ID", original.id)
            EditTextField("公演名", name, { name = it })
            EditTextField("日付 (YYYY-MM-DD)", date, { date = it })
            EditTextField("会場", venue, { venue = it })
            EditTextField("会場所在地", venueCity, { venueCity = it })
            EditTextField("開演時刻 (HH:mm)", startTime, { startTime = it })
            EditStepperRow("並び順", sortOrder, 0..999) { sortOrder = it }
            EditDropdownField("出演形態", PERFORMER_TYPES, performerType) { performerType = it }
        }
    }

    errorMessage?.let { EditErrorDialog(it) { errorMessage = null } }

    if (requestSent) {
        EditRequestSentDialog(requestedIssueUrl) { requestSent = false; onDismiss() }
    }
}

/** 新規作成時の土台。フォームで埋める列以外は既定値にする。 */
private fun emptyShow(id: String, eventId: String) = Show(
    id = id,
    eventId = eventId,
    name = "",
    date = "",
    venue = null,
    venueCity = null,
    startTime = null,
    sortOrder = 0,
    performerType = null
)
