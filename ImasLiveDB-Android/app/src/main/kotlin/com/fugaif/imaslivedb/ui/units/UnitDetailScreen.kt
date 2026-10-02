package com.fugaif.imaslivedb.ui.units

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.auth.AuthState
import com.fugaif.imaslivedb.data.auth.shouldPromptLogin
import com.fugaif.imaslivedb.data.auth.showEditAffordance
import com.fugaif.imaslivedb.data.auth.startCommunityEdit
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.CommunityLoginPromptDialog
import com.fugaif.imaslivedb.ui.components.ImasSongRow
import com.fugaif.imaslivedb.ui.components.UnitGridSection
import com.fugaif.imaslivedb.ui.components.CopyItem
import com.fugaif.imaslivedb.ui.components.Copyable
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasChip
import com.fugaif.imaslivedb.ui.designsystem.ImasChipFlow
import com.fugaif.imaslivedb.ui.designsystem.ImasChipStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasHero
import com.fugaif.imaslivedb.ui.designsystem.ImasHeroLayout
import com.fugaif.imaslivedb.ui.designsystem.ImasIdolRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasSignInPrompt
import com.fugaif.imaslivedb.ui.designsystem.ImasUnitAvatar
import com.fugaif.imaslivedb.ui.components.PersonalTagsSection
import com.fugaif.imaslivedb.ui.polls.PollAchievementBadges
import com.fugaif.imaslivedb.ui.tags.UnitTagPickerSheet
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasRowPress

/**
 * ユニット詳細。iOS 構造: hero(ユニット名) → [楽曲/メンバー/コミュニティ] セグメント。
 * `ui.idols.IdolDetailScreen` のセグメント切替パターンを踏襲 (「ライブ」相当はユニットに馴染まないため3タブ)。
 * 画像登録機能は iOS のみの対応 (Android は今回未実装)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UnitDetailScreen(
    unitId: String,
    onNavigateBack: () -> Unit,
    onNavigateToIdolDetail: (String) -> Unit,
    onNavigateToSongDetail: (String) -> Unit,
    onNavigateToUnitDetail: (String) -> Unit = {},
    onPollClick: (String) -> Unit = {},
    onUnitTagClick: (String) -> Unit = {},
    viewModel: UnitDetailViewModel = viewModel(
        factory = UnitDetailViewModel.Factory(
            LocalContext.current.applicationContext as android.app.Application, unitId
        )
    )
) {
    val context = LocalContext.current
    val state by viewModel.uiState.collectAsState()
    val unit = state.unit
    var segment by rememberSaveable(unitId) { mutableIntStateOf(0) }
    var showTagPicker by rememberSaveable { mutableStateOf(false) }
    var showLoginPrompt by rememberSaveable { mutableStateOf(false) }
    val authState by AppModule.from(context).authService.state.collectAsState()

    // 投稿/編集導線の共通ゲート (iOS UnitDetailView.startCommunityEdit と同じ)。優先順はコアが持つので
    // if で並べ直さない。BAN 済みは iOS の .ignore と同じく無反応 (onBanned 既定) —
    // この画面の編集導線は showEditAffordance で隠れており、押せるのはタグチップだけ。
    fun startCommunityEdit(present: () -> Unit) =
        authState.startCommunityEdit(promptLogin = { showLoginPrompt = true }, present = present)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(unit?.displayName ?: "", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { padding ->
        if (state.loadError != null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                ImasEmptyState(
                    icon = Icons.Filled.ErrorOutline,
                    title = "読み込みに失敗しました",
                    message = state.loadError,
                    actionTitle = "再試行",
                    onAction = { viewModel.retry() }
                )
            }
        } else if (state.isLoading || unit == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
                Hero(unit)
                ImasSegmented(
                    labels = listOf("楽曲", "メンバー", "コミュニティ"),
                    selection = segment, onSelect = { segment = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)
                )
                when (segment) {
                    0 -> SongsBody(state, onNavigateToSongDetail)
                    1 -> MembersBody(state, onNavigateToIdolDetail)
                    else -> Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
                        CommunityBody(
                            unitId = unit.id,
                            tags = state.tags,
                            authState = authState,
                            similarUnits = state.similarUnits,
                            similarSharedTags = state.similarSharedTags,
                            // 外す方向はゲートしない (iOS も自分が付けたタグの取り消しは素通し)。
                            // 付ける方向はタグ投票の書き込みなので共通ゲートを通す。
                            onToggleTag = { tag ->
                                if (tag.mine) viewModel.toggleTag(tag)
                                else startCommunityEdit { viewModel.toggleTag(tag) }
                            },
                            onOpenTagPicker = { startCommunityEdit { showTagPicker = true } },
                            onPollClick = onPollClick,
                            onTagDetailClick = onUnitTagClick,
                            onUnitClick = onNavigateToUnitDetail
                        )
                        PersonalTagsSection(
                            tags = state.personalTags.map { it.tagName },
                            onAdd = viewModel::addPersonalTag,
                            onRemove = viewModel::removePersonalTag
                        )
                    }
                }
                Box(Modifier.size(24.dp))
            }
        }
    }

    if (showTagPicker && unit != null) {
        UnitTagPickerSheet(
            unitId = unit.id,
            alreadyAppliedTagIds = state.tags.filter { it.mine }.map { it.id }.toSet(),
            onDismiss = { showTagPicker = false },
            onApplied = { viewModel.onTagsApplied() }
        )
    }

    if (showLoginPrompt) {
        CommunityLoginPromptDialog(
            message = "タグ付け・投票にはログインが必要です。",
            onDismiss = { showLoginPrompt = false }
        )
    }
}

/** 頭 (iOS `ImasHero(layout: .leading)` + `ImasUnitAvatar`)。長押しでユニット名・別名をコピーできる。 */
@Composable
private fun Hero(unit: ImasUnit) {
    Copyable(
        items = listOf(CopyItem("ユニット名をコピー", unit.displayName), CopyItem("別名をコピー", unit.nameAlt)),
        modifier = Modifier.fillMaxWidth()
    ) {
        ImasHero(title = unit.displayName, layout = ImasHeroLayout.LEADING) {
            ImasUnitAvatar(unit, size = 72.dp)
        }
    }
}

