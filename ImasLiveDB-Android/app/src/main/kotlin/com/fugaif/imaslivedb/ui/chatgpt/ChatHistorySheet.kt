package com.fugaif.imaslivedb.ui.chatgpt

import androidx.compose.foundation.layout.Column
import androidx.compose.ui.Modifier
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.chatgpt.ChatSessionStore
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRowKind
import com.fugaif.imaslivedb.ui.designsystem.ImasConfirmDestructive
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipe
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeAction
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeKind
import com.fugaif.imaslivedb.ui.theme.DS
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.ChatSessionSummary

/**
 * これまでの会話の一覧。開く・消す。iOS `ChatHistorySheet`。
 *
 * 会話は端末の中にだけある ([ChatSessionStore])。並びと残す本数はコアが決める。
 *
 * @param currentId いま開いている会話 (印を付ける)。
 * @param onOpen 会話を開く (シートはこの中で閉じる)。
 * @param onDelete 消した会話の id (いま開いている会話を消したら、画面の側で新しい会話にする)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatHistorySheet(
    currentId: String,
    onDismiss: () -> Unit,
    onOpen: (String) -> Unit,
    onDelete: (String) -> Unit,
) {
    val context = LocalContext.current
    var sessions by remember { mutableStateOf<List<ChatSessionSummary>?>(null) }
    var confirmsDeleteAll by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { sessions = withContext(Dispatchers.IO) { ChatSessionStore.list(context) } }
    val list = sessions

    suspend fun deleteFiles(block: () -> Unit) = withContext(Dispatchers.IO) { block() }

    val scope = rememberCoroutineScope()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg,
    ) {
        ImasFormBackdrop {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
                ImasSheetToolbar(ImasSheetToolbarKind.Read(onClose = onDismiss), title = "会話の履歴")
                when {
                    list == null -> Unit
                    list.isEmpty() -> ImasEmptyState(
                        icon = Icons.Filled.History,
                        title = "まだ会話がありません",
                        message = "送った会話は、この端末の中に残ります",
                    )
                    else -> {
                        ImasListSection(
                            "これまでの会話",
                            count = "${list.size}件",
                            footer = "会話はこの端末の中にだけ残ります (バックアップにも入れません)。添えた画像は残しません。行を左に引くと消せます。",
                        ) {
                            list.forEach { summary ->
                                ImasSwipe(
                                    trailing = listOf(
                                        ImasSwipeAction(kind = ImasSwipeKind.DELETE, title = "削除") {
                                            scope.launch {
                                                deleteFiles { ChatSessionStore.delete(context, summary.id) }
                                                sessions = sessions?.filter { it.id != summary.id }
                                                onDelete(summary.id)
                                            }
                                        },
                                    ),
                                    background = DS.surface,
                                ) {
                                    ImasNavRow(
                                        title = summary.title,
                                        subtitle = subtitle(summary),
                                        icon = if (summary.id == currentId) Icons.Filled.ChatBubble else Icons.Outlined.ChatBubbleOutline,
                                        iconTone = ImasIconTileTone.NEUTRAL,
                                        onClick = { onOpen(summary.id); onDismiss() },
                                    )
                                }
                            }
                        }
                        ImasListSection {
                            ImasActionRow(
                                title = "すべて消す",
                                icon = Icons.Filled.Delete,
                                kind = ImasActionRowKind.DESTRUCTIVE,
                                onClick = { confirmsDeleteAll = true },
                            )
                        }
                    }
                }
            }
        }
    }
    ImasConfirmDestructive(
        title = "これまでの会話をすべて消しますか？",
        isPresented = confirmsDeleteAll,
        onDismiss = { confirmsDeleteAll = false },
        actionTitle = "すべて消す",
        dismissTitle = "やめる",
        onConfirm = {
            val ids = sessions.orEmpty().map { it.id }
            scope.launch {
                deleteFiles { ChatSessionStore.deleteAll(context) }
                sessions = emptyList()
                ids.forEach(onDelete)
            }
        },
    )
}

private fun subtitle(summary: ChatSessionSummary): String {
    val date = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(summary.updatedAt * 1000))
    return "$date・${summary.turnCount} 往復"
}
