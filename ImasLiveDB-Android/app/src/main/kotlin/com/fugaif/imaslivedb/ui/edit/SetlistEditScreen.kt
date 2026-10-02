package com.fugaif.imaslivedb.ui.edit

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.edit.friendlyMessage
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.SetlistItem
import com.fugaif.imaslivedb.data.model.SetlistPerformer
import com.fugaif.imaslivedb.data.model.SetlistRow
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasConfirmDestructive
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowEmphasis
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.PickedSongRecord
import uniffi.imas_core.SetlistItemDiffRow
import uniffi.imas_core.setlistItemIndexesNeedingSync
import uniffi.imas_core.setlistPerformerIndexesNeedingSync
import java.util.UUID

/** 編集中の 1 行 (iOS `EditableSetlistRow` の移植)。 */
data class EditableSetlistRow(
    val rowId: String = UUID.randomUUID().toString(),
    val existingItemId: String? = null,
    val songId: String = "",
    val songTitle: String = "(曲を選択)",
    val section: String? = null,
    val castIds: Set<String> = emptySet()
)

sealed class SetlistSaveOutcome {
    object Applied : SetlistSaveOutcome()
    data class Requested(val issueUrl: String?) : SetlistSaveOutcome()
    data class Failed(val message: String) : SetlistSaveOutcome()
}

data class SetlistEditUiState(
    val rows: List<EditableSetlistRow> = emptyList(),
    val initialItemIds: List<String> = emptyList(),
    /**
     * 編集前のセトリ行 (item id → 行そのもの)。用途は 2 つあり、どちらも**全列**が要る:
     *  - 「値が変わった行だけ送る」差分判定のベースライン (判定そのものは共有コアが行う)
     *  - このフォームが編集しない列 (notes / unitName) の引き継ぎ元。射影に落として
     *    捨てると [save] の楽観更新がその列を null で上書きする (iOS SetlistEditView と同じ理由)。
     */
    val originalItems: Map<String, SetlistRow> = emptyMap(),
    val initialPerformerKeys: Set<Pair<String, String>> = emptySet(),
    val idolById: Map<String, Idol> = emptyMap(),
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val errorMessage: String? = null,
    val saveOutcome: SetlistSaveOutcome? = null
)

/** セトリ編集の状態管理。iOS `SetlistEditView` の移植 (契約: POST /edits を 1 リクエスト = 1 batch)。 */
class SetlistEditViewModel(app: Application, private val show: Show) : AndroidViewModel(app) {
    private val eventRepo = AppModule.from(app).eventRepository
    private val masterEditRepo = AppModule.from(app).masterEditRepository
    private val idolRepo = AppModule.from(app).idolRepository
    private val editApi = AppModule.from(app).editApi

