package com.fugaif.imaslivedb.ui.sortmaker

import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.games.SortMakerDepth
import com.fugaif.imaslivedb.data.games.SortMakerPurpose
import com.fugaif.imaslivedb.data.games.SortMakerSession
import com.fugaif.imaslivedb.data.games.SortMakerSubject
import com.fugaif.imaslivedb.data.games.TierListBoard
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasCardListStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasConfirmDestructive
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasProgressBar
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasSetupHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasStatGrid
import com.fugaif.imaslivedb.ui.designsystem.ImasStatTile
import com.fugaif.imaslivedb.ui.designsystem.ImasToggleRow
import com.fugaif.imaslivedb.ui.games.GameBrandFilterGrid
import com.fugaif.imaslivedb.ui.songs.IdolMultiPickerPage
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.quizBrandIdsDecode
import uniffi.imas_core.quizBrandIdsEncode
import uniffi.imas_core.sortMakerEstimateTotal

// =============================================================================
// ソートメーカーの設定画面。iOS SortMakerSetupView.swift の移植。
// 対象 (ブランド・曲の種類・歌唱アイドル) と決め方 (ベスト10 / 全順位) を選んで始める。
// 途中のセッションがあれば「つづきから」を先頭に出す。
// =============================================================================

data class SortMakerSetupUiState(
    val brands: List<Brand> = emptyList(),
    val scope: SortMakerScope = SortMakerScope(),
    val depth: SortMakerDepth = SortMakerDepth.TOP10,
    val pickedIdols: List<Idol> = emptyList(),
    val allIdolsForPicker: List<Idol> = emptyList(),
    val candidates: List<SortMakerItem> = emptyList(),
    val isLoading: Boolean = true
) {
    val estimate: Int get() = sortMakerEstimateTotal(candidates.size.toUInt(), depth.rawValue.toUInt()).toInt()

    /** 始められるか (2 件以上)。ティアー表は全曲でも作れる (未分類は絞り込みと遅延表示)。 */
    fun canStart(purpose: SortMakerPurpose): Boolean =
        !isLoading && candidates.size >= 2
}

/** ティアー表に並べられる上限。 */

class SortMakerSetupViewModel : ViewModel() {

    private lateinit var subject: SortMakerSubject
    private var purpose: SortMakerPurpose = SortMakerPurpose.SORT
    private var appModule: AppModule? = null
    private var appContext: Context? = null

    private val _uiState = MutableStateFlow(SortMakerSetupUiState())
    val uiState: StateFlow<SortMakerSetupUiState> = _uiState.asStateFlow()

    /** 条件が変わっている間に読み込みが終わっても、古い件数で上書きしない。 */
    private var loadRequest = 0

    fun load(context: Context, subject: SortMakerSubject, purpose: SortMakerPurpose = SortMakerPurpose.SORT) {
        this.subject = subject
        this.purpose = purpose
        val module = AppModule.from(context)
        appModule = module
        appContext = context.applicationContext
        val prefs = prefs()
        val savedBrandIds = quizBrandIdsDecode(prefs?.getString(keyBrandIds(subject), "") ?: "").toSet()
        val savedDepth = SortMakerDepth.fromRawValue(prefs?.getInt(keyDepth(subject), SortMakerDepth.TOP10.rawValue) ?: SortMakerDepth.TOP10.rawValue)
        _uiState.value = SortMakerSetupUiState(
            scope = SortMakerScope(brandIds = savedBrandIds),
            depth = savedDepth
        )
        viewModelScope.launch {
            val brands = module.statsRepository.fetchBrands()
            val allIdols = if (subject == SortMakerSubject.SONG) module.idolRepository.fetchIdolsForList(null) else emptyList()
            _uiState.value = _uiState.value.copy(brands = brands, allIdolsForPicker = allIdols)
            reload()
        }
    }

    fun updateScope(newScope: SortMakerScope) {
        val old = _uiState.value.scope
        _uiState.value = _uiState.value.copy(scope = newScope)
        if (old.brandIds != newScope.brandIds) {
            prefs()?.edit()?.putString(keyBrandIds(subject), quizBrandIdsEncode(newScope.brandIds.toList()))?.apply()
        }
        viewModelScope.launch { reload() }
    }

