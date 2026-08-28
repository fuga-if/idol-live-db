package com.fugaif.imaslivedb.ui.edit

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.edit.friendlyMessage
import com.fugaif.imaslivedb.data.model.SongVideo
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID

private const val MAX_VIDEO_TITLE = 300
private const val MAX_VIDEO_NOTE = 1000

/**
 * 参考動画 (SongVideo) の投稿・編集フォーム。iOS `VideoEditView` の移植。
 *
 * SongVideo はコーレスと同じコミュニティ型レコードなので、一般ユーザーでも
 * `POST /edits` で即時反映される (マスタ型の admin/一般振り分けは不要 = [EditApi.submit] を直接叩く)。
 * 見た目・状態の持ち方は同型の [com.fugaif.imaslivedb.ui.songs.CallEditSheet] に揃えてある。
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
    val urlOk = isYouTubeUrl(trimmedUrl)
    val isValid = urlOk && trimmedTitle.length <= MAX_VIDEO_TITLE && trimmedNote.length <= MAX_VIDEO_NOTE

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(if (existing == null) "参考動画を投稿" else "参考動画を編集", fontSize = 20.sp, color = DS.ink)

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedTextField(
                    value = youtubeUrl,
                    onValueChange = { youtubeUrl = it },
                    label = { Text("YouTube URL") },
                    singleLine = true,
                    isError = trimmedUrl.isNotEmpty() && !urlOk,
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    "YouTube の watch / youtu.be / shorts / embed URL に対応。",
                    fontSize = 12.sp,
                    color = if (trimmedUrl.isEmpty() || urlOk) DS.ink2 else DS.danger
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedTextField(
                    value = videoTitle,
                    onValueChange = { videoTitle = it },
                    label = { Text("動画タイトル (任意)") },
                    singleLine = true,
                    isError = trimmedTitle.length > MAX_VIDEO_TITLE,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("メモ (任意)") },
                    minLines = 2,
                    isError = trimmedNote.length > MAX_VIDEO_NOTE,
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    "どの公演の映像かなどの補足。メモ ${trimmedNote.length}/$MAX_VIDEO_NOTE 文字",
                    fontSize = 12.sp,
                    color = if (trimmedNote.length <= MAX_VIDEO_NOTE) DS.ink2 else DS.danger
                )
            }

            if (errorMessage != null) {
                Text(errorMessage!!, color = DS.danger, fontSize = 13.sp)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("キャンセル") }
                Button(
                    onClick = {
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
                                module.database.syncDao().upsertSongVideos(listOf(saved))
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
                    },
                    enabled = isValid && !isSaving,
                    modifier = Modifier.weight(1f)
                ) {
                    if (isSaving) {
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), color = DS.ink)
                    } else {
                        Text("保存")
                    }
                }
            }
        }
    }
}

/**
 * YouTube URL の簡易判定。iOS `VideoEditView.isYouTubeURL` と同条件で、
 * http(s) + ホストが YouTube 系かどうかだけを見る (パス形式はサーバ validator が見る)。
 */
internal fun isYouTubeUrl(s: String): Boolean {
    if (s.isEmpty()) return false
    val uri = runCatching { android.net.Uri.parse(s) }.getOrNull() ?: return false
    val scheme = uri.scheme?.lowercase()
    if (scheme != "http" && scheme != "https") return false
    val host = uri.host?.lowercase()?.takeIf { it.isNotEmpty() } ?: return false
    return host == "youtu.be" ||
        host == "youtube.com" || host == "www.youtube.com" ||
        host == "m.youtube.com" || host == "music.youtube.com"
}
