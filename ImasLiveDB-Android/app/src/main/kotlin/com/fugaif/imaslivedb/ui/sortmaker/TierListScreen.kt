package com.fugaif.imaslivedb.ui.sortmaker

import androidx.compose.foundation.layout.heightIn
import com.fugaif.imaslivedb.ui.components.NameFilterField
import com.fugaif.imaslivedb.ui.components.rememberSearchFiltered
import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.games.TierDef
import com.fugaif.imaslivedb.data.games.TierListBoard
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasArtwork
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasTierBoard
import com.fugaif.imaslivedb.ui.designsystem.ImasTierChip
import com.fugaif.imaslivedb.ui.designsystem.ImasTierChipMediaSize
import com.fugaif.imaslivedb.ui.designsystem.ImasTierHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasTierItems
import com.fugaif.imaslivedb.ui.designsystem.ImasTierItemsLayout
import com.fugaif.imaslivedb.ui.designsystem.ImasTierLabel
import com.fugaif.imaslivedb.ui.designsystem.ImasTierLabelStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasTierMoveBar
import com.fugaif.imaslivedb.ui.designsystem.ImasTierRow
import com.fugaif.imaslivedb.ui.designsystem.ImasTierSpec
import com.fugaif.imaslivedb.ui.designsystem.ImasTierDragAutoScroll
import com.fugaif.imaslivedb.ui.designsystem.imasTierDragAutoScrollArea
import com.fugaif.imaslivedb.ui.designsystem.imasTierDropTarget
import com.fugaif.imaslivedb.ui.designsystem.rememberImasTierDragAutoScroll
import com.fugaif.imaslivedb.ui.theme.BrandColors
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasTheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.tierListCycleColor
import uniffi.imas_core.tierListMaxTiers
import uniffi.imas_core.tierListMinTiers
import uniffi.imas_core.tierListNewTier
import uniffi.imas_core.tierListNormalizeTierLabel
import uniffi.imas_core.tierListNormalizeTitle
import uniffi.imas_core.tierListTierLabelMaxChars
import uniffi.imas_core.tierListTitleMaxChars

// =============================================================================
// ティアー表の編集画面。iOS TierListView.swift の移植。
// タップで選ぶ → 下のバーで段を押す、が主な操作。長押しでつかんで段へ運ぶ近道もある
// (長押しのまま動かさずに離すと詳細)。段の中の札の上に落とすと、その左に入る。
// 1 回動かすたびに端末へ保存する (一覧から何枚でも開き直せる)。
// 見た目の部品は ui/designsystem/ImasTierList.kt (iOS ImasTierList.swift と同名・同役目)。
// =============================================================================

data class TierListUiState(
    val board: TierListBoard,
    val items: Map<String, SortMakerItem> = emptyMap(),
    val isLoaded: Boolean = false
)

class TierListViewModel : ViewModel() {

    private val _uiState = MutableStateFlow<TierListUiState?>(null)
    val uiState: StateFlow<TierListUiState?> = _uiState.asStateFlow()

    private var appModule: AppModule? = null
    private var loaded = false

    fun load(context: Context, initialBoard: TierListBoard) {
        if (loaded) return
        loaded = true
        val module = AppModule.from(context)
        appModule = module
        _uiState.value = TierListUiState(board = initialBoard)
        viewModelScope.launch {
            val loadedItems = SortMakerCandidates.loadByIds(
                initialBoard.subject, initialBoard.itemIds, module.songRepository, module.idolRepository
            )
            val map = initialBoard.itemIds.zip(loadedItems).mapNotNull { (id, item) -> item?.let { id to it } }.toMap()
            val current = _uiState.value ?: return@launch
            _uiState.value = current.copy(items = map, isLoaded = true)
        }
    }

    fun move(id: String, tierId: String?, before: String? = null) {
        val current = _uiState.value ?: return
        commit(current.board.moved(id, tierId, before).copy(savedAt = System.currentTimeMillis()))
    }

    fun resetToSuggested() {
        val current = _uiState.value ?: return
        val suggested = current.board.suggested ?: return
        commit(current.board.copy(placements = suggested, order = null, savedAt = System.currentTimeMillis()))
    }

    fun resetAllUnplaced() {
        val current = _uiState.value ?: return
        commit(current.board.copy(placements = emptyMap(), order = null, savedAt = System.currentTimeMillis()))
    }