    fun setPickedIdols(idols: List<Idol>) {
        _uiState.value = _uiState.value.copy(pickedIdols = idols)
    }

    fun setDepth(depth: SortMakerDepth) {
        _uiState.value = _uiState.value.copy(depth = depth)
        prefs()?.edit()?.putInt(keyDepth(subject), depth.rawValue)?.apply()
    }

    /** 前回の続きを消して最初から始める。 */
    fun start(): SortMakerSession {
        val state = _uiState.value
        val session = SortMakerSession(
            subject = subject,
            itemIds = state.candidates.map { it.id },
            seed = kotlin.random.Random.nextLong().toULong(),
            topK = state.depth.rawValue,
            scopeLabel = scopeLabel(state),
            answers = ""
        )
        appModule?.sortMakerStore?.save(session)
        return session
    }

    /** ティアー表を新しく作って開く。 */
    fun startTier(): TierListBoard {
        val state = _uiState.value
        val board = TierListBoard(
            subject = subject,
            itemIds = state.candidates.map { it.id },
            placements = emptyMap(),
            scopeLabel = scopeLabel(state)
        )
        appModule?.tierListStore?.save(board)
        return board
    }

    fun scopeLabel(state: SortMakerSetupUiState = _uiState.value): String {
        val parts = mutableListOf<String>()
        val names = state.brands.filter { state.scope.brandIds.contains(it.id) }.map { it.shortName }
        parts.add(if (names.isEmpty()) "全ブランド" else names.joinToString("・"))
        if (subject == SortMakerSubject.SONG) {
            if (state.scope.songType != SortMakerSongType.ANY) parts.add(state.scope.songType.label)
            if (state.pickedIdols.isNotEmpty()) {
                parts.add(
                    if (state.pickedIdols.size <= 2) state.pickedIdols.joinToString("・") { it.name }
                    else "${state.pickedIdols.first().name}ほか"
                )
            }
        }
        val base = parts.joinToString("・") + " ${state.candidates.size}${subject.counter}"
        if (purpose != SortMakerPurpose.SORT) return base
        return base + "から" + state.depth.label
    }

    private suspend fun reload() {
        val module = appModule ?: return
        val requestId = ++loadRequest
        _uiState.value = _uiState.value.copy(isLoading = true)
        val requestedScope = _uiState.value.scope
        val loaded = SortMakerCandidates.load(subject, requestedScope, module.songRepository, module.idolRepository)
        // 読んでいる間に条件が変わっていたら捨てる (古い件数で上書きしない)。
        if (requestId != loadRequest) return
        _uiState.value = _uiState.value.copy(candidates = loaded, isLoading = false)
    }

