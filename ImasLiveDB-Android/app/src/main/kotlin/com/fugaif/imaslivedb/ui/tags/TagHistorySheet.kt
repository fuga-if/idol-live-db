package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasContentState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyStateKind
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasRecordRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasStateContainer
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** タグの説明文編集履歴。iOS TagHistoryView の移植。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagHistorySheet(tagId: String, domain: TagDomain = TagDomain.SONG, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var isLoading by remember { mutableStateOf(true) }
    var history by remember { mutableStateOf<List<CommunityApi.TagHistoryEntry>>(emptyList()) }

    LaunchedEffect(tagId) {
        val api = AppModule.from(context).communityApi
        history = runCatching {
            when (domain) {
                TagDomain.SONG -> api.tagHistory(tagId)
                TagDomain.IDOL -> api.idolTagOptionHistory(tagId)
                TagDomain.UNIT -> api.unitTagOptionHistory(tagId)
            }
        }.getOrDefault(emptyList())
        isLoading = false
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth().heightIn(min = 200.dp)) {
            ImasSheetToolbar(kind = ImasSheetToolbarKind.Read(onClose = onDismiss), title = "編集履歴")
            val state = when {
                isLoading -> ImasContentState.Loading
                history.isEmpty() -> ImasContentState.Empty
                else -> ImasContentState.Loaded
            }
            ImasStateContainer(
                state = state,
                empty = { ImasEmptyState(ImasEmptyStateKind.EMPTY, title = "編集履歴はありません") }
            ) {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    ImasListSection {
                        history.forEach { entry -> HistoryRow(entry) }
                    }
                }
            }
        }
    }
}

/** 前と同じ絶対日時 (yyyy/MM/dd HH:mm)。相対時刻にしない (編集履歴は「いつ」を正確に見る画面)。 */
private fun formatEditedAt(epochSeconds: Long): String {
    if (epochSeconds <= 0) return ""
    val fmt = SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.getDefault())
    return fmt.format(Date(epochSeconds * 1000))
}

@Composable
private fun HistoryRow(entry: CommunityApi.TagHistoryEntry) {
    ImasRecordRow(
        title = formatEditedAt(entry.editedAt),
        trailing = ImasRowTrailing.Value("${entry.editedBy.take(8)}...")
    ) {
        val desc = entry.descriptionAfter
        // 説明は行数の制限なしで全文 (最大 300 字)。題 (2 行までの ImasRecordRow の既定) に乗せると切れるため detail に出す。
        if (!desc.isNullOrEmpty()) {
            Text(desc, style = ImasTextRole.BODY.style, color = DS.ink)
        } else {
            Text("(説明なし)", style = ImasTextRole.BODY.style, color = DS.ink3)
        }
    }
}
