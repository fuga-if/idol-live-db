package com.fugaif.imaslivedb.ui.sortmaker

import android.content.Context
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.games.GameBrandFilterGrid
import com.fugaif.imaslivedb.ui.songs.IdolMultiPickerPage
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
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

    /**
     * 始められるか。ティアー表は全部を 1 画面に並べる (遅延表示しない) ので、
     * [TIER_LIST_LIMIT] を超えたら無効にする (振り分ける手間からも現実的な上限)。
     */
    fun canStart(purpose: SortMakerPurpose): Boolean =
        !isLoading && candidates.size >= 2 && (purpose == SortMakerPurpose.SORT || candidates.size <= TIER_LIST_LIMIT)
}

/** ティアー表に並べられる上限。 */
const val TIER_LIST_LIMIT = 200

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
    val savedBoard = tierBoards[subject]
    var confirmRestart by rememberSaveable { mutableStateOf(false) }
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
                if (purpose == SortMakerPurpose.TIER && savedBoard != null) {
                    confirmRestart = true
                } else if (purpose == SortMakerPurpose.SORT && savedSession != null && (savedSession.isFinished || savedSession.answers.isNotEmpty())) {
                    confirmRestart = true
                } else if (purpose == SortMakerPurpose.TIER) {
                    onOpenTier(viewModel.startTier())
                } else {
                    onPlay(viewModel.start())
                }
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(DS.bg)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            HeaderCard(subject, purpose)
            if (purpose == SortMakerPurpose.SORT) {
                savedSession?.let { saved -> SavedCard(saved) { onPlay(saved) } }
            } else {
                savedBoard?.let { saved -> SavedBoardCard(saved) { onOpenTier(saved) } }
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

    if (confirmRestart) {
        AlertDialog(
            onDismissRequest = { confirmRestart = false },
            title = {
                Text(
                    when {
                        purpose == SortMakerPurpose.TIER -> "今のティアー表を消して作り直しますか？"
                        savedSession?.isFinished == true -> "前回の結果を消して新しく始めますか？"
                        else -> "前回の続きを消して最初から始めますか？"
                    }
                )
            },
            confirmButton = {
                Text(
                    "最初から始める",
                    color = DS.warning,
                    modifier = Modifier
                        .clickable {
                            confirmRestart = false
                            if (purpose == SortMakerPurpose.TIER) onOpenTier(viewModel.startTier()) else onPlay(viewModel.start())
                        }
                        .padding(12.dp)
                )
            },
            dismissButton = {
                Text("キャンセル", color = DS.ink2, modifier = Modifier.clickable { confirmRestart = false }.padding(12.dp))
            }
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
private fun HeaderCard(subject: SortMakerSubject, purpose: SortMakerPurpose) {
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(DS.surface).padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Box(
            modifier = Modifier.size(52.dp).clip(RoundedCornerShape(14.dp)).background(ImasTheme.derive(null, null, dark = true).accent),
            contentAlignment = Alignment.Center
        ) {
            Icon(if (purpose == SortMakerPurpose.SORT) Icons.Filled.SwapHoriz else Icons.Filled.Layers, null, tint = DS.surface)
        }
        Column {
            Text(
                if (purpose == SortMakerPurpose.SORT) "2つから好きな方を選ぶだけ" else "S〜Dの段に振り分ける",
                fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink
            )
            Text(
                if (purpose == SortMakerPurpose.SORT)
                    "対戦を重ねると、あなたの${if (subject == SortMakerSubject.SONG) "好きな曲" else "好きなアイドル"}ランキングができあがります。途中でやめても続きから遊べます。"
                else
                    "選んだ対象がぜんぶ未分類に並びます。ソートメーカーの結果からたたき台を作ることもできます。",
                fontSize = 12.sp, color = DS.ink3
            )
        }
    }
}

// MARK: - つづきから / 前回の結果

@Composable
private fun SavedCard(s: SortMakerSession, onOpen: () -> Unit) {
    val stateResult = remember(s) { s.replay() }
    Box(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(DS.surface)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(Modifier.weight(1f)) {
                Text(if (s.isFinished) "前回の結果" else "つづきから", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3)
                if (s.isFinished) {
                    Text(
                        s.topNames.firstOrNull()?.let { "1位 $it" } ?: s.scopeLabel,
                        fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink, maxLines = 1
                    )
                } else {
                    Text(
                        "${stateResult.progressPercent}% · ${stateResult.answered}戦 済み",
                        fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink
                    )
                }
                Text(s.scopeLabel, fontSize = 12.sp, color = DS.ink3, maxLines = 1)
            }
            val accent = ImasTheme.derive(null, null, dark = true).accent
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(accent)
                    .clickable(onClick = onOpen)
                    .padding(horizontal = 20.dp, vertical = 10.dp)
            ) {
                Text(if (s.isFinished) "見る" else "再開", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.surface)
            }
        }
        if (!s.isFinished) {
            LinearProgressIndicator(
                progress = { stateResult.progressPercent.toFloat() / 100f },
                modifier = Modifier.fillMaxWidth().height(3.dp).align(Alignment.BottomCenter),
                color = ImasTheme.derive(null, null, dark = true).accent,
                trackColor = DS.fill
            )
        }
    }
}

