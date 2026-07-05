package com.fugaif.imaslivedb.ui.edit

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.QueueMusic
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.model.ShowWithEventName
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 「最近の編集」= コミュニティのオープン編集機能。iOS `RecentEditsView` の移植。
 * `GET /edits` フィードの閲覧 + Good トグルに加え、FAB からセトリ編集を新規提案できる。
 *
 * 契約 (imas-live-api を実ソースで確認済み): マスタ (Song/Show/Idol/Event/Setlist系) の直接反映は
 * admin 限定。一般ユーザーがここから編集すると `POST /edit-requests` で GitHub issue 化され、
 * このフィードには載らない (CloudKit 未反映のため)。フィードに載るのは admin の直接編集と
 * コミュニティ投稿 (コーレス/参考動画。別画面) のみ。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecentEditsScreen(onBack: () -> Unit, viewModel: RecentEditsViewModel = viewModel()) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val authService = remember { AppModule.from(context).authService }
    val authState by authService.state.collectAsState()
    val scope = rememberCoroutineScope()
    fun signIn() { scope.launch { authService.signIn(context) } }

    var tab by remember { mutableStateOf(0) }
    var showProposeSheet by remember { mutableStateOf(false) }
    var showShowPicker by remember { mutableStateOf(false) }
    var editingShow by remember { mutableStateOf<ShowWithEventName?>(null) }
    var historyEntry by remember { mutableStateOf<EditApi.EditFeedEntry?>(null) }

    LaunchedEffect(tab) { viewModel.setMineOnly(tab == 1) }

    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    title = { Text(if (tab == 1) "自分の編集" else "最近の編集", fontWeight = FontWeight.Bold) },
                    navigationIcon = {
                        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                    }
                )
                ImasSegmented(
                    labels = listOf("みんなの編集", "自分の編集"),
                    selection = tab,
                    onSelect = { tab = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)
                )
            }
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(onClick = {
                if (!authState.isSignedIn) {
                    viewModel.requestLogin()
                } else {
                    showProposeSheet = true
                }
            }) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Text("編集を提案", modifier = Modifier.padding(start = 6.dp))
            }
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            if (tab == 1 && !authState.isSignedIn) {
                Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Spacer(Modifier.height(40.dp))
                    ImasEmptyState(Icons.Filled.Person, "ログインが必要です", "自分の編集履歴を見るにはログインしてください。")
                    Button(onClick = ::signIn, modifier = Modifier.fillMaxWidth()) { Text("Googleでログイン") }
                }
            } else if (state.isLoading && state.entries.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            } else if (state.entries.isEmpty()) {
                Column(Modifier.fillMaxSize()) {
                    ImasEmptyState(
                        icon = Icons.Filled.EditNote,
                        title = "まだ編集がありません",
                        message = if (tab == 1) "ライブ・楽曲・セトリを編集すると、ここに履歴が残ります。"
                        else "誰かがデータを編集すると、ここに新着順で表示されます。"
                    )
                }
            } else {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    itemsIndexed(state.entries, key = { _, entry -> entry.batchId }) { index, entry ->
                        val (gooded, goodCount) = viewModel.goodState(entry)
                        EditFeedCard(
                            entry = entry,
                            gooded = gooded,
                            goodCount = goodCount,
                            recordTitle = state.recordTitles[entry.batchId],
                            onToggleGood = { viewModel.toggleGood(entry) },
                            onOpenHistory = { historyEntry = entry }
                        )
                        if (index >= state.entries.size - 3) {
                            LaunchedEffect(entry.batchId) { viewModel.loadMore() }
                        }
                    }
                    if (state.isLoadingMore) {
                        item {
                            Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator()
                            }
                        }
                    }
                }
            }
        }
    }

    if (state.errorMessage != null) {
        AlertDialog(
            onDismissRequest = { viewModel.clearError() },
            confirmButton = { TextButton(onClick = { viewModel.clearError() }) { Text("OK") } },
            title = { Text("エラー") },
            text = { Text(state.errorMessage ?: "") }
        )
    }

    if (state.showLoginPrompt) {
        AlertDialog(
            onDismissRequest = { viewModel.dismissLoginPrompt() },
            title = { Text("ログインが必要です") },
            text = { Text("編集の提案や Good にはログインが必要です。") },
            confirmButton = {
                TextButton(onClick = { viewModel.dismissLoginPrompt(); signIn() }) { Text("Googleでログイン") }
            },
            dismissButton = { TextButton(onClick = { viewModel.dismissLoginPrompt() }) { Text("キャンセル") } }
        )
    }

    if (showProposeSheet) {
        ProposeEditTypeSheet(
            onDismiss = { showProposeSheet = false },
            onPickSetlist = { showProposeSheet = false; showShowPicker = true }
        )
    }

    if (showShowPicker) {
        ShowSearchPickerSheet(
            onDismiss = { showShowPicker = false },
            onSelect = { show -> showShowPicker = false; editingShow = show }
        )
    }

    val currentEditingShow = editingShow
    if (currentEditingShow != null) {
        Dialog(
            onDismissRequest = { editingShow = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            SetlistEditScreen(
                show = currentEditingShow.toShow(),
                eventName = currentEditingShow.eventName,
                onDismiss = { editingShow = null },
                onSaved = {
                    editingShow = null
                    viewModel.refresh()
                }
            )
        }
    }

    val currentHistoryEntry = historyEntry
    if (currentHistoryEntry != null) {
        RecordHistorySheet(entry = currentHistoryEntry, onDismiss = { historyEntry = null })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProposeEditTypeSheet(onDismiss: () -> Unit, onPickSetlist: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
            Text(
                "編集の種類を選択", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)
            )
            Row(
                modifier = Modifier.fillMaxWidth()
                    .clickable(onClick = onPickSetlist)
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(
                    modifier = Modifier.height(40.dp).background(DS.fill, CircleShape).padding(horizontal = 10.dp),
                    contentAlignment = Alignment.Center
                ) { Icon(Icons.Filled.QueueMusic, contentDescription = null, tint = DS.ink2) }
                Column {
                    Text("セトリを編集", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
                    Text("公演の楽曲・出演者の追加/修正/削除", fontSize = 12.sp, color = DS.ink2)
                }
            }
            Text(
                "他の編集タイプ (曲情報・アイドル情報・イベント/公演情報) は今後追加予定です。",
                fontSize = 11.sp, color = DS.ink3,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RecordHistorySheet(entry: EditApi.EditFeedEntry, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    var history by remember { mutableStateOf<List<EditApi.RecordHistoryEntry>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(entry.recordType, entry.recordName) {
        val editApi = AppModule.from(context).editApi
        try {
            history = editApi.recordHistory(entry.recordType, entry.recordName)
        } catch (e: Exception) {
            error = "変更履歴の取得に失敗しました"
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            Text("変更履歴", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            Text(
                EditFeedFormat.recordTypeLabel(entry.recordType),
                fontSize = 12.sp, color = DS.ink2, modifier = Modifier.padding(bottom = 8.dp)
            )
            when {
                error != null -> Text(error ?: "", color = DS.danger, fontSize = 13.sp)
                history == null -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                history!!.isEmpty() -> Text("履歴がありません", fontSize = 13.sp, color = DS.ink2, modifier = Modifier.padding(16.dp))
                else -> {
                    history!!.forEach { h ->
                        Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                val (label, color) = EditFeedFormat.opDesign(h.op)
                                Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = color)
                                Text(EditFeedFormat.relativeTime(h.createdAt), fontSize = 11.sp, color = DS.ink3)
                                if (h.reverted) Text("(差戻し済み)", fontSize = 11.sp, color = DS.ink3)
                            }
                            if (h.changedFields.isNotEmpty()) {
                                Text(h.changedFields.joinToString(", "), fontSize = 12.sp, color = DS.ink2)
                            }
                            h.editorName?.let { Text(it, fontSize = 11.sp, color = DS.ink3) }
                        }
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun EditFeedCard(
    entry: EditApi.EditFeedEntry,
    gooded: Boolean,
    goodCount: Int,
    recordTitle: String?,
    onToggleGood: () -> Unit,
    onOpenHistory: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 5.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(DS.surface)
            .clickable(onClick = onOpenHistory)
            .padding(14.dp)
    ) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            val design = EditFeedFormat.recordTypeDesign(entry.recordType)
            Box(
                modifier = Modifier.size(40.dp).clip(CircleShape).background(design.second.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center
            ) { Icon(design.first, contentDescription = null, tint = design.second) }

            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(entry.editorDisplayLabel, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    OpBadge(entry.op)
                    Spacer(Modifier.weight(1f))
                    Text(EditFeedFormat.relativeTime(entry.createdAt), fontSize = 11.sp, color = DS.ink2)
                }
                Text(
                    recordTitle ?: EditFeedFormat.recordTypeLabel(entry.recordType),
                    fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                    modifier = Modifier.padding(top = 4.dp)
                )
                if (!entry.summary.isNullOrEmpty()) {
                    Text(entry.summary, fontSize = 12.sp, color = DS.ink2, modifier = Modifier.padding(top = 2.dp))
                }
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (entry.isOwnEdit) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Person, contentDescription = null, tint = DS.ink2, modifier = Modifier.size(14.dp))
                    Text("あなたの編集", fontSize = 12.sp, color = DS.ink2, modifier = Modifier.padding(start = 4.dp))
                }
            } else {
                Row(
                    modifier = Modifier.clip(RoundedCornerShape(50))
                        .background((if (gooded) DS.pick else DS.ink2).copy(alpha = 0.12f))
                        .clickable(onClick = onToggleGood)
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        if (gooded) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                        contentDescription = if (gooded) "Good を取り消す" else "Good を付ける",
                        tint = if (gooded) DS.pick else DS.ink2,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        if (goodCount > 0) "$goodCount" else "Good",
                        fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                        color = if (gooded) DS.pick else DS.ink2,
                        modifier = Modifier.padding(start = 5.dp)
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.History, contentDescription = null, tint = DS.ink3, modifier = Modifier.size(13.dp))
                Text("変更履歴", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2, modifier = Modifier.padding(start = 4.dp))
            }
        }
    }
}

@Composable
private fun OpBadge(op: String) {
    val (label, color) = EditFeedFormat.opDesign(op)
    Text(
        label, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = color,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(color.copy(alpha = 0.15f))
            .padding(horizontal = 7.dp, vertical = 2.dp)
    )
}

/** record_type / op の表示メタ + 相対時刻整形。iOS `EditFeedFormat` の移植。 */
private object EditFeedFormat {
    fun recordTypeDesign(type: String): Pair<androidx.compose.ui.graphics.vector.ImageVector, Color> = when (type) {
        "Event" -> Icons.Filled.Event to Color(0xFF9C6ADE)
        "Show" -> Icons.Filled.MusicNote to Color(0xFF6A7FDE)
        "Song" -> Icons.Filled.MusicNote to DS.pick
        "Idol" -> Icons.Filled.Person to Color(0xFF4A90D9)
        "SetlistItem", "ShowSetlist" -> Icons.Filled.QueueMusic to Color(0xFF2FB8A8)
        "SetlistPerformer" -> Icons.AutoMirrored.Filled.List to Color(0xFF2FB8A8)
        "SongArtist" -> Icons.Filled.MusicNote to DS.success
        "ShowCast" -> Icons.Filled.Person to DS.warning
        else -> Icons.Filled.EditNote to DS.ink3
    }

    fun recordTypeLabel(type: String): String = when (type) {
        "Event" -> "ライブ・イベント"
        "Show" -> "公演"
        "Song" -> "楽曲"
        "Idol" -> "アイドル"
        "SetlistItem", "ShowSetlist" -> "セットリスト"
        "SetlistPerformer" -> "セトリ出演者"
        "SongArtist" -> "楽曲アーティスト"
        "ShowCast" -> "出演キャスト"
        else -> type
    }

    fun opDesign(op: String): Pair<String, Color> = when (op) {
        "create" -> "追加" to DS.success
        "update", "replace" -> "更新" to Color(0xFF4A90D9)
        "delete" -> "削除" to DS.danger
        "revert" -> "差戻し" to DS.warning
        "snapshot" -> "セトリ更新" to Color(0xFF2FB8A8)
        else -> op to DS.ink3
    }

    fun relativeTime(epochMs: Long): String {
        val now = System.currentTimeMillis()
        val diffSec = (now - epochMs) / 1000
        return when {
            diffSec < 60 -> "今"
            diffSec < 3600 -> "${diffSec / 60}分前"
            diffSec < 86_400 -> "${diffSec / 3600}時間前"
            diffSec < 86_400 * 30 -> "${diffSec / 86_400}日前"
            else -> SimpleDateFormat("yyyy/MM/dd", Locale.JAPAN).format(Date(epochMs))
        }
    }
}
