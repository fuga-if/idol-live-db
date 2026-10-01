package com.fugaif.imaslivedb.ui.sortmaker

import android.content.Context
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Equalizer
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
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
import com.fugaif.imaslivedb.data.games.SortMakerSession
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.ui.designsystem.ImasArtwork
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasTheme
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.SortMakerChoice
import uniffi.imas_core.SortMakerState

// =============================================================================
// ソートメーカーの対戦進行。iOS SortMakerPlayView.swift の移植。
// 答えるたびにコアで状態を作り直し、保存する。終わったら同じ画面のまま結果に切り替わる
// (戻るで対戦に戻らないように、result への遷移は行わずここで表示を差し替える)。
// =============================================================================

data class SortMakerPlayUiState(
    val session: SortMakerSession,
    val coreState: SortMakerState,
    /** `session.itemIds` と同じ並び。消えた曲・アイドルは null。 */
    val items: List<SortMakerItem?> = emptyList(),
    val isLoaded: Boolean = false,
    /**
     * 画面に出す進み具合と残り。ベスト10モードは K 位に勝った新顔の探索が見積りに
     * 後から乗るので、コアの値は 1 戦ごとに少し戻ることがある。表示だけは戻さない
     * (1 つ戻る / 読み込み直しで取り直す)。
     */
    val shownPercent: UInt = 0u,
    val shownRemaining: UInt = 0u,
    /** 終わった (isFinished が false→true になった) たびに増える。触覚フィードバックの一度きりの合図。 */
    val finishEventId: Int = 0
) {
    /** 保存した対象のうち、マスタから消えて引けなかった件数。 */
    val missingCount: Int get() = items.count { it == null }
}

class SortMakerPlayViewModel : ViewModel() {

    private val _uiState = MutableStateFlow<SortMakerPlayUiState?>(null)
    val uiState: StateFlow<SortMakerPlayUiState?> = _uiState.asStateFlow()

    private var appModule: AppModule? = null
    private var loaded = false

    fun load(context: Context, initialSession: SortMakerSession) {
        if (loaded) return
        loaded = true
        val module = AppModule.from(context)
        appModule = module
        // 再生は load で 1 回だけ (コアを呼ぶ重い初期化を Composable の再評価で何度も走らせない)。
        _uiState.value = SortMakerPlayUiState(
            session = initialSession,
            coreState = SortMakerState(pair = null, answered = 0u, estimatedRemaining = 0u, progressPercent = 0u, ranking = emptyList(), isFinished = false)
        )
        viewModelScope.launch {
            val items = SortMakerCandidates.loadByIds(
                initialSession.subject, initialSession.itemIds, module.songRepository, module.idolRepository
            )
            val current = _uiState.value ?: return@launch
            val coreState = initialSession.replay()
            _uiState.value = current.copy(
                items = items, isLoaded = true, coreState = coreState,
                shownPercent = coreState.progressPercent, shownRemaining = coreState.estimatedRemaining
            )
            if (coreState.isFinished && !initialSession.isFinished) finish()
        }
    }

    fun item(index: UInt): SortMakerItem? {
        val items = _uiState.value?.items ?: return null
        val i = index.toInt()
        return items.getOrNull(i)
    }

    val canUndo: Boolean get() = _uiState.value?.session?.answers?.isNotEmpty() == true

    /** 何戦目か (1 始まり)。 */
    val round: Int get() = (_uiState.value?.coreState?.answered?.toInt() ?: 0) + 1

    fun answer(choice: SortMakerChoice) {
        val current = _uiState.value ?: return
        if (current.coreState.isFinished) return
        commit(current.session.appendChoice(choice), resetShown = false)
    }

    fun undo() {
        val current = _uiState.value ?: return
        if (!canUndo) return
        // 「1 つ戻る」は進み具合が実際に減る操作なので、戻らない表示もここで取り直す。
        commit(current.session.withoutLastAnswer(), resetShown = true)
    }

