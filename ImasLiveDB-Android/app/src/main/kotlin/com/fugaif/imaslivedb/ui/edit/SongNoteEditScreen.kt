package com.fugaif.imaslivedb.ui.edit

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.launch

/** サーバの上限 (`master_validators.ts` の Song.note) と揃える。 */
private const val NOTE_MAX_LENGTH = 200

/**
 * 曲の補足 (`songs.note`) だけを書く・直す画面。iOS `SongNoteEditSheet` の移植。
 *
 * 補足は利用者からの投稿が主な入口なので、Apple Music ID まで並ぶ [SongEditScreen] を
 * 開かせず、1 文と出典だけで出せるようにする。送り先は楽曲編集と同じオープン編集
 * ([submitMasterEdit]) で、直接反映できない人の投稿は修正リクエストになる。
 * 出典はマスタに列を持たないので、確認する運営に見えるよう編集の summary に載せる。
 */
@Composable
fun SongNoteEditScreen(
    song: Song,
    onDismiss: () -> Unit,
    onSaved: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var note by rememberSaveable(song.id) { mutableStateOf(song.note ?: "") }
    var source by rememberSaveable(song.id) { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var requestedIssueUrl by remember { mutableStateOf<String?>(null) }
    var requestSent by remember { mutableStateOf(false) }

    val trimmedNote = note.trim()
    val isTooLong = trimmedNote.length > NOTE_MAX_LENGTH
    val isUnchanged = trimmedNote == (song.note ?: "")

    fun submit() {
        val newNote = trimmedNote.ifEmpty { null }
        val trimmedSource = source.trim()
        // 空にしたら null を送って消す (楽曲編集の putClearable と同じ意味)。
        val ops = listOf(
            EditApi.EditOperation(
                op = EditApi.EditOp.UPDATE,
                recordType = "Song",
                recordName = song.id,
                fields = mapOf("note" to newNote)
            )
        )
        isSaving = true
        scope.launch {
            val result = submitMasterEdit(
                context = context,
                ops = ops,
                summary = if (trimmedSource.isEmpty()) "補足を編集" else "補足を編集 (出典: $trimmedSource)",
                fallbackRecordName = song.id
            ) { resolvedId ->
                AppModule.from(context).masterEditRepository.applySong(
                    song.copy(id = resolvedId, note = newNote),
                    newArtists = emptyList()
                )
            }
            isSaving = false
            when (result) {
                is MasterEditSubmitResult.Applied -> onSaved()
                is MasterEditSubmitResult.Requested -> {
                    requestedIssueUrl = result.issueUrl
                    requestSent = true
                }
                is MasterEditSubmitResult.Failed -> errorMessage = result.message
            }
        }
    }

    MasterEditScaffold(
        title = if (song.note == null) "補足を書く" else "補足を直す",
        canSave = !isUnchanged && !isTooLong,
        isSaving = isSaving,
        onCancel = onDismiss,
        onSave = ::submit
    ) {
        EditSection("補足", footer = "由来や位置づけを 1 文で。曲詳細の曲名の下に表示されます。") {
            EditTextField(
                "例: ミリシタ 1 周年記念楽曲", note, { note = it },
                singleLine = false, minLines = 2,
                isError = isTooLong,
                supportingText = "${trimmedNote.length}/$NOTE_MAX_LENGTH"
            )
        }
        EditSection(
            "出典",
            footer = "公式の告知や CD のクレジットなど、確かめられるものを書いてください。確認の目安にします。"
        ) {
            EditTextField("公式サイトの URL など", source, { source = it }, singleLine = false)
        }
    }

    errorMessage?.let { EditErrorDialog(it) { errorMessage = null } }

    if (requestSent) {
        EditRequestSentDialog(requestedIssueUrl) { requestSent = false; onDismiss() }
    }
}