    /** 表の名前・段 (名前・色・並び・数) を保存する。消した段にいたものは未分類へ。 */
    fun updateTitleAndTiers(title: String?, tiers: List<TierDef>) {
        val current = _uiState.value ?: return
        val keptIds = tiers.map { it.id }.toSet()
        val placements = current.board.placements.filterValues { keptIds.contains(it) }
        commit(current.board.copy(title = title, tiers = tiers, placements = placements, savedAt = System.currentTimeMillis()))
    }

    private fun commit(newBoard: TierListBoard) {
        appModule?.tierListStore?.save(newBoard)
        _uiState.value = _uiState.value?.copy(board = newBoard)
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun TierListScreen(
    board: TierListBoard,
    onBack: () -> Unit,
    onItemClick: (SortMakerItem) -> Unit,
    viewModel: TierListViewModel = viewModel(key = "tier_list_${board.id}")
) {
    val context = LocalContext.current
    LaunchedEffect(board.id) { viewModel.load(context, board) }

    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    var showMenu by remember { mutableStateOf(false) }
    var confirmReset by rememberSaveable { mutableStateOf(false) }
    var showExport by rememberSaveable { mutableStateOf(false) }
    var showEdit by rememberSaveable { mutableStateOf(false) }
    /** ドラッグ中、その左に入る札 (段の中の並べ替えの印を出す)。 */
    var dropBeforeId by remember { mutableStateOf<String?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(board.subject.tierTitle, fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") } },
                actions = {
                    IconButton(onClick = { selectedId = null; showExport = true }) { Icon(Icons.Filled.Share, "画像にする") }
                    IconButton(onClick = { showMenu = true }) { Icon(Icons.Filled.MoreVert, "その他") }
                    DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                        DropdownMenuItem(
                            text = { Text("名前と段を編集") },
                            leadingIcon = { Icon(Icons.Filled.Edit, null) },
                            onClick = { showMenu = false; showEdit = true }
                        )
                        if (state?.board?.suggested != null) {
                            DropdownMenuItem(
                                text = { Text("ソート結果のたたき台に戻す") },
                                leadingIcon = { Icon(Icons.Filled.Restore, null) },
                                onClick = { showMenu = false; viewModel.resetToSuggested() }
                            )
                        }
                        DropdownMenuItem(
                            text = { Text("全部を未分類に戻す") },
                            leadingIcon = { Icon(Icons.Filled.Inbox, null) },
                            onClick = { showMenu = false; confirmReset = true }
                        )
                    }
                }
            )
        }
    ) { padding ->
        val s = state
        Box(Modifier.fillMaxSize().padding(padding).background(DS.bg)) {
            if (s == null || !s.isLoaded) {
                ImasLoadingState()
            } else {
                val scrollState = rememberScrollState()
                val autoScroll = rememberImasTierDragAutoScroll(scrollState)
                Column(Modifier.fillMaxSize()) {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .imasTierDragAutoScrollArea(autoScroll)
                            .verticalScroll(scrollState)
                            .padding(DS.sp5),
                        verticalArrangement = Arrangement.spacedBy(DS.sp4)
                    ) {
                        ImasTierHeader(
                            title = s.board.displayTitle,
                            subtitle = "${s.board.scopeLabel} · ${s.board.placedCount} / ${s.board.itemIds.size} 振り分け済み",
                            onEdit = { showEdit = true }
                        )
                        // チップのタップ。何か選んでいて別のチップを押したら、そのチップの段の
                        // その左 (未分類なら未分類) へ移す (段の中はチップで埋まるので、行の余白を
                        // 押せと言っても押せない)。
                        val tapChip: (String) -> Unit = { id ->
                            val selected = selectedId
                            if (selected != null && selected != id) {
                                viewModel.move(selected, s.board.placements[id], before = id)
                                selectedId = null
                            } else {
                                selectedId = if (selectedId == id) null else id
                            }
                        }
                        ImasTierBoard {
                            s.board.tiers.forEach { tier ->
                                val ids = s.board.idsInTier(tier.id)
                                ImasTierRow(
                                    label = tier.label,
                                    seed = tier.colorSeed,
                                    isTarget = selectedId != null,
                                    accessibilityLabel = "${tier.label} ${ids.size}件",
                                    onMoveHere = { selectedId?.let { viewModel.move(it, tier.id); selectedId = null } },
                                    // 段の余白に落とす = その段の右端。
                                    modifier = Modifier.imasTierDropTarget(onDrop = { dragged ->
                                        if (dragged !in s.board.itemIds) return@imasTierDropTarget false
                                        viewModel.move(dragged, tier.id); selectedId = null; true
                                    }, autoScroll = autoScroll)
                                ) {
                                    ImasTierItems(
                                        ids = ids,
                                        emptyText = if (selectedId != null) "ここへ移す" else null
                                    ) { id ->
                                        TierListChip(
                                            item = s.items[id], isSelected = selectedId == id,
                                            onClick = { tapChip(id) }, onLongClick = { s.items[id]?.let(onItemClick) },
                                            dragId = id, showsInsertMark = dropBeforeId == id,
                                            // 札の上に落とす = その左。
                                            modifier = Modifier.imasTierDropTarget(
                                                onDrop = { dragged ->
                                                    if (dragged !in s.board.itemIds) return@imasTierDropTarget false
                                                    viewModel.move(dragged, tier.id, before = id); selectedId = null; true
                                                },
                                                onHover = { over ->
                                                    if (over) dropBeforeId = id else if (dropBeforeId == id) dropBeforeId = null
                                                },
                                                autoScroll = autoScroll
                                            )
                                        )
                                    }
                                }
                            }
                        }
                        ImasButton(
                            title = "段を編集", onClick = { showEdit = true },
                            icon = Icons.Filled.Edit, role = ImasButtonRole.SECONDARY,
                            size = ImasButtonSize.MEDIUM, fillsWidth = true
                        )
                        UnplacedSection(
                            ids = s.board.unplacedIds,
                            items = s.items,
                            selectedId = selectedId,
                            hasSelection = selectedId != null,
                            onSelect = tapChip,
                            onItemDetail = onItemClick,
                            onRowClick = { selectedId?.let { viewModel.move(it, null); selectedId = null } },
                            onDrop = { dragged ->
                                if (dragged !in s.board.itemIds) false else { viewModel.move(dragged, null); selectedId = null; true }
                            },
                            autoScroll = autoScroll
                        )
                        ImasText(
                            "タップで選んで下のボタンで段を選ぶか、長押しでつかんで段まで運んでください。段の中の札の上に落とすと、その左に入ります。変えるたびに端末に保存されます。",
                            ImasTextRole.META
                        )
                    }
                    AnimatedVisibility(
                        visible = selectedId != null,
                        enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
                        exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
                    ) {
                        val id = selectedId
                        val item = id?.let { s.items[it] }
                        if (id != null) {
                            ImasTierMoveBar(
                                title = "「${item?.title ?: ""}」をどこへ？",
                                tiers = s.board.tiers.map { ImasTierSpec(it.id, it.label, it.colorSeed) },
                                onCancel = { selectedId = null },
                                onMove = { tierId -> viewModel.move(id, tierId); selectedId = null },
                                onUnplace = { viewModel.move(id, null); selectedId = null }
                            )
                        }
                    }
                }
            }
        }
    }

    if (confirmReset) {
        AlertDialog(
            onDismissRequest = { confirmReset = false },
            title = { Text("全部を未分類に戻しますか？") },
            confirmButton = {
                Text(
                    "未分類に戻す", color = DS.warning,
                    modifier = Modifier.clickable { confirmReset = false; viewModel.resetAllUnplaced() }.padding(DS.sp4)
                )
            },
            dismissButton = {
                Text("キャンセル", color = DS.ink2, modifier = Modifier.clickable { confirmReset = false }.padding(DS.sp4))
            }
        )
    }

    if (showExport) {
        state?.let { s ->
            TierListExportSheet(board = s.board, items = s.items, onDismiss = { showExport = false })
        }
    }

    if (showEdit) {
        state?.let { s ->
            TierListEditSheet(
                board = s.board,
                onDismiss = { showEdit = false },
                onSave = { title, tiers -> viewModel.updateTitleAndTiers(title, tiers); showEdit = false }
            )
        }
    }
}