    /** 順位表の行 (消えたものは飛ばす)。 */
    fun rankedItems(): List<Pair<Int, SortMakerItem>> {
        val current = _uiState.value ?: return emptyList()
        return current.coreState.ranking.mapNotNull { entry ->
            item(entry.item)?.let { entry.rank.toInt() to it }
        }
    }

    private fun commit(newSession: SortMakerSession, resetShown: Boolean) {
        val withSavedAt = newSession.copy(savedAt = System.currentTimeMillis())
        val newCoreState = withSavedAt.replay()
        val current = _uiState.value
        val (shownPercent, shownRemaining) = when {
            resetShown -> newCoreState.progressPercent to newCoreState.estimatedRemaining
            newCoreState.isFinished -> 100u to 0u
            else -> maxOf(current?.shownPercent ?: 0u, newCoreState.progressPercent) to
                minOf(current?.shownRemaining ?: newCoreState.estimatedRemaining, newCoreState.estimatedRemaining)
        }
        if (newCoreState.isFinished) {
            // 消えた項目も位置を詰めない (詰めると「前回の1位」が実際の2位になる)。
            val finished = withSavedAt.copy(
                isFinished = true,
                topNames = newCoreState.ranking.take(3).map { item(it.item)?.title ?: "（見つかりません）" }
            )
            appModule?.sortMakerStore?.save(finished)
            _uiState.value = current?.copy(
                session = finished, coreState = newCoreState, shownPercent = shownPercent, shownRemaining = shownRemaining,
                finishEventId = current.finishEventId + 1
            )
        } else {
            appModule?.sortMakerStore?.save(withSavedAt)
            _uiState.value = current?.copy(
                session = withSavedAt, coreState = newCoreState, shownPercent = shownPercent, shownRemaining = shownRemaining
            )
        }
    }

    private fun finish() {
        val current = _uiState.value ?: return
        val finished = current.session.copy(
            isFinished = true,
            topNames = current.coreState.ranking.take(3).map { item(it.item)?.title ?: "（見つかりません）" }
        )
        appModule?.sortMakerStore?.save(finished)
        _uiState.value = current.copy(session = finished, finishEventId = current.finishEventId + 1)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SortMakerPlayScreen(
    session: SortMakerSession,
    onBack: () -> Unit,
    onItemClick: (SortMakerItem) -> Unit,
    onPlayAgain: () -> Unit,
    onOpenTierList: (com.fugaif.imaslivedb.data.games.TierListBoard) -> Unit = {},
    viewModel: SortMakerPlayViewModel = viewModel(key = "sort_maker_play_${session.subject.key}")
) {
    val context = LocalContext.current
    LaunchedEffect(session.subject) { viewModel.load(context, session) }
    DisposableEffect(Unit) { onDispose { AudioPreviewManager.stop() } }

    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var showProvisional by rememberSaveable { mutableStateOf(false) }

    // 結果が出た瞬間だけ触覚を鳴らす (finishEventId は最初に終わった時点でしか増えない)。
    val haptics = androidx.compose.ui.platform.LocalHapticFeedback.current
    LaunchedEffect(state?.finishEventId) {
        if ((state?.finishEventId ?: 0) > 0) {
            haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(session.subject.title, fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") } },
                actions = {
                    if (state?.isLoaded == true && state?.coreState?.isFinished == false) {
                        IconButton(onClick = { showProvisional = true }, enabled = state?.coreState?.ranking?.isNotEmpty() == true) {
                            Icon(Icons.Filled.FormatListNumbered, "いまの順位")
                        }
                    }
                }
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding).background(DS.bg)) {
            val s = state
            when {
                s == null || !s.isLoaded -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                }
                s.coreState.isFinished -> {
                    SortMakerResultScreen(
                        model = viewModel,
                        state = s,
                        onItemClick = onItemClick,
                        onPlayAgain = onPlayAgain,
                        onOpenTierList = onOpenTierList
                    )
                }
                else -> {
                    SortMakerBattleView(model = viewModel, state = s)
                }
            }
        }
    }

    if (showProvisional) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
        ModalBottomSheet(onDismissRequest = { showProvisional = false }, sheetState = sheetState, containerColor = DS.bg) {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("いまの順位", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = DS.ink, modifier = Modifier.weight(1f))
                    IconButton(onClick = { showProvisional = false }) { Icon(Icons.Filled.Close, "閉じる", tint = DS.ink2) }
                }
                Text(
                    "ここまでの対戦で並んだ分だけの暫定順位です。",
                    fontSize = 12.sp, color = DS.ink3
                )
                SortMakerRankingList(rows = viewModel.rankedItems(), onSelect = null, modifier = Modifier.verticalScroll(rememberScrollState()))
            }
        }
    }
}

