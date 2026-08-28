package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * この公演のセトリの変更履歴。iOS の `EditHistoryView(recordType: "ShowSetlist", …)` にあたる。
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

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            Text("セトリの編集履歴", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            Text(
                showName, fontSize = 12.sp, color = DS.ink2,
                maxLines = 2, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(bottom = 8.dp)
            )
            val entries = history
            when {
                error != null -> Text(error.orEmpty(), fontSize = 13.sp, color = DS.danger)
                entries == null -> Box(
                    Modifier.fillMaxWidth().padding(24.dp),
                    contentAlignment = Alignment.Center
                ) { CircularProgressIndicator() }
                entries.isEmpty() -> Text(
                    "まだ編集されていません", fontSize = 13.sp, color = DS.ink2,
                    modifier = Modifier.padding(16.dp)
                )
                else -> entries.forEach { h ->
                    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            val (label, color) = opDesign(h.op)
                            Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = color)
                            Text(relativeTime(h.createdAt), fontSize = 11.sp, color = DS.ink3)
                            if (h.reverted) Text("(差戻し済み)", fontSize = 11.sp, color = DS.ink3)
                        }
                        if (h.changedFields.isNotEmpty()) {
                            Text(h.changedFields.joinToString(", "), fontSize = 12.sp, color = DS.ink2)
                        }
                        h.editorName?.let { Text(it, fontSize = 11.sp, color = DS.ink3) }
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

/**
 * 操作種別のラベルと色。「最近の編集」画面の同名の表と同じ対応にしてある
 * (向こうは private なので参照できない — 表を足すときは両方直すこと)。
 */
private fun opDesign(op: String): Pair<String, Color> = when (op) {
    "create" -> "追加" to DS.success
    "update", "replace" -> "更新" to Color(0xFF4A90D9)
    "delete" -> "削除" to DS.danger
    "revert" -> "差戻し" to DS.warning
    "snapshot" -> "セトリ更新" to Color(0xFF2FB8A8)
    else -> op to DS.ink3
}

/** 「3日前」形式の相対時刻。1 か月以上前は日付そのもの。 */
private fun relativeTime(epochMs: Long): String {
    val diffSec = (System.currentTimeMillis() - epochMs) / 1000
    return when {
        diffSec < 60 -> "今"
        diffSec < 3600 -> "${diffSec / 60}分前"
        diffSec < 86_400 -> "${diffSec / 3600}時間前"
        diffSec < 86_400 * 30 -> "${diffSec / 86_400}日前"
        else -> SimpleDateFormat("yyyy/MM/dd", Locale.JAPAN).format(Date(epochMs))
    }
}
