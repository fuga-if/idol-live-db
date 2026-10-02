package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeSpec
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasRecordRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import uniffi.imas_core.relativeTimes

/**
 * この公演のセトリの変更履歴。iOS の `EditHistoryView(recordType: "ShowSetlist", …)` にあたる。
 * 見た目は DesignSystem の `ImasRecordRow` (iOS の簡易版と同じ構成: 題=操作の種類・
 * 副題=編集者・末尾=相対時刻・札=差戻し済みの印・下段=変更された項目名)。
 *
 * セトリ編集は 1 曲ずつではなく **公演単位のスナップショット** (`ShowSetlist`) として
 * 履歴化されるので、record_name は showId。曲行 (`SetlistItem`) を引くと編集 1 回が
 * 曲数ぶんの行に散ってしまい、「いつ誰がこの公演のセトリを直したか」が読めなくなる。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SetlistEditHistorySheet(showId: String, showName: String, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    var history by remember { mutableStateOf<List<EditApi.RecordHistoryEntry>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(showId) {
        try {
            history = AppModule.from(context).editApi.recordHistory("ShowSetlist", showId)
        } catch (e: Exception) {
            error = "変更履歴の取得に失敗しました"
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = DS.bg) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
            verticalArrangement = Arrangement.spacedBy(DS.Space.gap)
        ) {
            Text(
                "セトリの編集履歴",
                style = ImasType.heading(17.sp, FontWeight.Bold),
                color = DS.ink
            )
            ImasText(
                showName,
                role = ImasTextRole.NOTE,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            val entries = history
            when {
                error != null -> ImasNotice(kind = ImasNoticeKind.ERROR, message = error)
                entries == null -> ImasInlineLoading()
                entries.isEmpty() -> ImasEmptyState(
                    icon = Icons.Filled.History,
                    title = "まだ編集されていません"
                )
                else -> {
                    // 相対時刻の言い回しはコア。一覧ぶんを 1 回で引く。
                    val times = remember(entries) { relativeTimes(entries.map { it.createdAt }, System.currentTimeMillis()) }
                    entries.forEachIndexed { i, h ->
                        HistoryRow(h, times[i])
                    }
                }
            }
        }
    }
}

@Composable
private fun HistoryRow(h: EditApi.RecordHistoryEntry, time: String) {
    val badges = buildList {
        add(ImasBadgeSpec(opLabel(h.op), kind = if (h.op == "revert") ImasBadgeKind.NEGATIVE else ImasBadgeKind.NEUTRAL))
        if (h.reverted) add(ImasBadgeSpec("差戻し済み", kind = ImasBadgeKind.NEGATIVE))
    }
    ImasCard {
        ImasRecordRow(
            title = opLabel(h.op),
            subtitle = h.editorName,
            badges = badges,
            trailing = ImasRowTrailing.Value(time)
        ) {
            if (h.changedFields.isNotEmpty()) {
                ImasText(h.changedFields.joinToString(", "), role = ImasTextRole.META)
            }
        }
    }
}

/**
 * 操作種別のラベル。「最近の編集」画面の同名の表と同じ対応にしてある
 * (向こうは private なので参照できない — 表を足すときは両方直すこと)。
 * 色は操作ごとに変えない (§10.1)。差し戻しだけ `ImasBadgeKind.NEGATIVE` に当てる (iOS `EditFeedFormat.opBadgeKind` と同じ)。
 */
private fun opLabel(op: String): String = when (op) {
    "create" -> "追加"
    "update", "replace" -> "更新"
    "delete" -> "削除"
    "revert" -> "差戻し"
    "snapshot" -> "セトリ更新"
    else -> op
}
