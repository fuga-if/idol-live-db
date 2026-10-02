package com.fugaif.imaslivedb.ui.edit

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.material.icons.filled.Undo
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.auth.shouldPromptLogin
import com.fugaif.imaslivedb.data.auth.showEditAffordance
import com.fugaif.imaslivedb.data.auth.startCommunityEdit
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.model.ShowWithEventName
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.CommunityLoginPromptDialog
import com.fugaif.imaslivedb.ui.designsystem.ImasBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeSpec
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasCardListStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasConfirmDestructive
import com.fugaif.imaslivedb.ui.designsystem.ImasContentState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyStateKind
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRecordRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowChevron
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasStateContainer
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import kotlinx.coroutines.launch
import uniffi.imas_core.relativeTimes

/**
 * 「最近の編集」= コミュニティのオープン編集機能。iOS `RecentEditsView` の移植。
 * `GET /edits` フィードの閲覧 + Good トグルに加え、FAB からセトリ編集を新規提案できる。
 *
 * 契約 (imas-live-api を実ソースで確認済み): マスタ (Song/Show/Idol/Event/Setlist系) の直接反映は
 * admin 限定。一般ユーザーがここから編集すると `POST /edit-requests` で GitHub issue 化され、
 * このフィードには載らない (CloudKit 未反映のため)。フィードに載るのは admin の直接編集と
 * コミュニティ投稿 (参考動画。別画面) のみ。
 *
 * 「取り消す」(revert) は iOS のオープン編集初期から残る Android 独自の導線 (自分の編集タブのみ)。
 * iOS 版 RecentEditsView には無いが、既存機能なのでそのまま残す。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecentEditsScreen(onBack: (() -> Unit)?, viewModel: RecentEditsViewModel = viewModel()) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val authService = remember { AppModule.from(context).authService }
    val authState by authService.state.collectAsState()
    // 権限フラグは認証状態が変わった時だけコアへ問い合わせる。extension property は 1 回ごとに
    // EditPermissionRules を RustBuffer へ詰め直して JNA を跨ぐので、FAB や本文の再コンポーズの
    // たびに呼ぶと積み上がる (詳細は data/auth/EditPermission.kt のヘッダ)。
    val canEditHere = remember(authState) { authState.showEditAffordance }
    val needsLogin = remember(authState) { authState.shouldPromptLogin }
    val scope = rememberCoroutineScope()
    fun signIn() { scope.launch { authService.signIn(context) } }

    var tab by remember { mutableStateOf(0) }
    var showProposeSheet by remember { mutableStateOf(false) }
    var showShowPicker by remember { mutableStateOf(false) }
    // 新規作成 (曲 / ライブ)。既存の修正は各詳細画面が入口なので、ここは create だけ持つ。
    var showSongCreate by remember { mutableStateOf(false) }
    var showEventCreate by remember { mutableStateOf(false) }
    var editingShow by remember { mutableStateOf<ShowWithEventName?>(null) }
    var historyEntry by remember { mutableStateOf<EditApi.EditFeedEntry?>(null) }
    var revertTarget by remember { mutableStateOf<EditApi.EditFeedEntry?>(null) }

    LaunchedEffect(tab) { viewModel.setMineOnly(tab == 1) }

    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    title = { Text(if (tab == 1) "自分の編集" else "最近の編集") },
                    navigationIcon = {
                        // サイドバーの根として開いたときは戻る先が無いので出さない。
                        onBack?.let { back ->
                            IconButton(onClick = back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                        }
                    }
                )
                ImasSegmented(
                    labels = listOf("みんなの編集", "自分の編集"),
                    selection = tab,
                    onSelect = { tab = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
                )
            }
        },
        floatingActionButton = {
            // BAN 済みには「編集を提案」自体を出さない (押しても 403 になるだけ)。判定はコア。
            if (canEditHere) {
                ExtendedFloatingActionButton(onClick = {
                    authState.startCommunityEdit(promptLogin = viewModel::requestLogin) {
                        showProposeSheet = true
                    }
                }) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                    Text("編集を提案", modifier = Modifier.padding(start = DS.Space.gapTight))
                }
            }
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            if (tab == 1 && needsLogin) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    ImasEmptyState(
                        icon = Icons.Filled.Person,
                        title = "ログインが必要です",
                        message = "自分の編集履歴を見るにはログインしてください。",
                        actionTitle = "Googleでログイン",
                        onAction = ::signIn
                    )
                }
            } else {
                val contentState = when {
                    state.isLoading && state.entries.isEmpty() -> ImasContentState.Loading
                    state.entries.isEmpty() -> ImasContentState.Empty
                    else -> ImasContentState.Loaded
                }
                ImasStateContainer(
                    state = contentState,
                    modifier = Modifier.fillMaxSize(),
                    empty = {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            ImasEmptyState(
                                icon = Icons.Filled.EditNote,
                                title = "まだ編集がありません",
                                message = if (tab == 1) "ライブ・楽曲・セトリを編集すると、ここに履歴が残ります。"
                                else "誰かがデータを編集すると、ここに新着順で表示されます。"
                            )
                        }
                    }
                ) {
                    // 相対時刻の言い回しはコア。一覧ぶんを 1 回で引く (行ごとに呼ばない)。
                    val times = remember(state.entries) {
                        relativeTimes(state.entries.map { it.createdAt }, System.currentTimeMillis())
                    }
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        itemsIndexed(state.entries, key = { _, entry -> entry.batchId }) { index, entry ->
                            val (gooded, goodCount) = viewModel.goodState(entry)
                            EditFeedCard(
                                timeText = times.getOrElse(index) { "" },
                                entry = entry,
                                gooded = gooded,
                                goodCount = goodCount,
                                recordTitle = state.recordTitles[entry.batchId],
                                showRevertAction = tab == 1,
                                isReverted = viewModel.isReverted(entry),
                                isReverting = state.revertingId == entry.batchId,
                                onToggleGood = { viewModel.toggleGood(entry) },
                                onOpenHistory = { historyEntry = entry },
                                onRevertRequest = { revertTarget = entry }
                            )
                            if (index >= state.entries.size - 3) {
                                LaunchedEffect(entry.batchId) { viewModel.loadMore() }
                            }
                        }
                        if (state.isLoadingMore) {
                            item { ImasInlineLoading() }
                        }
                    }
                }
            }
        }
    }

    ImasErrorAlert(message = state.errorMessage, onDismiss = { viewModel.clearError() }, title = "エラー")

    if (state.showLoginPrompt) {
        CommunityLoginPromptDialog(
            message = "編集の提案や Good にはログインが必要です。",
            onDismiss = { viewModel.dismissLoginPrompt() }
        )
    }

    if (showProposeSheet) {
        ProposeEditTypeSheet(
            onDismiss = { showProposeSheet = false },
            onPickSetlist = { showProposeSheet = false; showShowPicker = true },
            onPickNewSong = { showProposeSheet = false; showSongCreate = true },
            onPickNewEvent = { showProposeSheet = false; showEventCreate = true }
        )
    }

    // 編集フォームはフルスクリーン Dialog に載せる (セトリ編集と同じ出し方)。
    // 中身は必ず Scaffold なので、システムバーに保存ボタンが潜り込むことはない。
    if (showSongCreate) {
        Dialog(
            onDismissRequest = { showSongCreate = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            SongEditScreen(
                onDismiss = { showSongCreate = false },
                onSaved = { showSongCreate = false; viewModel.refresh() }
            )
        }
    }

    if (showEventCreate) {
        Dialog(
            onDismissRequest = { showEventCreate = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            EventEditScreen(
                onDismiss = { showEventCreate = false },
                onSaved = { showEventCreate = false; viewModel.refresh() }
            )
        }
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
        RecordHistorySheet(
            recordType = currentHistoryEntry.recordType,
            recordName = currentHistoryEntry.recordName,
            onDismiss = { historyEntry = null }
        )
    }

    val currentRevertTarget = revertTarget
    ImasConfirmDestructive(
        title = "この編集を取り消しますか？",
        isPresented = currentRevertTarget != null,
        onDismiss = { revertTarget = null },
        onConfirm = { currentRevertTarget?.let { viewModel.revert(it) }; revertTarget = null },
        actionTitle = "取り消す",
        message = currentRevertTarget?.let { t ->
            val label = t.summary ?: EditFeedFormat.recordTypeLabel(t.recordType)
            "「$label」を編集前の状態に戻します。この操作も履歴に記録されます。"
        },
        dismissTitle = "やめる"
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProposeEditTypeSheet(
    onDismiss: () -> Unit,
    onPickSetlist: () -> Unit,
    onPickNewSong: () -> Unit,
    onPickNewEvent: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth().padding(bottom = DS.Space.section)) {
            ImasSheetToolbar(kind = ImasSheetToolbarKind.Read(onClose = onDismiss), title = "編集の種類を選択")
            Column(Modifier.padding(horizontal = DS.Space.rowH), verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                ImasCardList(style = ImasCardListStyle.PANEL) {
                    ImasRecordRow(
                        title = "セトリを編集",
                        subtitle = "公演の楽曲・出演者の追加/修正/削除",
                        icon = Icons.Filled.QueueMusic,
                        tone = ImasIconTileTone.NEUTRAL,
                        modifier = Modifier.imasRowPress(onClick = onPickSetlist)
                    )
                    ImasRecordRow(
                        title = "曲を追加",
                        subtitle = "まだ登録されていない楽曲を作る",
                        icon = Icons.Filled.MusicNote,
                        tone = ImasIconTileTone.NEUTRAL,
                        modifier = Modifier.imasRowPress(onClick = onPickNewSong)
                    )
                    ImasRecordRow(
                        title = "ライブを追加",
                        subtitle = "まだ登録されていないライブ・イベントを作る",
                        icon = Icons.Filled.Event,
                        tone = ImasIconTileTone.NEUTRAL,
                        modifier = Modifier.imasRowPress(onClick = onPickNewEvent)
                    )
                }
                // 既存レコードの修正はそれぞれの詳細画面が入口 (どれを直すのか選ばせる画面を
                // ここに二重で作らない)。公演の追加も親ライブが決まっていないと作れない。
                ImasNote("既存の楽曲・アイドル・ライブの修正、公演の追加は、それぞれの詳細画面から行えます。")
            }
        }
    }
}

/**
 * 1 レコードの変更履歴 (`GET /master/:recordType/:recordName/history`)。
 *
 * このフィードの行からだけでなく、曲/ライブ/公演/アイドルの各詳細の「編集履歴」からも開く。
 * 呼び出し側が持っているのは編集対象そのもの (id と型) なので、フィード行ではなく
 * recordType / recordName を受け取る形にしてある。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordHistorySheet(recordType: String, recordName: String, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    var history by remember { mutableStateOf<List<EditApi.RecordHistoryEntry>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(recordType, recordName) {
        val editApi = AppModule.from(context).editApi
        try {
            history = editApi.recordHistory(recordType, recordName)
        } catch (e: Exception) {
            error = "変更履歴の取得に失敗しました"
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth().heightIn(min = 200.dp)) {
            ImasSheetToolbar(kind = ImasSheetToolbarKind.Read(onClose = onDismiss), title = "変更履歴")
            ImasNote(
                EditFeedFormat.recordTypeLabel(recordType),
                modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gapTight)
            )
            val currentHistory = history
            val state = when {
                error != null -> ImasContentState.Failed(error)
                currentHistory == null -> ImasContentState.Loading
                currentHistory.isEmpty() -> ImasContentState.Empty
                else -> ImasContentState.Loaded
            }
            ImasStateContainer(
                state = state,
                empty = { ImasEmptyState(ImasEmptyStateKind.EMPTY, title = "履歴がありません") }
            ) {
                // 相対時刻の言い回しはコア。一覧ぶんを 1 回で引き、一覧が変わるまで使い回す。
                val times = remember(currentHistory) {
                    relativeTimes(currentHistory!!.map { it.createdAt }, System.currentTimeMillis())
                }
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    ImasListSection {
                        currentHistory!!.forEachIndexed { i, h -> HistoryRow(h, times.getOrElse(i) { "" }) }
                    }
                }
            }
            Spacer(Modifier.heightIn(min = DS.Space.section))
        }
    }
}

@Composable
private fun HistoryRow(entry: EditApi.RecordHistoryEntry, timeText: String) {
    val badges = buildList {
        if (entry.reverted) add(ImasBadgeSpec("(差戻し済み)", ImasBadgeKind.NEGATIVE))
    }
    ImasRecordRow(
        title = EditFeedFormat.opLabel(entry.op),
        subtitle = entry.editorName,
        badges = badges,
        trailing = ImasRowTrailing.Value(timeText)
    ) {
        if (entry.changedFields.isNotEmpty()) {
            Text(entry.changedFields.joinToString(", "), style = ImasTextRole.NOTE.style, color = DS.ink2)
        }
    }
}

@Composable
private fun EditFeedCard(
    timeText: String,
    entry: EditApi.EditFeedEntry,
    gooded: Boolean,
    goodCount: Int,
    recordTitle: String?,
    showRevertAction: Boolean,
    isReverted: Boolean,
    isReverting: Boolean,
    onToggleGood: () -> Unit,
    onOpenHistory: () -> Unit,
    onRevertRequest: () -> Unit
) {
    ImasCard(
        modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.gapTight),
        padding = 0.dp
    ) {
        val revertedTitle = showRevertAction && isReverted
        val titleText = recordTitle ?: EditFeedFormat.recordTypeLabel(entry.recordType)
        ImasRecordRow(
            modifier = Modifier.imasRowPress(onClick = onOpenHistory),
            leading = ImasRowLeading.Icon(EditFeedFormat.recordTypeIcon(entry.recordType), tone = ImasIconTileTone.THEMED, categoryKey = entry.recordType),
            title = titleText,
            attributedTitle = if (revertedTitle) {
                AnnotatedString(titleText, spanStyle = SpanStyle(color = DS.ink2, textDecoration = TextDecoration.LineThrough))
            } else null,
            titleLineLimit = Int.MAX_VALUE,
            subtitle = entry.editorDisplayLabel,
            badges = buildList {
                add(ImasBadgeSpec(EditFeedFormat.opLabel(entry.op), EditFeedFormat.opBadgeKind(entry.op)))
                if (showRevertAction && isReverted) add(ImasBadgeSpec("差戻し済み", ImasBadgeKind.NEGATIVE))
            },
            trailing = ImasRowTrailing.Custom {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight), verticalAlignment = Alignment.CenterVertically) {
                    Text(timeText, style = ImasTextRole.META.style, color = DS.ink2)
                    ImasRowChevron()
                }
            }
        ) {
            if (!entry.summary.isNullOrEmpty()) {
                Text(entry.summary, style = ImasTextRole.NOTE.style, color = DS.ink2)
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gapTight),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)
        ) {
            if (showRevertAction) {
                if (entry.goodCount > 0) {
                    ImasBadge(text = "${entry.goodCount}", icon = Icons.Filled.Favorite, kind = ImasBadgeKind.NEUTRAL)
                }
                Spacer(Modifier.weight(1f))
                if (isReverting || (entry.isRevertable && !isReverted)) {
                    ImasButton(
                        title = "取り消す",
                        onClick = onRevertRequest,
                        icon = Icons.Filled.Undo,
                        role = ImasButtonRole.DESTRUCTIVE,
                        size = ImasButtonSize.SMALL,
                        isLoading = isReverting,
                        enabled = !isReverting
                    )
                }
            } else {
                if (entry.isOwnEdit) {
                    ImasBadge(text = "あなたの編集", icon = Icons.Filled.Person, kind = ImasBadgeKind.NEUTRAL)
                } else {
                    ImasFilterChip(
                        label = if (goodCount > 0) "$goodCount" else "Good",
                        selected = gooded,
                        icon = if (gooded) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                        onClick = onToggleGood,
                        onClickLabel = if (gooded) "Good を取り消す" else "Good を付ける",
                        contentDescription = buildString {
                            append(if (gooded) "Good を取り消す" else "Good を付ける")
                            if (goodCount > 0) append("、$goodCount 件")
                        }
                    )
                }
                Spacer(Modifier.weight(1f))
                ImasButton(
                    title = "変更履歴",
                    onClick = onOpenHistory,
                    icon = Icons.Filled.History,
                    role = ImasButtonRole.PLAIN,
                    size = ImasButtonSize.SMALL
                )
            }
        }
    }
}

/** record_type / op の表示メタ + 相対時刻整形。iOS `EditFeedFormat` の移植。
 *
 * 色は分類キー (record_type) から `ImasRowLeading.Icon(tone = THEMED, categoryKey = ...)` が安定導出する
 * ([ImasTheme.forCategoryKey] 経由、iOS `ImasTheme.derive(categoryKey:)` と同じ仕組み) ため、ここでは
 * アイコン・ラベルの対応表だけを持つ (手書きの色パレットは持たない)。
 *
 * op の札も iOS 本体と同じ方針 (§10.1: 操作は色でなく文字で区別する) に合わせ、差戻しだけ
 * `NEGATIVE` (灰) にする。旧実装にあった op ごとの色分け (追加=緑/更新=青/削除=赤 等) は
 * iOS 側でも実際には使われていない (`opDesign` は死んだコード) ため、ここでは持ち越さない。
 */
