package com.fugaif.imaslivedb.ui.sortmaker

import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.IntrinsicSize
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
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import com.fugaif.imaslivedb.data.games.TierListBoard
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasArtwork
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.TierListTier
import uniffi.imas_core.tierListNormalizeTierLabel
import uniffi.imas_core.tierListNormalizeTitle
import uniffi.imas_core.tierListTierLabelMaxChars
import uniffi.imas_core.tierListTiers
import uniffi.imas_core.tierListTitleMaxChars

// =============================================================================
// ティアー表の編集画面。iOS TierListView.swift の移植。
// タップで選ぶ → 下のバーで段を押す、が主な操作 (長押しドラッグは iOS のみ・Android は省略)。
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

    fun move(id: String, tier: Int?) {
        val current = _uiState.value ?: return
        val placements = current.board.placements.toMutableMap()
        if (tier == null) placements.remove(id) else placements[id] = tier
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

    /** 表の名前・段の名前の上書きを保存する。 */
    fun updateNames(title: String?, tierLabels: List<String?>?) {
        val current = _uiState.value ?: return
        commit(current.board.copy(title = title, tierLabels = tierLabels, savedAt = System.currentTimeMillis()))
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
    viewModel: TierListViewModel = viewModel(key = "tier_list_${board.subject.key}")
) {
    val context = LocalContext.current
    LaunchedEffect(board.subject) { viewModel.load(context, board) }

    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    var showMenu by remember { mutableStateOf(false) }
    var confirmReset by rememberSaveable { mutableStateOf(false) }
    var showShare by rememberSaveable { mutableStateOf(false) }
    var showRename by rememberSaveable { mutableStateOf(false) }
    val tiers = remember { tierListTiers() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(board.subject.tierTitle, fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") } },
                actions = {
                    IconButton(onClick = { showShare = true }) { Icon(Icons.Filled.Share, "シェア") }
                    IconButton(onClick = { showMenu = true }) { Icon(Icons.Filled.MoreVert, "その他") }
                    DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                        DropdownMenuItem(
                            text = { Text("名前を変える") },
                            leadingIcon = { Icon(Icons.Filled.Edit, null) },
                            onClick = { showMenu = false; showRename = true }
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
                // 段の名前の上書きを反映した段の並び (色はコアの既定のまま)。
                val displayTiers = remember(tiers, s.board.tierLabels) {
                    tiers.mapIndexed { i, t -> t.copy(label = s.board.label(ofTier = i, default = t.label)) }
                }
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
                                .clickable { showRename = true },
                            verticalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(s.board.displayTitle, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                                Icon(Icons.Filled.Edit, contentDescription = "名前を変える", tint = DS.ink3, modifier = Modifier.size(15.dp))
                            }
                            Text(s.board.scopeLabel, fontSize = 12.sp, color = DS.ink3)
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
                            displayTiers.forEachIndexed { index, tier ->
                                TierRow(
                                    tier = tier,
                                    ids = s.board.idsInTier(index),
                                    items = s.items,
                                    selectedId = selectedId,
                                    onSelect = tapChip,
                                    onItemDetail = onItemClick,
                                    onRowClick = { selectedId?.let { viewModel.move(it, index); selectedId = null } }
                                )
                            }
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
                            "タップで選んで下のボタンで段を選んでください。",
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
                                tiers = displayTiers,
                                onCancel = { selectedId = null },
                                onMove = { tierIndex -> viewModel.move(id, tierIndex); selectedId = null },
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

    if (showShare) {
        state?.let { s ->
            val displayTiers = tiers.mapIndexed { i, t -> t.copy(label = s.board.label(ofTier = i, default = t.label)) }
            TierListShareSheet(
                title = s.board.displayTitle,
                scopeLabel = s.board.scopeLabel,
                tiers = displayTiers,
                rowsByTier = displayTiers.indices.map { index -> s.board.idsInTier(index).mapNotNull { s.items[it] } },
                onDismiss = { showShare = false }
            )
        }
    }

    if (showRename) {
        state?.let { s ->
            TierListRenameSheet(
                board = s.board,
                tiers = tiers,
                onDismiss = { showRename = false },
                onSave = { title, labels -> viewModel.updateNames(title, labels); showRename = false }
            )
        }
    }
}

// MARK: - 段の行

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TierRow(
    tier: TierListTier,
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
                .width(56.dp)
                .fillMaxHeight()
                .background(theme.accent)
                // 段の札ボタンは何か選んでいるときだけ有効 (押しても行き先が無いため)。
                .clickable(enabled = selectedId != null, onClick = onRowClick),
            contentAlignment = Alignment.Center
        ) {
            Text(
                tier.label, fontSize = if (tier.label.length <= 2) 24.sp else 14.sp, fontWeight = FontWeight.Black,
                color = theme.onAccent, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(horizontal = 4.dp)
            )
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
    val theme = ImasTheme.derive(item?.seed, com.fugaif.imaslivedb.ui.theme.BrandColors.hex(item?.brandId), dark = true)
    val scale by animateFloatAsState(if (isSelected) 1.06f else 1f, label = "tierChipScale")
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
        modifier = Modifier
            .scale(scale)
            .clip(RoundedCornerShape(10.dp))
            .background(if (isSelected) theme.tint else androidx.compose.ui.graphics.Color.Transparent)
            .then(
                if (isSelected) Modifier.border2(theme)
                else Modifier
            )
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
    tiers: List<TierListTier>,
    onCancel: () -> Unit,
    onMove: (Int) -> Unit,
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
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            tiers.forEachIndexed { index, tier ->
                val theme = ImasTheme.derive(seed = tier.colorSeed, brand = null, dark = true)
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(44.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(theme.accent)
                        .clickable { onMove(index) },
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        tier.label, fontSize = if (tier.label.length <= 2) 18.sp else 12.sp, fontWeight = FontWeight.Black,
                        color = theme.onAccent, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = 2.dp)
                    )
                }
            }
            Box(
                modifier = Modifier
                    .weight(1f)
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

// MARK: - 名前を変えるシート

/** 表の名前と段の名前を変えるシート。空にすると既定の名前に戻る。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TierListRenameSheet(
    board: TierListBoard,
    tiers: List<TierListTier>,
    onDismiss: () -> Unit,
    onSave: (title: String?, labels: List<String?>?) -> Unit
) {
    val titleMax = remember { tierListTitleMaxChars().toInt() }
    val labelMax = remember { tierListTierLabelMaxChars().toInt() }
    var title by rememberSaveable { mutableStateOf(board.title ?: "") }
    var labels by rememberSaveable { mutableStateOf(tiers.indices.map { i -> board.tierLabels?.getOrNull(i) ?: "" }) }
    val accent = ImasTheme.derive(null, null, dark = true).accent

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
                Text("名前を変える", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                Spacer(Modifier.weight(1f))
                Text(
                    "保存", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = accent,
                    modifier = Modifier.clickable {
                        // 整え方 (空白・改行・上限) はコアの規則で揃える。
                        val normalizedLabels = labels.map { tierListNormalizeTierLabel(it) }
                        onSave(
                            tierListNormalizeTitle(title),
                            if (normalizedLabels.all { it == null }) null else normalizedLabels
                        )
                    }
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("表の名前", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = DS.ink3)
                OutlinedTextField(
                    value = title,
                    onValueChange = { v -> title = if (v.length > titleMax) v.take(titleMax) else v },
                    placeholder = { Text(board.displayTitle(ignoringCustom = true)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    "シェア画像の見出しになります。空にすると「${board.displayTitle(ignoringCustom = true)}」に戻ります。",
                    fontSize = 12.sp, color = DS.ink3
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("段の名前", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = DS.ink3)
                tiers.forEachIndexed { i, tier ->
                    val theme = ImasTheme.derive(seed = tier.colorSeed, brand = null, dark = true)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(
                            modifier = Modifier
                                .width(44.dp)
                                .height(32.dp)
                                .clip(RoundedCornerShape(6.dp))
                                .background(theme.accent),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                labels[i].ifEmpty { tier.label }, fontSize = 14.sp, fontWeight = FontWeight.Black,
                                color = theme.onAccent, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.padding(horizontal = 2.dp)
                            )
                        }
                        OutlinedTextField(
                            value = labels[i],
                            onValueChange = { v ->
                                val next = if (v.length > labelMax) v.take(labelMax) else v
                                labels = labels.toMutableList().also { it[i] = next }
                            },
                            placeholder = { Text(tier.label) },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
                Text(
                    "${labelMax}文字まで。「神」「沼」「好き」のように自由に付けられます。空にすると S〜D に戻ります。",
                    fontSize = 12.sp, color = DS.ink3
                )
            }
        }
    }
}
