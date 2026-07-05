package com.fugaif.imaslivedb.ui.songs

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
import com.fugaif.imaslivedb.data.model.SongCall
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID

private const val MAX_CALL_TEXT = 5000

/**
 * コーレス (SongCall) 投稿・編集フォーム。iOS CallEditView の移植。
 * SongCall はコミュニティ型レコードなので、一般ユーザーも POST /edits で即時反映される
 * (マスタ型と異なり submitMaster の admin/一般振り分けは不要。iOS と同じく submit() を直接叩く)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CallEditSheet(
    songId: String,
    existing: SongCall? = null,
    onDismiss: () -> Unit,
    onSaved: (SongCall) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var callText by remember { mutableStateOf(existing?.callText ?: "") }
    var sourceUrl by remember { mutableStateOf(existing?.sourceUrl ?: "") }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val trimmedText = callText.trim()
    val trimmedUrl = sourceUrl.trim()
    val isValid = trimmedText.isNotEmpty() && trimmedText.length <= MAX_CALL_TEXT && isValidHttpUrlOrEmpty(trimmedUrl)

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(if (existing == null) "コーレスを投稿" else "コーレスを編集", fontSize = 20.sp, color = DS.ink)

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedTextField(
                    value = callText,
                    onValueChange = { callText = it },
                    label = { Text("コール本文") },
                    minLines = 4,
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    "コールやMIX、ペンライトの振り方など。${trimmedText.length}/$MAX_CALL_TEXT 文字",
                    fontSize = 12.sp,
                    color = if (trimmedText.length <= MAX_CALL_TEXT) DS.ink2 else DS.danger
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedTextField(
                    value = sourceUrl,
                    onValueChange = { sourceUrl = it },
                    label = { Text("出典URL(任意)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    isError = trimmedUrl.isNotEmpty() && !isValidHttpUrlOrEmpty(trimmedUrl)
                )
                Text("コール表などの参考ページがあれば。http(s)のみ。", fontSize = 12.sp, color = DS.ink2)
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
                            val editApi = AppModule.from(context).editApi
                            val op = EditApi.EditOperation(
                                op = if (existing == null) EditApi.EditOp.CREATE else EditApi.EditOp.UPDATE,
                                recordType = "SongCall",
                                recordName = existing?.id,
                                fields = mapOf(
                                    "songId" to songId,
                                    "callText" to trimmedText,
                                    "sourceUrl" to trimmedUrl.ifEmpty { null }
                                )
                            )
                            try {
                                val resp = editApi.submit(
                                    listOf(op),
                                    summary = if (existing == null) "コーレスを追加" else "コーレスを編集"
                                )
                                val resolvedId = resp.results.firstOrNull()?.recordName
                                    ?: existing?.id
                                    ?: "call_${UUID.randomUUID()}"
                                val saved = SongCall(
                                    id = resolvedId,
                                    songId = songId,
                                    callText = trimmedText,
                                    sourceUrl = trimmedUrl.ifEmpty { null },
                                    createdAt = existing?.createdAt ?: Instant.now().toString(),
                                    authorDisplayName = existing?.authorDisplayName
                                )
                                AppModule.from(context).database.communityDao().upsertCalls(listOf(saved))
                                isSaving = false
                                onSaved(saved)
                                onDismiss()
                            } catch (e: EditApi.ApiException) {
                                isSaving = false
                                errorMessage = friendlyEditError(e)
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

private fun isValidHttpUrlOrEmpty(url: String): Boolean {
    if (url.isEmpty()) return true
    return try {
        val uri = android.net.Uri.parse(url)
        (uri.scheme == "http" || uri.scheme == "https") && !uri.host.isNullOrEmpty()
    } catch (e: Exception) {
        false
    }
}

private fun friendlyEditError(e: EditApi.ApiException): String = when (e) {
    is EditApi.ApiException.NotAuthorized -> "認証の有効期限が切れています。再度サインインしてください。"
    is EditApi.ApiException.Banned -> "この操作は制限されています。"
    is EditApi.ApiException.RateLimited -> "投稿が多すぎます。しばらく待ってからお試しください。"
    is EditApi.ApiException.Server -> "保存に失敗しました (${e.status})"
    is EditApi.ApiException.Transport -> "通信に失敗しました: ${e.message}"
}