private object EditFeedFormat {
    fun recordTypeIcon(type: String): ImageVector = when (type) {
        "Event" -> Icons.Filled.Event
        "Show" -> Icons.Filled.MusicNote
        "Song" -> Icons.Filled.MusicNote
        "Idol" -> Icons.Filled.Person
        "SetlistItem", "ShowSetlist" -> Icons.Filled.QueueMusic
        "SetlistPerformer" -> Icons.AutoMirrored.Filled.List
        "SongArtist" -> Icons.Filled.MusicNote
        "ShowCast" -> Icons.Filled.Person
        else -> Icons.Filled.EditNote
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
        // 2026-09-06 に廃止した投稿型。過去の履歴だけが残る。
        "SongCall" -> "コーレス (終了)"
        else -> type
    }

    fun opLabel(op: String): String = when (op) {
        "create" -> "追加"
        "update", "replace" -> "更新"
        "delete" -> "削除"
        "revert" -> "差戻し"
        "snapshot" -> "セトリ更新"
        else -> op
    }

    /** 差し戻しだけ「取り消された記録」として `NEGATIVE` (灰の薄字) に当てる。 */
    fun opBadgeKind(op: String): ImasBadgeKind = if (op == "revert") ImasBadgeKind.NEGATIVE else ImasBadgeKind.NEUTRAL
}