// MARK: - 対戦

/**
 * 画面幅から絵の大きさを決める定数。カードの左右余白 (画面 16.dp×2・カード間 16.dp・
 * カード内側 12.dp×2) を引いた残りを 2 枚に割り、64〜148.dp に収める
 * (375pt 幅の端末でもカードがはみ出さないように)。
 */
private val SCREEN_HORIZONTAL_PADDING = 16.dp
private val INTER_CARD_SPACING = 16.dp
private val CARD_INNER_HORIZONTAL_PADDING = 12.dp
private val CARD_TOP_INSET = 34.dp // カード上端からジャケ/アイコン上端まで (上余白20 + 帯4 + 間隔10)
private val VS_BADGE_RADIUS = 18.dp

@Composable
private fun SortMakerBattleView(model: SortMakerPlayViewModel, state: SortMakerPlayUiState) {
    var picked by remember { mutableStateOf<SortMakerChoice?>(null) }
    val scope = rememberCoroutineScopeCompat()

    Column(modifier = Modifier.fillMaxSize()) {
        // 本文: 普段は残りの高さいっぱいに収まるが、文字を大きくして収まらないときだけスクロール。
        androidx.compose.foundation.layout.BoxWithConstraints(
            modifier = Modifier.weight(1f).fillMaxWidth()
        ) {
            val cardInner = (maxWidth - SCREEN_HORIZONTAL_PADDING * 2 - INTER_CARD_SPACING) / 2 - CARD_INNER_HORIZONTAL_PADDING * 2
            val visual = cardInner.coerceIn(64.dp, 148.dp)

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = SCREEN_HORIZONTAL_PADDING)
                    .padding(top = 12.dp, bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp)
            ) {
                ProgressHeader(model, state)
                if (state.missingCount > 0) {
                    Text(
                        "対象のうち ${state.missingCount} 件がデータの更新で見つからなくなりました。気になるときは設定から作り直してください。",
                        fontSize = 12.sp, color = DS.ink3
                    )
                }
                Text(
                    "どっちが好き？", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DS.ink,
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()
                )
                val pair = state.coreState.pair
                if (pair != null) {
                    Box(Modifier.fillMaxWidth()) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(INTER_CARD_SPACING)) {
                            SortMakerCard(
                                item = model.item(pair.left),
                                visualSize = visual,
                                isPicked = picked == SortMakerChoice.LEFT,
                                isDimmed = picked != null && picked != SortMakerChoice.LEFT && picked != SortMakerChoice.TIE,
                                isTied = picked == SortMakerChoice.TIE,
                                modifier = Modifier.weight(1f)
                            ) {
                                if (picked == null) {
                                    picked = SortMakerChoice.LEFT
                                    AudioPreviewManager.stop()
                                    scope.launch {
                                        kotlinx.coroutines.delay(220)
                                        model.answer(SortMakerChoice.LEFT)
                                        picked = null
                                    }
                                }
                            }
                            SortMakerCard(
                                item = model.item(pair.right),
                                visualSize = visual,
                                isPicked = picked == SortMakerChoice.RIGHT,
                                isDimmed = picked != null && picked != SortMakerChoice.RIGHT && picked != SortMakerChoice.TIE,
                                isTied = picked == SortMakerChoice.TIE,
                                modifier = Modifier.weight(1f)
                            ) {
                                if (picked == null) {
                                    picked = SortMakerChoice.RIGHT
                                    AudioPreviewManager.stop()
                                    scope.launch {
                                        kotlinx.coroutines.delay(220)
                                        model.answer(SortMakerChoice.RIGHT)
                                        picked = null
                                    }
                                }
                            }
                        }
                        VsBadge(Modifier.align(Alignment.TopCenter).padding(top = CARD_TOP_INSET + visual / 2 - VS_BADGE_RADIUS))
                    }
                }
            }
        }
        // 操作バーは常に画面下に固定 (本文がスクロールしても位置が変わらない)。
        BottomBar(
            canUndo = model.canUndo && picked == null,
            onUndo = {
                AudioPreviewManager.stop()
                model.undo()
            },
            onTie = {
                if (picked == null) {
                    picked = SortMakerChoice.TIE
                    scope.launch {
                        kotlinx.coroutines.delay(220)
                        model.answer(SortMakerChoice.TIE)
                        picked = null
                    }
                }
            },
            tieDisabled = picked != null,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
        )
    }
}