    private fun prefs(): android.content.SharedPreferences? =
        appContext?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    companion object {
        private const val PREFS_NAME = "sort_maker_setup_prefs"
        private fun keyBrandIds(subject: SortMakerSubject) = "sortMaker.${subject.key}.brandIds"
        private fun keyDepth(subject: SortMakerSubject) = "sortMaker.${subject.key}.depth"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SortMakerSetupScreen(
    subject: SortMakerSubject,
    purpose: SortMakerPurpose = SortMakerPurpose.SORT,
    onBack: () -> Unit,
    onPlay: (SortMakerSession) -> Unit,
    onOpenTier: (TierListBoard) -> Unit = {},
    viewModel: SortMakerSetupViewModel = viewModel(key = "sort_maker_setup_${purpose}_${subject.key}")
) {
    val context = LocalContext.current
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    // 「つづきから」の有無は SortMakerStore/TierListStore を直接購読する (ViewModel の uiState は
    // load() 時点のスナップショットで、Play/編集画面から戻ってきても古いままになるため)。
    val sortMakerSessions by AppModule.from(context).sortMakerStore.sessions.collectAsStateWithLifecycle()
    val tierBoards by AppModule.from(context).tierListStore.boards.collectAsStateWithLifecycle()
    val savedSession = sortMakerSessions[subject]
    val boardsForSubject = remember(tierBoards, subject) { tierBoards.filter { it.subject == subject } }
    var confirmRestart by rememberSaveable { mutableStateOf(false) }
    var deletingBoard by remember { mutableStateOf<TierListBoard?>(null) }
    var showIdolPicker by rememberSaveable { mutableStateOf(false) }

    androidx.compose.runtime.LaunchedEffect(subject, purpose) {
        viewModel.load(context, subject, purpose)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (purpose == SortMakerPurpose.SORT) subject.title else subject.tierTitle, fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") } }
            )
        },
        bottomBar = {
            StartBar(canStart = state.canStart(purpose), purpose = purpose) {
                if (purpose == SortMakerPurpose.SORT && savedSession != null && (savedSession.isFinished || savedSession.answers.isNotEmpty())) {
                    confirmRestart = true
                } else if (purpose == SortMakerPurpose.TIER) {
                    onOpenTier(viewModel.startTier())
                } else {
                    onPlay(viewModel.start())
                }
            }
        }
    ) { padding ->
        ImasPage(modifier = Modifier.padding(padding)) {
            Header(subject, purpose)
            if (purpose == SortMakerPurpose.SORT) {
                savedSession?.let { saved -> SavedCard(saved) { onPlay(saved) } }
            } else if (boardsForSubject.isNotEmpty()) {
                SavedBoardsSection(boards = boardsForSubject, onOpen = { onOpenTier(it) }, onRequestDelete = { deletingBoard = it })
            }
            BrandSection(state) { viewModel.updateScope(state.scope.copy(brandIds = it)) }
            if (subject == SortMakerSubject.SONG) {
                SongSection(
                    state = state,
                    onSongTypeChange = { viewModel.updateScope(state.scope.copy(songType = it)) },
                    onRemixesChange = { viewModel.updateScope(state.scope.copy(includeRemixes = it)) },
                    onOpenIdolPicker = { showIdolPicker = true },
                    onClearIdols = {
                        viewModel.updateScope(state.scope.copy(idolIds = emptySet()))
                        viewModel.setPickedIdols(emptyList())
                    }
                )
            }
            if (purpose == SortMakerPurpose.SORT) {
                DepthSection(state.depth) { viewModel.setDepth(it) }
            }
            Summary(state, subject, purpose)
        }
    }

    ImasConfirmDestructive(
        title = if (savedSession?.isFinished == true) "前回の結果を消して新しく始めますか？" else "前回の続きを消して最初から始めますか？",
        isPresented = confirmRestart,
        onDismiss = { confirmRestart = false },
        onConfirm = { onPlay(viewModel.start()) },
        actionTitle = "最初から始める"
    )

    deletingBoard?.let { board ->
        ImasConfirmDestructive(
            title = "「${board.displayTitle}」を削除しますか？",
            isPresented = true,
            onDismiss = { deletingBoard = null },
            onConfirm = { AppModule.from(context).tierListStore.delete(board.id) }
        )
    }

    if (showIdolPicker) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        val scope = rememberCoroutineScopeCompat()
        ModalBottomSheet(onDismissRequest = { showIdolPicker = false }, sheetState = sheetState, containerColor = DS.bg) {
            IdolMultiPickerPage(
                idols = state.allIdolsForPicker,
                brands = state.brands,
                selected = state.scope.idolIds,
                onBack = { showIdolPicker = false },
                onToggle = { id ->
                    val updated = if (state.scope.idolIds.contains(id)) state.scope.idolIds - id else state.scope.idolIds + id
                    viewModel.updateScope(state.scope.copy(idolIds = updated))
                    viewModel.setPickedIdols(state.allIdolsForPicker.filter { updated.contains(it.id) })
                },
                onClear = {
                    viewModel.updateScope(state.scope.copy(idolIds = emptySet()))
                    viewModel.setPickedIdols(emptyList())
                }
            )
        }
    }
}

@Composable
private fun rememberCoroutineScopeCompat() = androidx.compose.runtime.rememberCoroutineScope()

// MARK: - ヘッダ