@Composable
private fun SongsBody(state: UnitDetailUiState, onSongClick: (String) -> Unit) {
    Column(modifier = Modifier.padding(top = DS.Space.gapTight)) {
        if (state.songs.isEmpty()) {
            ImasEmptyState(icon = Icons.Filled.MusicNote, title = "楽曲がありません")
        } else {
            ImasSectionHeader("楽曲", count = "${state.songs.size}", tight = true)
            ImasCardList(
                items = state.songs,
                modifier = Modifier.padding(horizontal = DS.Space.screen),
                key = { it.id }
            ) { song ->
                ImasSongRow(
                    song = song,
                    subtitle = song.singerLabel?.takeIf { it.isNotEmpty() } ?: song.unitName,
                    showsBrandBar = true,
                    density = ImasRowDensity.COMPACT,
                    onClick = { onSongClick(song.id) }
                )
            }
        }
    }
}

/** メンバー一覧。iOS `UnitDetailView.membersBody` と同じく `ImasIdolRow` の行 (担当は Android では未算出)。 */
@Composable
private fun MembersBody(state: UnitDetailUiState, onIdolClick: (String) -> Unit) {
    Column(modifier = Modifier.padding(top = DS.Space.gapTight)) {
        if (state.members.isEmpty()) {
            ImasEmptyState(icon = Icons.Filled.Groups, title = "メンバー情報がありません")
        } else {
            ImasSectionHeader("メンバー", count = "${state.members.size}", tight = true)
            ImasCardList(
                items = state.members,
                modifier = Modifier.padding(horizontal = DS.Space.screen),
                key = { it.id }
            ) { idol ->
                ImasIdolRow(
                    idol = idol,
                    subtitle = idol.currentVoiceActor,
                    trailing = ImasRowTrailing.Chevron,
                    density = ImasRowDensity.COMPACT,
                    modifier = Modifier.imasRowPress(onClick = { onIdolClick(idol.id) })
                )
            }
        }
    }
}

/**
 * コミュニティタブ。`ui.idols.IdolDetailScreen` の CommunityBody をユニット向けに置換したもの。
 * タグ表示・付与 (unit_tag_master) + タグが似ているユニット (サーバ算出) + 投票実績バッジ。
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
private fun CommunityBody(
    unitId: String,
    tags: List<CommunityApi.UnitTag>,
    authState: AuthState,
    similarUnits: List<ImasUnit>,
    similarSharedTags: Map<String, Int>,
    onToggleTag: (CommunityApi.UnitTag) -> Unit,
    onOpenTagPicker: () -> Unit,
    onPollClick: (String) -> Unit,
    onTagDetailClick: (String) -> Unit,
    onUnitClick: (String) -> Unit
) {
    // 権限フラグは認証状態が変わった時だけコアへ問い合わせる (再コンポーズごとに
    // EditPermissionRules を RustBuffer へ詰め直して JNA を跨がないため)。
    val canEditHere = remember(authState) { authState.showEditAffordance }
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.section)) {
        PollAchievementBadges(entityId = unitId, onOpenPoll = onPollClick)
        ImasSignInPrompt(
            modifier = Modifier.padding(horizontal = DS.Space.screen),
            message = "タグ付け・投票にはログインが必要です"
        )
        Column {
            ImasSectionHeader(
                "タグ", count = "${tags.size}",
                actionTitle = if (canEditHere) "タグ" else null,
                actionIcon = if (canEditHere) Icons.Filled.Add else null,
                onAction = if (canEditHere) onOpenTagPicker else null
            )
            if (tags.isEmpty()) {
                ImasEmptyState(icon = Icons.Filled.Sell, title = "タグはまだありません")
            } else {
                ImasChipFlow(modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen)) {
                    tags.forEach { tag ->
                        val label = if (tag.voteCount > 0) "${tag.name} ${tag.voteCount}" else tag.name
                        ImasChip(
                            text = label,
                            style = if (tag.mine) ImasChipStyle.SELECTED else ImasChipStyle.THEMED,
                            // タップは投票トグル、長押しでタグ詳細 (アイドルタグのチップと同じ作法)。
                            modifier = Modifier.combinedClickable(
                                onClick = { onToggleTag(tag) },
                                onLongClick = { onTagDetailClick(tag.id) }
                            )
                        )
                    }
                }
            }
        }
        // タグが似ているユニット (このユニットが好きな人にはこのユニットも, サーバ算出)
        if (similarUnits.isNotEmpty()) {
            UnitGridSection("タグが似ているユニット", similarUnits, onUnitClick, badge = similarSharedTags)
        }
    }
}