    private val _uiState = MutableStateFlow(SetlistEditUiState())
    val uiState: StateFlow<SetlistEditUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch { load() }
    }

    private suspend fun load() {
        try {
            val setlist: List<SetlistRow> = eventRepo.fetchSetlist(show.id)
            val allPerformers = eventRepo.fetchAllPerformers(show.id)
            val performersByItem = allPerformers.groupBy { it.setlistItemId }
            val idols = idolRepo.fetchIdols()
            val idolById = idols.associateBy { it.id }

            val rows = setlist.map { item ->
                EditableSetlistRow(
                    existingItemId = item.id,
                    songId = item.songId,
                    songTitle = item.songTitle,
                    section = item.section,
                    castIds = (performersByItem[item.id] ?: emptyList()).mapNotNull { it.idolId }.toSet()
                )
            }
            val performerKeys = allPerformers.mapNotNull { p -> p.idolId?.let { p.setlistItemId to it } }.toSet()

            _uiState.value = SetlistEditUiState(
                rows = rows,
                initialItemIds = setlist.map { it.id },
                originalItems = setlist.associateBy { it.id },
                initialPerformerKeys = performerKeys,
                idolById = idolById,
                isLoading = false
            )
        } catch (e: Exception) {
            _uiState.value = _uiState.value.copy(isLoading = false, errorMessage = "セトリ読み込み失敗: ${e.message}")
        }
    }

    fun addRow(song: PickedSongRecord) {
        val state = _uiState.value
        _uiState.value = state.copy(rows = state.rows + EditableSetlistRow(songId = song.id, songTitle = song.title))
    }

    fun setSong(rowId: String, song: PickedSongRecord) {
        updateRow(rowId) { it.copy(songId = song.id, songTitle = song.title) }
    }

    fun setSection(rowId: String, section: String?) {
        updateRow(rowId) { it.copy(section = section) }
    }

    fun setCasts(rowId: String, castIds: Set<String>) {
        updateRow(rowId) { it.copy(castIds = castIds) }
    }

    fun removeRow(rowId: String) {
        val state = _uiState.value
        _uiState.value = state.copy(rows = state.rows.filterNot { it.rowId == rowId })
    }

    fun moveUp(rowId: String) = move(rowId, -1)
    fun moveDown(rowId: String) = move(rowId, 1)

    private fun move(rowId: String, delta: Int) {
        val state = _uiState.value
        val idx = state.rows.indexOfFirst { it.rowId == rowId }
        val target = idx + delta
        if (idx < 0 || target < 0 || target >= state.rows.size) return
        val newRows = state.rows.toMutableList()
        val tmp = newRows[idx]
        newRows[idx] = newRows[target]
        newRows[target] = tmp
        _uiState.value = state.copy(rows = newRows)
    }

    private fun updateRow(rowId: String, transform: (EditableSetlistRow) -> EditableSetlistRow) {
        val state = _uiState.value
        _uiState.value = state.copy(rows = state.rows.map { if (it.rowId == rowId) transform(it) else it })
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    fun consumeSaveOutcome() {
        _uiState.value = _uiState.value.copy(saveOutcome = null)
    }

    fun save() {
        val state = _uiState.value
        if (state.rows.any { it.songId.isEmpty() }) {
            _uiState.value = state.copy(errorMessage = "曲が未選択の行があります")
            return
        }
        _uiState.value = state.copy(isSaving = true)
        viewModelScope.launch {
            try {
                val existingIds = state.initialItemIds.toSet()

                // 新しい SetlistItem を構築。既存行は元 ID 維持 (位置非依存)、新規行は sli_<uuid>。
                // フォームに無い列 (notes / unitName) は元レコードから引き継ぐ。null で構築すると
                // 下の replaceSetlist (upsertItems = REPLACE) がその列を消してしまい、しかも
                // 差分送信のせいでサーバの modifiedAt が動かないため増分同期でも戻ってこない。
                data class Built(val item: SetlistItem, val castIds: Set<String>)
                val built = state.rows.mapIndexed { idx, row ->
                    val original = row.existingItemId?.let { state.originalItems[it] }
                    Built(
                        item = SetlistItem(
                            id = row.existingItemId ?: "sli_${UUID.randomUUID()}",
                            showId = show.id,
                            songId = row.songId,
                            position = idx + 1,
                            section = row.section,
                            notes = original?.notes,
                            unitName = original?.unitName
                        ),
                        castIds = row.castIds
                    )
                }

                val newItemIds = built.map { it.item.id }.toSet()
                val deletedItemIds = state.initialItemIds.filter { it !in newItemIds }

                // 出演者は index で引き直すのでリストのまま保持する (集合化は削除差分の計算だけ)。
                val newPerformers = built.flatMap { b -> b.castIds.map { b.item.id to it } }
                val deletedPerformerKeys = state.initialPerformerKeys - newPerformers.toSet()

                // 変わっていない行は送らない。差分規則は共有コア (domain::setlist_diff)。
                // 以前は 1 曲直すだけでも全曲・全出演者を送っていたため実測最大 606 ops に達し、
                // 一般ユーザーの修正リクエストが op 上限で弾かれていた。
                val changedItems = setlistItemIndexesNeedingSync(
                    items = built.map { it.item.toDiffRow() },
                    original = state.originalItems.values.map { it.toDiffRow() }
                ).map { built[it.toInt()].item }

                // 出演者は create と delete しか意味を持たない。SetlistPerformer は
                // (setlistItemId, idolId) しか持たず recordName がその 2 つから決まるので、
                // 既存出演者を update しても書く値が recordName と同じで変化しようがない。
                val addedPerformers = setlistPerformerIndexesNeedingSync(
                    recordNames = newPerformers.map { (itemId, idolId) -> performerRecordName(itemId, idolId) },
                    initialRecordNames = state.initialPerformerKeys.map { (itemId, idolId) ->
                        performerRecordName(itemId, idolId)
                    }
                ).map { newPerformers[it.toInt()] }

                val ops = mutableListOf<EditApi.EditOperation>()
                for (item in changedItems) {
                    val fields = mutableMapOf<String, Any?>(
                        "showId" to item.showId,
                        "songId" to item.songId,
                        "position" to item.position
                    )
                    if (item.section != null) {
                        fields["section"] = item.section
                    } else if (state.originalItems[item.id]?.section != null) {
                        // 「本編」に戻した = section のクリア。null を明示送信してサーバのマージで削除させる。
                        fields["section"] = null
                    }
                    ops.add(
                        EditApi.EditOperation(
                            op = if (existingIds.contains(item.id)) EditApi.EditOp.UPDATE else EditApi.EditOp.CREATE,
                            recordType = "SetlistItem",
                            recordName = item.id,
                            fields = fields
                        )
                    )
                }
                for ((itemId, idolId) in addedPerformers) {
                    ops.add(
                        EditApi.EditOperation(
                            op = EditApi.EditOp.CREATE,
                            recordType = "SetlistPerformer",
                            recordName = performerRecordName(itemId, idolId),
                            fields = mapOf("setlistItemId" to itemId, "idolId" to idolId)
                        )
                    )
                }
                for (id in deletedItemIds) {
                    ops.add(EditApi.EditOperation(op = EditApi.EditOp.DELETE, recordType = "SetlistItem", recordName = id))
                }
                for ((itemId, idolId) in deletedPerformerKeys) {
                    ops.add(
                        EditApi.EditOperation(
                            op = EditApi.EditOp.DELETE,
                            recordType = "SetlistPerformer",
                            recordName = performerRecordName(itemId, idolId)
                        )
                    )
                }

                // 差分が空 = 何も変えずに保存した。送るものが無いので通信もローカル置換もせず、
                // 「修正リクエストを送信しました」を出さずに閉じる (iOS SetlistEditView と同じ)。
                if (ops.isEmpty()) {
                    _uiState.value = _uiState.value.copy(isSaving = false, saveOutcome = SetlistSaveOutcome.Applied)
                    return@launch
                }

                val outcome = editApi.submitMaster(ops, summary = "セトリ編集")
                when (outcome) {
                    is EditApi.MasterEditOutcome.Applied -> {
                        // ローカル置換は差分ではなく編集後の全量で行う (サーバ確定値との一致が目的)。
                        val performers = newPerformers.map { (itemId, idolId) -> SetlistPerformer(itemId, idolId) }
                        masterEditRepo.replaceSetlist(
                            deletedItemIds = deletedItemIds,
                            deletedPerformers = deletedPerformerKeys.toList(),
                            items = built.map { it.item },
                            performers = performers
                        )
                        _uiState.value = _uiState.value.copy(isSaving = false, saveOutcome = SetlistSaveOutcome.Applied)
                    }
                    is EditApi.MasterEditOutcome.Requested -> {
                        _uiState.value = _uiState.value.copy(
                            isSaving = false,
                            saveOutcome = SetlistSaveOutcome.Requested(outcome.response.issueUrl)
                        )
                    }
                }
            } catch (e: EditApi.ApiException) {
                _uiState.value = _uiState.value.copy(isSaving = false, errorMessage = e.friendlyMessage())
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isSaving = false, errorMessage = "保存失敗: ${e.message}")
            }
        }
    }

    private fun performerRecordName(itemId: String, idolId: String) = "setlist_performers-$itemId-$idolId"
}