@Composable
private fun rememberCoroutineScopeCompat() = androidx.compose.runtime.rememberCoroutineScope()

@Composable
private fun ProgressHeader(model: SortMakerPlayViewModel, state: SortMakerPlayUiState) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text("第${model.round}戦", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            Spacer(Modifier.weight(1f))
            Text(
                "残り約${state.shownRemaining}戦 · ${state.shownPercent}%",
                fontSize = 12.sp, color = DS.ink3
            )
        }
        val progress by animateFloatAsState(targetValue = state.shownPercent.toFloat() / 100f, label = "sortMakerProgress")
        Box(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)).background(DS.fill)) {
            Box(
                Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(progress.coerceIn(0.02f, 1f))
                    .clip(RoundedCornerShape(3.dp))
                    .background(imasTheme(null, null).accent)
            )
        }
    }
}

@Composable
private fun VsBadge(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(36.dp)
            .clip(CircleShape)
            .background(imasTheme(null, null).accent),
        contentAlignment = Alignment.Center
    ) {
        Text("VS", fontSize = 13.sp, fontWeight = FontWeight.Black, color = DS.surface)
    }
}

@Composable
private fun BottomBar(
    canUndo: Boolean,
    onUndo: () -> Unit,
    onTie: () -> Unit,
    tieDisabled: Boolean,
    modifier: Modifier = Modifier
) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .weight(1f)
                .clip(RoundedCornerShape(12.dp))
                .background(DS.surface)
                .clickable(enabled = canUndo, onClick = onUndo)
                .padding(vertical = 14.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.AutoMirrored.Filled.Undo, null, tint = if (canUndo) DS.ink else DS.ink3, modifier = Modifier.size(16.dp))
            Spacer(Modifier.size(6.dp))
            Text("1つ戻る", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = if (canUndo) DS.ink else DS.ink3)
        }
        Row(
            modifier = Modifier
                .weight(1f)
                .clip(RoundedCornerShape(12.dp))
                .background(DS.surface)
                .clickable(enabled = !tieDisabled, onClick = onTie)
                .padding(vertical = 14.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Filled.Equalizer, null, tint = DS.ink, modifier = Modifier.size(16.dp))
            Spacer(Modifier.size(6.dp))
            Text("引き分け", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
        }
    }
}