@Composable
private fun UnplacedSection(
    ids: List<String>,
    items: Map<String, SortMakerItem>,
    selectedId: String?,
    hasSelection: Boolean,
    onSelect: (String) -> Unit,
    onItemDetail: (SortMakerItem) -> Unit,
    onRowClick: () -> Unit,
    onDrop: (String) -> Boolean,
    autoScroll: ImasTierDragAutoScroll
) {
    // 全曲を入れると数千件になるので、名前・歌唱で絞り込めるようにする (照合はコア)。
    var query by rememberSaveable { mutableStateOf("") }
    val visible = rememberSearchFiltered(ids, query) { id ->
        when (val item = items[id]) {
            is SortMakerItem.SongItem -> listOf(item.song.title, item.song.titleKana, item.song.singerLabel, item.song.unitName)
            is SortMakerItem.IdolItem -> listOf(item.idol.name, item.idol.nameKana, item.idol.aliases)
            else -> emptyList()
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(DS.sp3)) {
        ImasSectionHeader(
            "未分類",
            count = if (query.isBlank()) "${ids.size}" else "${visible.size} / ${ids.size}",
            tight = true,
            contentPadding = PaddingValues(0.dp)
        )
        if (ids.size > 12) {
            NameFilterField(
                prompt = if (items.values.firstOrNull() is SortMakerItem.IdolItem) "名前で絞り込み" else "曲名・歌唱で絞り込み",
                value = query, onValueChange = { query = it }, modifier = Modifier.fillMaxWidth()
            )
        }
        ImasCard(padding = 0.dp, modifier = Modifier.imasTierDropTarget(onDrop = onDrop, autoScroll = autoScroll)) {
            // 数が多いときは見えている分だけ描く格子 (枠の中でスクロール)。iOS の LazyVGrid は常に
            // 遅延描画だが、Compose の FlowRow は遅延しないので、ここだけ件数で切り替える
            // (全曲 (数千件) を回り込みで一度に組むと開いた瞬間に固まる)。
            val layout = if (visible.size > 60) ImasTierItemsLayout.GRID else ImasTierItemsLayout.FLOW
            ImasTierItems(
                ids = visible,
                layout = layout,
                emptyText = when {
                    ids.isEmpty() -> "全部振り分けました"
                    visible.isEmpty() -> "当てはまるものがありません"
                    hasSelection -> "ここへ移す"
                    else -> null
                },
                modifier = Modifier
                    .heightIn(min = 72.dp)
                    .clickable(onClick = onRowClick)
            ) { id ->
                TierListChip(
                    item = items[id], isSelected = selectedId == id,
                    onClick = { onSelect(id) }, onLongClick = { items[id]?.let(onItemDetail) }, dragId = id
                )
            }
        }
    }
}

/** ティアー表の 1 枚。項目のモデル ([SortMakerItem]) から [ImasTierChip] を組む。 */
@Composable
private fun TierListChip(
    item: SortMakerItem?,
    isSelected: Boolean,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    dragId: String? = null,
    showsInsertMark: Boolean = false,
    modifier: Modifier = Modifier
) {
    ImasTierChip(
        title = item?.title ?: "",
        seed = item?.seed,
        brand = BrandColors.hex(item?.brandId),
        isSelected = isSelected,
        modifier = modifier,
        accessibilityTitle = if (item == null) "不明" else null,
        onClick = onClick,
        onLongClick = onLongClick,
        dragData = dragId,
        showsInsertMark = showsInsertMark
    ) { size ->
        when (item) {
            is SortMakerItem.SongItem -> ImasArtwork(title = item.song.title, imageUrl = item.song.artworkUrl, size = size)
            is SortMakerItem.IdolItem -> ImasAvatar(label = item.idol.shortName, seed = item.idol.color, brand = item.idol.brandId, size = size, entityId = item.idol.id)
            null -> ImasArtwork(title = "?", size = size)
        }
    }
}

// MARK: - 名前と段を編集するシート

/** 表の名前と段 (名前・色・並び・数) を編集するシート。保存を押すまで表は変わらない。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TierListEditSheet(
    board: TierListBoard,
    onDismiss: () -> Unit,
    onSave: (title: String?, tiers: List<TierDef>) -> Unit
) {
    val titleMax = remember { tierListTitleMaxChars().toInt() }
    val labelMax = remember { tierListTierLabelMaxChars().toInt() }
    val minTiers = remember { tierListMinTiers().toInt() }
    val maxTiers = remember { tierListMaxTiers().toInt() }
    var title by rememberSaveable { mutableStateOf(board.title ?: "") }
    var tiers by remember { mutableStateOf(board.tiers) }
    val accent = imasTheme(null, null).accent

    val removedWithItems = remember(tiers) {
        val kept = tiers.map { it.id }.toSet()
        board.placements.values.count { !kept.contains(it) }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = DS.sp5)
                .padding(bottom = DS.sp7),
            verticalArrangement = Arrangement.spacedBy(DS.sp6)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(vertical = DS.sp2)) {
                Text("キャンセル", style = ImasType.text(15.sp), color = DS.ink2, modifier = Modifier.clickable(onClick = onDismiss))
                Spacer(Modifier.weight(1f))
                ImasText("名前と段を編集", ImasTextRole.CARD_TITLE)
                Spacer(Modifier.weight(1f))
                Text(
                    "保存", style = ImasType.text(15.sp, FontWeight.SemiBold), color = accent,
                    modifier = Modifier.clickable {
                        // 名前の整え方 (空白・改行・上限) はコアの規則。空の段名はその位置の既定名にする。
                        val cleaned = tiers.mapIndexed { i, t ->
                            val normalized = tierListNormalizeTierLabel(t.label)
                                ?: tierListNewTier(i.toUInt(), emptyList()).label
                            t.copy(label = normalized)
                        }
                        onSave(tierListNormalizeTitle(title), cleaned)
                    }
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(DS.sp3)) {
                ImasText("表の名前", ImasTextRole.SECTION_LABEL, color = DS.ink3)
                OutlinedTextField(
                    value = title,
                    onValueChange = { v -> title = if (v.length > titleMax) v.take(titleMax) else v },
                    placeholder = { Text(board.defaultTitle) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                ImasText("画像の見出しになります。空にすると「${board.defaultTitle}」に戻ります。", ImasTextRole.META)
            }

            Column(verticalArrangement = Arrangement.spacedBy(DS.sp3)) {
                ImasText("段 (${tiers.size} / $maxTiers)", ImasTextRole.SECTION_LABEL, color = DS.ink3)
                tiers.forEachIndexed { i, tier ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.sp3)) {
                        Box(
                            modifier = Modifier.clickable {
                                tiers = tiers.toMutableList().also { it[i] = it[i].copy(colorSeed = tierListCycleColor(it[i].colorSeed)) }
                            }
                        ) {
                            ImasTierLabel(label = tier.label.ifEmpty { "?" }, seed = tier.colorSeed, style = ImasTierLabelStyle.SWATCH)
                        }
                        OutlinedTextField(
                            value = tier.label,
                            onValueChange = { v ->
                                val next = if (v.length > labelMax) v.take(labelMax) else v
                                tiers = tiers.toMutableList().also { it[i] = it[i].copy(label = next) }
                            },
                            placeholder = { Text("段の名前") },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(onClick = { tiers = tiers.toMutableList().also { it.removeAt(i); it.add(maxOf(0, i - 1), tier) } }, enabled = i > 0) {
                            Icon(Icons.Filled.ArrowUpward, "上へ", tint = if (i > 0) DS.ink2 else DS.ink3, modifier = Modifier.size(18.dp))
                        }
                        IconButton(
                            onClick = { tiers = tiers.toMutableList().also { it.removeAt(i); it.add(minOf(it.size, i + 1), tier) } },
                            enabled = i < tiers.size - 1
                        ) {
                            Icon(Icons.Filled.ArrowDownward, "下へ", tint = if (i < tiers.size - 1) DS.ink2 else DS.ink3, modifier = Modifier.size(18.dp))
                        }
                        IconButton(
                            onClick = { if (tiers.size > minTiers) tiers = tiers.toMutableList().also { it.removeAt(i) } },
                            enabled = tiers.size > minTiers
                        ) {
                            Icon(Icons.Filled.Delete, "削除", tint = if (tiers.size > minTiers) DS.warning else DS.ink3, modifier = Modifier.size(18.dp))
                        }
                    }
                }
                ImasButton(
                    title = "段を追加",
                    onClick = {
                        val newTier = tierListNewTier(tiers.size.toUInt(), tiers.map { it.colorSeed })
                        tiers = tiers + TierDef(label = newTier.label, colorSeed = newTier.colorSeed)
                    },
                    role = ImasButtonRole.SECONDARY,
                    size = ImasButtonSize.MEDIUM,
                    fillsWidth = true,
                    enabled = tiers.size < maxTiers
                )
                ImasText(
                    "色の札をタップすると色が変わります。名前は${labelMax}文字まで (「神」「沼」「好き」など)。上下の矢印で並べ替え、ゴミ箱で削除できます。" +
                        if (removedWithItems > 0) "\n削除する段にいる $removedWithItems 件は未分類に戻ります。" else "",
                    ImasTextRole.META
                )
            }
        }
    }
}