@Composable
private fun Header(subject: SortMakerSubject, purpose: SortMakerPurpose) {
    ImasSetupHeader(
        icon = if (purpose == SortMakerPurpose.SORT) Icons.Filled.SwapHoriz else Icons.Filled.Layers,
        title = if (purpose == SortMakerPurpose.SORT) "2つから好きな方を選ぶだけ" else "段に振り分けて1枚の画像に",
        message = if (purpose == SortMakerPurpose.SORT)
            "対戦を重ねると、あなたの${if (subject == SortMakerSubject.SONG) "好きな曲" else "好きなアイドル"}ランキングができあがります。途中でやめても続きから遊べます。"
        else
            "選んだ対象がぜんぶ未分類に並びます。段の数・名前・色は自由に変えられ、何枚でも端末に保存できます。"
    )
}

// MARK: - つづきから / 前回の結果

@Composable
private fun SavedCard(s: SortMakerSession, onOpen: () -> Unit) {
    val stateResult = remember(s) { s.replay() }
    ImasCard {
        Row(horizontalArrangement = Arrangement.spacedBy(DS.sp4), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DS.sp1)) {
                ImasText(if (s.isFinished) "前回の結果" else "つづきから", ImasTextRole.META)
                if (s.isFinished) {
                    ImasText(s.topNames.firstOrNull()?.let { "1位 $it" } ?: s.scopeLabel, ImasTextRole.ROW_TITLE, maxLines = 1)
                } else {
                    ImasText("${stateResult.progressPercent}% · ${stateResult.answered}戦 済み", ImasTextRole.ROW_TITLE)
                }
                ImasText(s.scopeLabel, ImasTextRole.META, maxLines = 1)
                if (!s.isFinished) {
                    ImasProgressBar(fraction = stateResult.progressPercent.toDouble() / 100, modifier = Modifier.padding(top = DS.Space.gapTight))
                }
            }
            ImasButton(title = if (s.isFinished) "見る" else "再開", onClick = onOpen, role = ImasButtonRole.PRIMARY, size = ImasButtonSize.MEDIUM)
        }
    }
}

