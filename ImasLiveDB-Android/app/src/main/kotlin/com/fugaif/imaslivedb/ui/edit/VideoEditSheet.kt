package com.fugaif.imaslivedb.ui.edit

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.edit.friendlyMessage
import com.fugaif.imaslivedb.data.model.SongVideo
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextArea
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextField
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID
import uniffi.imas_core.youtubeIsUploadUrl

private const val MAX_VIDEO_TITLE = 300
private const val MAX_VIDEO_NOTE = 1000

/**
 * 参考動画 (SongVideo) の投稿・編集フォーム。iOS `VideoEditView` の移植。
 *
 * SongVideo はコミュニティ型レコードなので、一般ユーザーでも
 * `POST /edits` で即時反映される (マスタ型の admin/一般振り分けは不要 = [EditApi.submit] を直接叩く)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VideoEditSheet(
    songId: String,
    existing: SongVideo? = null,
    onDismiss: () -> Unit,
    onSaved: (SongVideo) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var youtubeUrl by remember { mutableStateOf(existing?.youtubeUrl ?: "") }
    var videoTitle by remember { mutableStateOf(existing?.videoTitle ?: "") }
    var note by remember { mutableStateOf(existing?.note ?: "") }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val trimmedUrl = youtubeUrl.trim()
    val trimmedTitle = videoTitle.trim()
    val trimmedNote = note.trim()
    // iOS VideoEditView.isValid と同条件。
    // 受け付ける URL の形 (http(s) + YouTube のホスト) はコアが決める。
    val urlOk = youtubeIsUploadUrl(trimmedUrl)
    val isValid = urlOk && trimmedTitle.length <= MAX_VIDEO_TITLE && trimmedNote.length <= MAX_VIDEO_NOTE

    fun save() {
        errorMessage = null
        isSaving = true
        scope.launch {
            val module = AppModule.from(context)
            val op = EditApi.EditOperation(
                op = if (existing == null) EditApi.EditOp.CREATE else EditApi.EditOp.UPDATE,
                recordType = "SongVideo",
                recordName = existing?.id,
                fields = mapOf(
                    "songId" to songId,
                    "youtubeUrl" to trimmedUrl,
                    "videoTitle" to trimmedTitle.ifEmpty { null },
                    "note" to trimmedNote.ifEmpty { null }
                )
            )
            try {
                val resp = module.editApi.submit(
                    listOf(op),
                    summary = if (existing == null) "参考動画を追加" else "参考動画を編集"
                )
                // create はサーバ採番 (ytref_<uuid>)。確定 recordName でローカルへ入れる。
                val resolvedId = resp.primaryRecordName(existing?.id)
                    ?: "ytref_${UUID.randomUUID()}"
                val saved = SongVideo(
                    id = resolvedId,
                    songId = songId,
                    youtubeUrl = trimmedUrl,
                    videoTitle = trimmedTitle.ifEmpty { null },
                    note = trimmedNote.ifEmpty { null },
                    createdAt = existing?.createdAt ?: Instant.now().toString(),
                    authorDisplayName = existing?.authorDisplayName
                        ?: module.authService.state.value.displayName
                )
                module.masterEditRepository.applySongVideo(saved)
                isSaving = false
                onSaved(saved)
                onDismiss()
            } catch (e: EditApi.ApiException) {
                isSaving = false
                errorMessage = e.friendlyMessage()
            } catch (e: Exception) {
                isSaving = false
                errorMessage = "保存に失敗しました: ${e.message}"
            }
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Box(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.fillMaxWidth()) {
                ImasSheetToolbar(
                    kind = ImasSheetToolbarKind.Edit(canSave = isValid && !isSaving, onCancel = onDismiss, onSave = ::save),
                    title = if (existing == null) "参考動画を投稿" else "参考動画を編集"
                )
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = DS.Space.screen)
                        .padding(bottom = DS.Space.section),
                    verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
                ) {
                    ImasFormCard {
                        ImasFormTextField(
                            label = "YouTube URL",
                            text = youtubeUrl,
                            onTextChange = { youtubeUrl = it },
                            error = if (trimmedUrl.isNotEmpty() && !urlOk) {
                                "YouTube の watch / youtu.be / shorts / embed URL に対応。"
                            } else {
                                null
                            }
                        )
                    }
                    if (trimmedUrl.isEmpty() || urlOk) {
                        ImasNote("YouTube の watch / youtu.be / shorts / embed URL に対応。")
                    }

                    ImasFormCard {
                        ImasFormTextField(
                            label = "動画タイトル (任意)",
                            text = videoTitle,
                            onTextChange = { videoTitle = it }
                        )
                        ImasFormTextArea(
                            label = "メモ (任意)",
                            text = note,
                            onTextChange = { note = it },
                            prompt = "どの公演の映像かなどの補足",
                            imprint = null
                        )
                    }
                    ImasText(
                        "どの公演の映像かなどの補足。メモ ${trimmedNote.length}/$MAX_VIDEO_NOTE 文字",
                        ImasTextRole.NOTE,
                        color = if (trimmedNote.length <= MAX_VIDEO_NOTE) ImasTextRole.NOTE.color else DS.danger
                    )

                    if (errorMessage != null) {
                        ImasText(errorMessage!!, ImasTextRole.META, color = DS.danger)
                    }
                }
            }
            ImasSavingOverlay(isSaving)
        }
    }
}