@Composable
private fun SavedBoardCard(b: TierListBoard, onOpen: () -> Unit) {
    val placed = b.itemIds.size - b.unplacedIds.size
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(DS.surface).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Column(Modifier.weight(1f)) {
            Text("つくりかけのティアー表", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3)
            Text("$placed / ${b.itemIds.size} 振り分け済み", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            Text(b.scopeLabel, fontSize = 12.sp, color = DS.ink3, maxLines = 1)
        }
        val accent = ImasTheme.derive(null, null, dark = true).accent
        Box(
            modifier = Modifier
                .clip(CircleShape)
                .background(accent)
                .clickable(onClick = onOpen)
                .padding(horizontal = 20.dp, vertical = 10.dp)
        ) {
            Text("開く", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.surface)
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
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            val options = SortMakerSongType.entries.toList()
            ImasSegmented(
                labels = options.map { it.label },
                selection = options.indexOf(state.scope.songType),
                onSelect = { onSongTypeChange(options[it]) }
            )

            Row(
                modifier = Modifier.fillMaxWidth().clickable(onClick = onOpenIdolPicker),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Column(Modifier.weight(1f)) {
                    Text("歌っているアイドルで絞る", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
                    Text(
                        if (state.scope.idolIds.isEmpty()) "指定なし" else state.pickedIdols.joinToString("、") { it.name },
                        fontSize = 12.sp, color = DS.ink3, maxLines = 1
                    )
                }
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = DS.ink3, modifier = Modifier.size(16.dp))
            }
            if (state.scope.idolIds.isNotEmpty()) {
                Text(
                    "アイドルの指定を外す", fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                    color = ImasTheme.derive(null, null, dark = true).accent,
                    modifier = Modifier.clickable(onClick = onClearIdols)
                )
            }

            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text("リミックス・別バージョンも入れる", fontSize = 15.sp, color = DS.ink, modifier = Modifier.weight(1f))
                Switch(checked = state.scope.includeRemixes, onCheckedChange = onRemixesChange)
            }
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
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(DS.surface).padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            Column {
                Text("対象", fontSize = 12.sp, color = DS.ink3)
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(if (state.isLoading) "…" else "${state.candidates.size}", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                    Text(subject.counter, fontSize = 12.sp, color = DS.ink3, modifier = Modifier.padding(start = 2.dp, bottom = 2.dp))
                }
            }
            if (purpose == SortMakerPurpose.SORT) {
                Column {
                    Text("対戦の目安", fontSize = 12.sp, color = DS.ink3)
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text(if (state.isLoading) "…" else "約${state.estimate}", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                        Text("戦", fontSize = 12.sp, color = DS.ink3, modifier = Modifier.padding(start = 2.dp, bottom = 2.dp))
                    }
                }
            }
        }
        val hint = hintFor(state, subject, purpose)
        if (!state.isLoading && hint != null) {
            Text(hint, fontSize = 12.sp, color = DS.ink3, modifier = Modifier.padding(horizontal = 4.dp))
        }
    }
}

/** 対戦が長すぎる / 少なすぎるときのひとこと。 */
private fun hintFor(state: SortMakerSetupUiState, subject: SortMakerSubject, purpose: SortMakerPurpose): String? {
    if (state.candidates.size < 2) return "2${subject.counter}以上になるように絞り込みをゆるめてください。"
    if (purpose == SortMakerPurpose.TIER) {
        if (state.candidates.size > TIER_LIST_LIMIT) {
            return "ティアー表は${TIER_LIST_LIMIT}${subject.counter}までです。ブランドや曲の種類で絞ってください。"
        }
        return if (state.candidates.size > 120) "数が多いと振り分けが大変です。ブランドなどで絞るのがおすすめです。" else null
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
    val accent = ImasTheme.derive(null, null, dark = true).accent
    Box(
        modifier = Modifier.fillMaxWidth().background(DS.bg).padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(if (canStart) accent else accent.copy(alpha = 0.4f))
                .clickable(enabled = canStart, onClick = onStart)
                .padding(vertical = 16.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                if (purpose == SortMakerPurpose.SORT) "はじめる" else "ティアー表をつくる",
                fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = DS.surface
            )
        }
    }
}

// MARK: - 部品

@Composable
private fun Section(title: String, note: String?, content: @Composable () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(DS.surface).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            if (note != null) Text(note, fontSize = 12.sp, color = DS.ink3)
        }
        content()
    }
}