/** 対戦カード 1 枚。全面がタップ領域。曲は試聴ボタン付き。 */
@Composable
fun SortMakerCard(
    item: SortMakerItem?,
    /** ジャケ / アイコンの一辺。画面幅から決まる。 */
    visualSize: androidx.compose.ui.unit.Dp,
    isPicked: Boolean,
    isDimmed: Boolean,
    isTied: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val theme = imasThemeForBrand(item?.seed, item?.brandId)
    val scaleTarget = if (isPicked) 1.03f else if (isDimmed) 0.97f else 1f
    val scale by animateFloatAsState(scaleTarget, label = "sortMakerCardScale")
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .scale(scale)
                .alpha(if (isDimmed) 0.5f else 1f)
                .clip(RoundedCornerShape(18.dp))
                .background(DS.surface)
                .then(
                    if (isPicked || isTied) Modifier.border(3.dp, theme.accent, RoundedCornerShape(18.dp))
                    else Modifier
                )
                .clickable(onClick = onClick)
                .padding(horizontal = 12.dp, vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Box(Modifier.size(width = 36.dp, height = 4.dp).clip(RoundedCornerShape(2.dp)).background(theme.accent))
            CardVisual(item, visualSize)
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    item?.title ?: "（見つかりません）",
                    fontSize = 16.sp, fontWeight = FontWeight.Bold, color = DS.ink,
                    textAlign = TextAlign.Center, maxLines = 3, overflow = TextOverflow.Ellipsis
                )
                item?.subtitle?.let {
                    Text(it, fontSize = 12.sp, color = DS.ink3, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        PreviewButton(item)
    }
}

@Composable
private fun CardVisual(item: SortMakerItem?, visualSize: androidx.compose.ui.unit.Dp) {
    when (item) {
        is SortMakerItem.SongItem -> ImasArtwork(title = item.song.title, imageUrl = item.song.artworkUrl, size = visualSize)
        is SortMakerItem.IdolItem -> ImasAvatar(label = item.idol.shortName, seed = item.idol.color, brand = item.idol.brandId, size = visualSize * 0.92f, entityId = item.idol.id)
        null -> ImasArtwork(title = "?", size = visualSize)
    }
}

/** 曲だけ: 試聴。カードのタップ (＝選ぶ) とは別のボタンにする。 */
@Composable
private fun PreviewButton(item: SortMakerItem?) {
    val song = (item as? SortMakerItem.SongItem)?.song
    val url = song?.previewUrl
    if (song != null && !url.isNullOrEmpty()) {
        val playback by AudioPreviewManager.playbackState.collectAsState()
        val playing = playback.isPlaying(song.id)
        Row(
            modifier = Modifier
                .clip(CircleShape)
                .background(DS.fill)
                .clickable { AudioPreviewManager.togglePreview(url, song.id) }
                .padding(horizontal = 14.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(if (playing) Icons.Filled.Stop else Icons.Filled.PlayArrow, null, tint = DS.ink2, modifier = Modifier.size(14.dp))
            Spacer(Modifier.size(4.dp))
            Text(if (playing) "停止" else "試聴", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
        }
    } else {
        Box(Modifier.height(28.dp))
    }
}

/** 順位表の一覧 (結果の 4 位以下・対戦中の「いまの順位」)。 */
@Composable
fun SortMakerRankingList(
    rows: List<Pair<Int, SortMakerItem>>,
    onSelect: ((SortMakerItem) -> Unit)?,
    modifier: Modifier = Modifier
) {
    if (rows.isEmpty()) {
        ImasEmptyState(icon = Icons.Filled.FormatListNumbered, title = "まだ順位はありません")
        return
    }
    Column(
        modifier = modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(DS.surface)
    ) {
        rows.forEachIndexed { i, (rank, item) ->
            if (i > 0) Box(Modifier.fillMaxWidth().padding(start = 84.dp)) { Box(Modifier.fillMaxWidth().height(0.5.dp).background(DS.sep)) }
            RankingRow(rank, item, onSelect)
        }
    }
}

@Composable
private fun RankingRow(rank: Int, item: SortMakerItem, onSelect: ((SortMakerItem) -> Unit)?) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (onSelect != null) Modifier.clickable { onSelect(item) } else Modifier)
            .padding(horizontal = 16.dp)
            .height(60.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text("$rank", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink2, modifier = Modifier.width(28.dp), textAlign = TextAlign.End)
        RankingThumb(item)
        Column(Modifier.weight(1f)) {
            Text(item.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            item.subtitle?.let { Text(it, fontSize = 12.sp, color = DS.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
    }
}

@Composable
private fun RankingThumb(item: SortMakerItem) {
    when (item) {
        is SortMakerItem.SongItem -> ImasArtwork(title = item.song.title, imageUrl = item.song.artworkUrl, size = 44.dp)
        is SortMakerItem.IdolItem -> ImasAvatar(label = item.idol.shortName, seed = item.idol.color, brand = item.idol.brandId, size = 44.dp, entityId = item.idol.id)
    }
}
