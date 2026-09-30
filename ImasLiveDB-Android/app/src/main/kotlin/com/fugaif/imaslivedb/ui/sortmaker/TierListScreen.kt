package com.fugaif.imaslivedb.ui.sortmaker

import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
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
import com.fugaif.imaslivedb.ui.components.ImasArtwork
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.theme.BrandColors
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
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
// タップで選ぶ → 下のバーで段を押す、が主な操作 (長押しドラッグは iOS のみ・Android は省略)。
// 1 回動かすたびに端末へ保存する (一覧から何枚でも開き直せる)。
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

    fun move(id: String, tierId: String?) {
        val current = _uiState.value ?: return
        val placements = current.board.placements.toMutableMap()
        if (tierId == null) placements.remove(id) else placements[id] = tierId
        commit(current.board.copy(placements = placements, savedAt = System.currentTimeMillis()))
    }

    fun resetToSuggested() {
        val current = _uiState.value ?: return
        val suggested = current.board.suggested ?: return
        commit(current.board.copy(placements = suggested, savedAt = System.currentTimeMillis()))
    }

    fun resetAllUnplaced() {
        val current = _uiState.value ?: return
        commit(current.board.copy(placements = emptyMap(), savedAt = System.currentTimeMillis()))
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
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            } else {
                Column(Modifier.fillMaxSize()) {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .verticalScroll(rememberScrollState())
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { showEdit = true },
                            verticalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(s.board.displayTitle, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                                Icon(Icons.Filled.Edit, contentDescription = "名前と段を編集", tint = DS.ink3, modifier = Modifier.size(15.dp))
                            }
                            Text(
                                "${s.board.scopeLabel} · ${s.board.placedCount} / ${s.board.itemIds.size} 振り分け済み",
                                fontSize = 12.sp, color = DS.ink3
                            )
                        }
                        // チップのタップ。何か選んでいて別のチップを押したら、そのチップの段
                        // (未分類なら未分類) へ移す (段の中はチップで埋まるので、行の余白を
                        // 押せと言っても押せない)。
                        val tapChip: (String) -> Unit = { id ->
                            val selected = selectedId
                            if (selected != null && selected != id) {
                                viewModel.move(selected, s.board.placements[id])
                                selectedId = null
                            } else {
                                selectedId = if (selectedId == id) null else id
                            }
                        }
                        Column(
                            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)),
                            verticalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            s.board.tiers.forEach { tier ->
                                TierRow(
                                    tier = tier,
                                    ids = s.board.idsInTier(tier.id),
                                    items = s.items,
                                    selectedId = selectedId,
                                    onSelect = tapChip,
                                    onItemDetail = onItemClick,
                                    onRowClick = { selectedId?.let { viewModel.move(it, tier.id); selectedId = null } }
                                )
                            }
                        }
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(DS.fill)
                                .clickable { showEdit = true }
                                .padding(vertical = 10.dp),
                            horizontalArrangement = Arrangement.Center,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Filled.Edit, null, tint = DS.ink2, modifier = Modifier.size(14.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("段を編集", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
                        }
                        UnplacedSection(
                            ids = s.board.unplacedIds,
                            items = s.items,
                            selectedId = selectedId,
                            hasSelection = selectedId != null,
                            onSelect = tapChip,
                            onItemDetail = onItemClick,
                            onRowClick = { selectedId?.let { viewModel.move(it, null); selectedId = null } }
                        )
                        Text(
                            "タップで選んで下のボタンで段を選ぶか、長押しでつかんで段まで運んでください。変えるたびに端末に保存されます。",
                            fontSize = 12.sp, color = DS.ink3
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
                            MoveBar(
                                title = item?.title ?: "",
                                tiers = s.board.tiers,
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
                    modifier = Modifier.clickable { confirmReset = false; viewModel.resetAllUnplaced() }.padding(12.dp)
                )
            },
            dismissButton = {
                Text("キャンセル", color = DS.ink2, modifier = Modifier.clickable { confirmReset = false }.padding(12.dp))
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

// MARK: - 段の行

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TierRow(
    tier: TierDef,
    ids: List<String>,
    items: Map<String, SortMakerItem>,
    selectedId: String?,
    onSelect: (String) -> Unit,
    onItemDetail: (SortMakerItem) -> Unit,
    onRowClick: () -> Unit
) {
    val theme = ImasTheme.derive(seed = tier.colorSeed, brand = null, dark = true)
    // 札を行の高さいっぱいに伸ばす (中身が 2 段に折り返しても色が途切れないように)。
    Row(modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
        Box(
            modifier = Modifier
                .width(60.dp)
                .fillMaxHeight()
                .background(theme.accent)
                // 段の札ボタンは何か選んでいるときだけ有効 (押しても行き先が無いため)。
                .clickable(enabled = selectedId != null, onClick = onRowClick),
            contentAlignment = Alignment.Center
        ) {
            TierLabelText(label = tier.label, large = 24.sp, small = 14.sp, color = theme.onAccent, modifier = Modifier.padding(horizontal = 4.dp))
        }
        Box(
            modifier = Modifier
                .weight(1f)
                .background(DS.surface)
                .clickable(onClick = onRowClick)
        ) {
            ItemsFlow(
                ids = ids,
                items = items,
                selectedId = selectedId,
                emptyText = if (selectedId != null) "ここへ移す" else null,
                onSelect = onSelect,
                onItemDetail = onItemDetail
            )
        }
    }
}

/** 段の名前。短い名前 (S / 神) は大きく、長い名前は小さくして 2 行まで。 */
@Composable
private fun TierLabelText(label: String, large: androidx.compose.ui.unit.TextUnit, small: androidx.compose.ui.unit.TextUnit, color: Color, modifier: Modifier = Modifier) {
    Text(
        label, fontSize = if (label.length <= 2) large else small, fontWeight = FontWeight.Black,
        color = color, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis,
        modifier = modifier
    )
}

@Composable
private fun UnplacedSection(
    ids: List<String>,
    items: Map<String, SortMakerItem>,
    selectedId: String?,
    hasSelection: Boolean,
    onSelect: (String) -> Unit,
    onItemDetail: (SortMakerItem) -> Unit,
    onRowClick: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("未分類", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            Spacer(Modifier.width(6.dp))
            Text("${ids.size}", fontSize = 12.sp, color = DS.ink3)
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(DS.surface)
                .clickable(onClick = onRowClick)
        ) {
            ItemsFlow(
                ids = ids,
                items = items,
                selectedId = selectedId,
                emptyText = if (ids.isEmpty()) "全部振り分けました" else if (hasSelection) "ここへ移す" else null,
                onSelect = onSelect,
                onItemDetail = onItemDetail
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
private fun ItemsFlow(
    ids: List<String>,
    items: Map<String, SortMakerItem>,
    selectedId: String?,
    emptyText: String?,
    onSelect: (String) -> Unit,
    onItemDetail: (SortMakerItem) -> Unit
) {
    if (ids.isEmpty()) {
        Box(Modifier.padding(16.dp)) {
            Text(emptyText ?: "", fontSize = 12.sp, color = DS.ink3)
        }
        return
    }
    FlowRow(
        modifier = Modifier.fillMaxWidth().padding(6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        ids.forEach { id ->
            val item = items[id]
            TierListChip(
                item = item,
                isSelected = selectedId == id,
                onClick = { onSelect(id) },
                onLongClick = { item?.let { onItemDetail(it) } }
            )
        }
    }
}

/** ティアー表の 1 枚 (ジャケ / アイコン + 名前)。 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TierListChip(
    item: SortMakerItem?,
    isSelected: Boolean,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null
) {
    val theme = ImasTheme.derive(item?.seed, BrandColors.hex(item?.brandId), dark = true)
    val scale by animateFloatAsState(if (isSelected) 1.06f else 1f, label = "tierChipScale")
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
        modifier = Modifier
            .scale(scale)
            .clip(RoundedCornerShape(10.dp))
            .background(if (isSelected) theme.tint else Color.Transparent)
            .then(if (isSelected) Modifier.border2(theme) else Modifier)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(3.dp)
    ) {
        when (item) {
            is SortMakerItem.SongItem -> ImasArtwork(title = item.song.title, imageUrl = item.song.artworkUrl, size = 52.dp)
            is SortMakerItem.IdolItem -> ImasAvatar(label = item.idol.shortName, seed = item.idol.color, brand = item.idol.brandId, size = 52.dp, entityId = item.idol.id)
            null -> ImasArtwork(title = "?", size = 52.dp)
        }
        Text(
            item?.title ?: "", fontSize = 10.sp, color = DS.ink2, maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 60.dp)
        )
    }
}

private fun Modifier.border2(theme: ImasTheme): Modifier =
    this.border(2.5.dp, theme.accent, RoundedCornerShape(10.dp))

// MARK: - 移すバー

@Composable
private fun MoveBar(
    title: String,
    tiers: List<TierDef>,
    onCancel: () -> Unit,
    onMove: (String) -> Unit,
    onUnplace: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth().background(DS.surface).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "「$title」をどこへ？", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f)
            )
            Text("やめる", fontSize = 15.sp, color = DS.ink2, modifier = Modifier.clickable(onClick = onCancel).padding(4.dp))
        }
        // 段は最大 10。6 列で折り返す (1 行に詰めると押せない幅になる)。
        val columns = minOf(6, tiers.size + 1)
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.fillMaxWidth().height((44.dp + 6.dp) * ((tiers.size) / columns + 1))
        ) {
            items(tiers) { tier ->
                val theme = ImasTheme.derive(seed = tier.colorSeed, brand = null, dark = true)
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(44.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(theme.accent)
                        .clickable { onMove(tier.id) },
                    contentAlignment = Alignment.Center
                ) {
                    TierLabelText(label = tier.label, large = 18.sp, small = 11.sp, color = theme.onAccent, modifier = Modifier.padding(horizontal = 2.dp))
                }
            }
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(44.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(DS.fill)
                        .clickable(onClick = onUnplace),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Filled.Inbox, contentDescription = "未分類へ", tint = DS.ink2, modifier = Modifier.size(18.dp))
                }
            }
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
    val accent = ImasTheme.derive(null, null, dark = true).accent

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
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                Text("キャンセル", fontSize = 15.sp, color = DS.ink2, modifier = Modifier.clickable(onClick = onDismiss))
                Spacer(Modifier.weight(1f))
                Text("名前と段を編集", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                Spacer(Modifier.weight(1f))
                Text(
                    "保存", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = accent,
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

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("表の名前", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = DS.ink3)
                OutlinedTextField(
                    value = title,
                    onValueChange = { v -> title = if (v.length > titleMax) v.take(titleMax) else v },
                    placeholder = { Text(board.defaultTitle) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Text("画像の見出しになります。空にすると「${board.defaultTitle}」に戻ります。", fontSize = 12.sp, color = DS.ink3)
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("段 (${tiers.size} / $maxTiers)", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = DS.ink3)
                tiers.forEachIndexed { i, tier ->
                    val theme = ImasTheme.derive(seed = tier.colorSeed, brand = null, dark = true)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(
                            modifier = Modifier
                                .clickable { tiers = tiers.toMutableList().also { it[i] = it[i].copy(colorSeed = tierListCycleColor(it[i].colorSeed)) } }
                                .width(48.dp)
                                .height(34.dp)
                                .clip(RoundedCornerShape(8.dp))
                                .background(theme.accent),
                            contentAlignment = Alignment.Center
                        ) {
                            TierLabelText(label = tier.label.ifEmpty { "?" }, large = 16.sp, small = 10.sp, color = theme.onAccent)
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
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(if (tiers.size < maxTiers) DS.fill else DS.fill.copy(alpha = 0.4f))
                        .clickable(enabled = tiers.size < maxTiers) {
                            val newTier = tierListNewTier(tiers.size.toUInt(), tiers.map { it.colorSeed })
                            tiers = tiers + TierDef(label = newTier.label, colorSeed = newTier.colorSeed)
                        }
                        .padding(vertical = 12.dp),
                    horizontalArrangement = Arrangement.Center
                ) {
                    Text(
                        "段を追加", fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                        color = if (tiers.size < maxTiers) DS.ink else DS.ink3
                    )
                }
                Text(
                    "色の札をタップすると色が変わります。名前は${labelMax}文字まで (「神」「沼」「好き」など)。上下の矢印で並べ替え、ゴミ箱で削除できます。" +
                        if (removedWithItems > 0) "\n削除する段にいる $removedWithItems 件は未分類に戻ります。" else "",
                    fontSize = 12.sp, color = DS.ink3
                )
            }
        }
    }
}