/** 端末に保存してあるティアー表 (新しく触ったものから)。タップで開き、長押しで削除。 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SavedBoardsSection(boards: List<TierListBoard>, onOpen: (TierListBoard) -> Unit, onRequestDelete: (TierListBoard) -> Unit) {
    val fmt = remember { java.text.SimpleDateFormat("yyyy/MM/dd HH:mm", java.util.Locale.getDefault()) }
    ImasSection(title = "保存したティアー表", count = "${boards.size}", footer = "長押しで削除できます。") {
        ImasCardList(style = ImasCardListStyle.PANEL) {
            boards.forEachIndexed { i, b ->
                if (i > 0) ImasRowDivider(inset = DS.sp4)
                ImasRow(
                    title = b.displayTitle,
                    subtitle = "${b.placedCount} / ${b.itemIds.size} 振り分け済み · ${fmt.format(java.util.Date(b.savedAt))}",
                    trailing = ImasRowTrailing.Chevron,
                    modifier = Modifier.combinedClickable(onClick = { onOpen(b) }, onLongClick = { onRequestDelete(b) })
                )
            }
        }
    }
}

// MARK: - ブランド

@Composable
private fun BrandSection(state: SortMakerSetupUiState, onChange: (Set<String>) -> Unit) {
    Section(title = "ブランド", note = "複数選択可 · 空=全ブランド") {
        GameBrandFilterGrid(
            brands = state.brands,
            selectedBrandIds = state.scope.brandIds,
            onToggle = { id ->
                val updated = if (state.scope.brandIds.contains(id)) state.scope.brandIds - id else state.scope.brandIds + id
                onChange(updated)
            },
            onClearAll = { onChange(emptySet()) }
        )
    }
}

// MARK: - 曲の絞り込み

@Composable
private fun SongSection(
    state: SortMakerSetupUiState,
    onSongTypeChange: (SortMakerSongType) -> Unit,
    onRemixesChange: (Boolean) -> Unit,
    onOpenIdolPicker: () -> Unit,
    onClearIdols: () -> Unit
) {
    Section(title = "曲の種類", note = null) {
        Column(verticalArrangement = Arrangement.spacedBy(DS.sp5)) {
            val options = SortMakerSongType.entries.toList()
            ImasSegmented(
                labels = options.map { it.label },
                selection = options.indexOf(state.scope.songType),
                onSelect = { onSongTypeChange(options[it]) }
            )

            ImasNavRow(
                title = "歌っているアイドルで絞る",
                subtitle = if (state.scope.idolIds.isEmpty()) "指定なし" else state.pickedIdols.joinToString("、") { it.name },
                onClick = onOpenIdolPicker
            )
            if (state.scope.idolIds.isNotEmpty()) {
                ImasButton(title = "アイドルの指定を外す", onClick = onClearIdols, role = ImasButtonRole.PLAIN, size = ImasButtonSize.SMALL)
            }

            ImasToggleRow(title = "リミックス・別バージョンも入れる", isOn = state.scope.includeRemixes, onCheckedChange = onRemixesChange)
        }
    }
}

// MARK: - 決める順位

@Composable
private fun DepthSection(depth: SortMakerDepth, onChange: (SortMakerDepth) -> Unit) {
    Section(
        title = "決める順位",
        note = if (depth == SortMakerDepth.TOP10) "上位だけ決めるので対戦が少なく済みます" else "全部に順位をつけます"
    ) {
        val options = SortMakerDepth.entries.toList()
        ImasSegmented(
            labels = options.map { it.label },
            selection = options.indexOf(depth),
            onSelect = { onChange(options[it]) }
        )
    }
}

// MARK: - 件数と見積り

@Composable
private fun Summary(state: SortMakerSetupUiState, subject: SortMakerSubject, purpose: SortMakerPurpose) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.note)) {
        ImasStatGrid(columns = if (purpose == SortMakerPurpose.SORT) 2 else 1) {
            ImasStatTile(icon = null, value = if (state.isLoading) "…" else "${state.candidates.size}", label = "対象", unit = subject.counter)
            if (purpose == SortMakerPurpose.SORT) {
                ImasStatTile(icon = null, value = if (state.isLoading) "…" else "約${state.estimate}", label = "対戦の目安", unit = "戦")
            }
        }
        val hint = hintFor(state, subject, purpose)
        if (!state.isLoading && hint != null) {
            ImasNote(hint)
        }
    }
}

/** 対戦が長すぎる / 少なすぎるときのひとこと。 */
private fun hintFor(state: SortMakerSetupUiState, subject: SortMakerSubject, purpose: SortMakerPurpose): String? {
    if (state.candidates.size < 2) return "2${subject.counter}以上になるように絞り込みをゆるめてください。"
    if (purpose == SortMakerPurpose.TIER) {
        return if (state.candidates.size > 200) "未分類は名前で絞り込めるので、全${subject.counter}からでも探して振り分けられます。" else null
    }
    if (state.estimate > 600) {
        return if (state.depth == SortMakerDepth.ALL) {
            "かなり長くなります。ブランドを絞るか「ベスト10」がおすすめです。途中保存されるので少しずつでも大丈夫です。"
        } else {
            "長めです。途中保存されるので、少しずつ進めても大丈夫です。"
        }
    }
    return null
}

// MARK: - 開始

@Composable
private fun StartBar(canStart: Boolean, purpose: SortMakerPurpose, onStart: () -> Unit) {
    ImasButton(
        title = if (purpose == SortMakerPurpose.SORT) "はじめる" else "ティアー表をつくる",
        onClick = onStart,
        role = ImasButtonRole.PRIMARY,
        size = ImasButtonSize.LARGE,
        enabled = canStart,
        modifier = Modifier
            .padding(horizontal = DS.sp5, vertical = DS.sp3)
            .background(DS.bg)
    )
}

// MARK: - 部品

@Composable
private fun Section(title: String, note: String?, content: @Composable () -> Unit) {
    ImasCard {
        Column(verticalArrangement = Arrangement.spacedBy(DS.sp4)) {
            Column(verticalArrangement = Arrangement.spacedBy(DS.sp1)) {
                ImasText(title, ImasTextRole.VALUE)
                if (note != null) ImasNote(note)
            }
            content()
        }
    }
}