/** 差分判定に渡す射影。サーバに送る field だけを持つ (曲名やジャケ URL は編集対象外)。 */
private fun SetlistItem.toDiffRow() = SetlistItemDiffRow(
    id = id, songId = songId, position = position.toLong(), section = section
)

/** 編集前の行を同じ射影に落とす。比較の対象を送信 field だけに揃えるため。 */
private fun SetlistRow.toDiffRow() = SetlistItemDiffRow(
    id = id, songId = songId, position = position.toLong(), section = section
)

/**
 * セトリ編集画面。iOS `SetlistEditView` の移植。
 * ナビゲーションは Compose の Dialog (フルスクリーン) で表示する想定 (呼び出し元 [RecentEditsScreen] 参照)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SetlistEditScreen(
    show: Show,
    eventName: String,
    onDismiss: () -> Unit,
    onSaved: () -> Unit
) {
    val context = LocalContext.current
    val app = context.applicationContext as Application
    val viewModel = viewModel<SetlistEditViewModel>(factory = SetlistEditViewModelFactory(app, show))
    val state by viewModel.uiState.collectAsState()

    var songPickerForRow by remember { mutableStateOf<String?>(null) }
    var castPickerForRow by remember { mutableStateOf<String?>(null) }
    var showClearConfirm by remember { mutableStateOf(false) }

    var requestedOutcome by remember { mutableStateOf<SetlistSaveOutcome.Requested?>(null) }

    LaunchedEffect(state.saveOutcome) {
        when (val outcome = state.saveOutcome) {
            is SetlistSaveOutcome.Applied -> {
                viewModel.consumeSaveOutcome()
                onSaved()
            }
            is SetlistSaveOutcome.Requested -> {
                viewModel.consumeSaveOutcome()
                requestedOutcome = outcome
            }
            else -> {}
        }
    }

    Scaffold(
        topBar = {
            ImasSheetToolbar(
                kind = ImasSheetToolbarKind.Edit(
                    canSave = !state.isSaving,
                    onCancel = onDismiss,
                    onSave = {
                        if (state.rows.isEmpty() && state.initialItemIds.isNotEmpty()) {
                            showClearConfirm = true
                        } else {
                            viewModel.save()
                        }
                    }
                ),
                title = "セトリ編集"
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            if (state.isLoading) {
                ImasLoadingState()
            } else {
                Column(Modifier.fillMaxSize()) {
                    ImasNote(
                        "$eventName ・ ${show.name}",
                        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
                    )
                    LazyColumn(modifier = Modifier.fillMaxSize().weight(1f)) {
                        items(state.rows, key = { it.rowId }) { row ->
                            SetlistEditRowView(
                                row = row,
                                idolById = state.idolById,
                                isFirst = state.rows.firstOrNull()?.rowId == row.rowId,
                                isLast = state.rows.lastOrNull()?.rowId == row.rowId,
                                onPickSong = { songPickerForRow = row.rowId },
                                onPickCasts = { castPickerForRow = row.rowId },
                                onSectionChange = { viewModel.setSection(row.rowId, it) },
                                onMoveUp = { viewModel.moveUp(row.rowId) },
                                onMoveDown = { viewModel.moveDown(row.rowId) },
                                onRemove = { viewModel.removeRow(row.rowId) }
                            )
                        }
                        item {
                            ImasFormCard(
                                modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
                            ) {
                                ImasActionRow(
                                    title = "曲を追加",
                                    onClick = { songPickerForRow = NEW_ROW_MARKER },
                                    icon = Icons.Filled.AddCircle
                                )
                            }
                        }
                    }
                }
            }

            ImasSavingOverlay(state.isSaving, label = "保存中…")
        }
    }

    state.errorMessage?.let { EditErrorDialog(it) { viewModel.clearError() } }

    requestedOutcome?.let { outcome ->
        EditRequestSentDialog(outcome.issueUrl) { requestedOutcome = null; onSaved() }
    }

    ImasConfirmDestructive(
        title = "セトリを全削除しますか?",
        isPresented = showClearConfirm,
        onDismiss = { showClearConfirm = false },
        onConfirm = { viewModel.save() },
        actionTitle = "削除する",
        message = "この公演のセトリ ${state.initialItemIds.size} 件をすべて削除します。この操作は取り消せません。"
    )

    if (songPickerForRow != null) {
        SongPickerSheet(
            onDismiss = { songPickerForRow = null },
            onSelect = { song ->
                val target = songPickerForRow
                if (target == NEW_ROW_MARKER) {
                    viewModel.addRow(song)
                } else if (target != null) {
                    viewModel.setSong(target, song)
                }
                songPickerForRow = null
            }
        )
    }

    if (castPickerForRow != null) {
        val row = state.rows.firstOrNull { it.rowId == castPickerForRow }
        if (row != null) {
            IdolMultiSelectSheet(
                selected = row.castIds,
                onDismiss = { castPickerForRow = null },
                onConfirm = { newSelection ->
                    viewModel.setCasts(row.rowId, newSelection)
                    castPickerForRow = null
                }
            )
        }
    }
}

private const val NEW_ROW_MARKER = "__new_row__"

private class SetlistEditViewModelFactory(
    private val app: Application,
    private val show: Show
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return SetlistEditViewModel(app, show) as T
    }
}

private val sections = listOf("本編", "アンコール", "MC", "ダブルアンコール")

@Composable
private fun SetlistEditRowView(
    row: EditableSetlistRow,
    idolById: Map<String, Idol>,
    isFirst: Boolean,
    isLast: Boolean,
    onPickSong: () -> Unit,
    onPickCasts: () -> Unit,
    onSectionChange: (String?) -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onRemove: () -> Unit
) {
    ImasFormCard(
        modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ImasRow(
                    title = row.songTitle,
                    modifier = Modifier.weight(1f).imasRowPress(onClick = onPickSong),
                    leading = ImasRowLeading.Icon(Icons.Filled.MusicNote, tone = ImasIconTileTone.NEUTRAL),
                    density = ImasRowDensity.COMPACT,
                    emphasis = if (row.songId.isEmpty()) ImasRowEmphasis.DIMMED else ImasRowEmphasis.NORMAL,
                    titleLineLimit = 2,
                    titleRole = ImasTextRole.ROW_LABEL
                )
                IconButton(onClick = onMoveUp, enabled = !isFirst) {
                    Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "上へ")
                }
                IconButton(onClick = onMoveDown, enabled = !isLast) {
                    Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "下へ")
                }
                IconButton(onClick = onRemove) {
                    Icon(Icons.Filled.Close, contentDescription = "削除", tint = DS.danger)
                }
            }

            ImasSegmented(
                labels = sections,
                // 4 択以外の値は -1 のまま渡す (coerceAtLeast(0) で「本編」扱いにすると、
                // 実際には本編ではないのに「本編」をタップしても選択済み扱いで反応しなくなる)。
                selection = sections.indexOf(row.section ?: "本編"),
                onSelect = { index -> onSectionChange(sections[index].takeUnless { it == "本編" }) }
            )

            ImasRow(
                title = if (row.castIds.isEmpty()) {
                    "(出演者なし — タップで追加)"
                } else {
                    row.castIds.mapNotNull { idolById[it]?.name }.sorted().joinToString(" / ")
                },
                modifier = Modifier.imasRowPress(onClick = onPickCasts),
                leading = ImasRowLeading.Icon(Icons.Filled.Person, tone = ImasIconTileTone.NEUTRAL),
                density = ImasRowDensity.COMPACT,
                emphasis = if (row.castIds.isEmpty()) ImasRowEmphasis.DIMMED else ImasRowEmphasis.NORMAL,
                titleLineLimit = 99,
                titleRole = ImasTextRole.ROW_LABEL
            )
        }
    }
}
