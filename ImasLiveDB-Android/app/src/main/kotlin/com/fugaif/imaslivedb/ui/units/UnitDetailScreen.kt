package com.fugaif.imaslivedb.ui.units

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.MusicNote
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.auth.AuthState
import com.fugaif.imaslivedb.data.auth.shouldPromptLogin
import com.fugaif.imaslivedb.data.auth.showEditAffordance
import com.fugaif.imaslivedb.data.auth.startCommunityEdit
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.CommunityLoginPromptDialog
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.components.PersonalTagsSection
import com.fugaif.imaslivedb.ui.components.SongRow
import com.fugaif.imaslivedb.ui.polls.PollAchievementBadges
import com.fugaif.imaslivedb.ui.tags.UnitTagPickerSheet
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme

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
    viewModel: UnitDetailViewModel = viewModel(
        factory = UnitDetailViewModel.Factory(
            LocalContext.current.applicationContext as android.app.Application, unitId
        )
    )
) {
    val context = LocalContext.current
    val state by viewModel.uiState.collectAsState()
    val unit = state.unit
    val t = ImasTheme.derive(null, unit?.brandId, dark = true)
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
                Hero(unit, t)
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

@Composable
private fun Hero(unit: ImasUnit, t: ImasTheme) {
    Column(
        modifier = Modifier.fillMaxWidth().background(t.heroSurface).padding(vertical = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(unit.displayName, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DS.ink, textAlign = TextAlign.Center)
    }
}

@Composable
private fun SongsBody(state: UnitDetailUiState, onSongClick: (String) -> Unit) {
    Column(modifier = Modifier.padding(top = 12.dp)) {
        if (state.songs.isEmpty()) {
            ImasEmptyState(icon = Icons.Filled.MusicNote, title = "楽曲がありません")
        } else {
            ImasSectionHeader("楽曲", count = "${state.songs.size}")
            state.songs.forEach { song ->
                SongRow(
                    title = song.title, artistNames = song.singerLabel ?: "", unitName = song.unitName,
                    artworkUrl = song.artworkUrl, previewUrl = song.previewUrl, brandId = song.brandId,
                    modifier = Modifier.clickable { onSongClick(song.id) }.padding(horizontal = 16.dp)
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MembersBody(state: UnitDetailUiState, onIdolClick: (String) -> Unit) {
    Column(modifier = Modifier.padding(top = 12.dp)) {
        if (state.members.isEmpty()) {
            ImasEmptyState(icon = Icons.Filled.Groups, title = "メンバー情報がありません")
        } else {
            ImasSectionHeader("メンバー", count = "${state.members.size}")
            FlowRow(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                state.members.forEach { idol ->
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.width(72.dp).clickable { onIdolClick(idol.id) }
                    ) {
                        ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 56.dp)
                        Text(idol.name, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = DS.ink2,
                            textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(top = 6.dp))
                        idol.currentVoiceActor?.let { cv ->
                            Text(cv, fontSize = 10.sp, color = DS.ink3, textAlign = TextAlign.Center,
                                maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}

/**
 * コミュニティタブ。`ui.idols.IdolDetailScreen` の CommunityBody をユニット向けに置換したもの。
 * タグ表示・付与 (unit_tag_master) + タグが似ているユニット (サーバ算出) + 投票実績バッジ。
 */
@OptIn(ExperimentalLayoutApi::class)
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
    onUnitClick: (String) -> Unit
) {
    // 権限フラグは認証状態が変わった時だけコアへ問い合わせる (再コンポーズごとに
    // EditPermissionRules を RustBuffer へ詰め直して JNA を跨がないため)。
    val canEditHere = remember(authState) { authState.showEditAffordance }
    val needsLogin = remember(authState) { authState.shouldPromptLogin }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        PollAchievementBadges(entityId = unitId, onOpenPoll = onPollClick)
        if (needsLogin) {
            Box(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
                    .clip(RoundedCornerShape(12.dp)).background(DS.fill).padding(12.dp)
            ) {
                Text("タグ付け・投票にはログインが必要です", fontSize = 12.5.sp, color = DS.ink2)
            }
        }
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ImasSectionHeader("タグ", count = "${tags.size}", modifier = Modifier.weight(1f))
                if (canEditHere) {
                    IconButton(onClick = onOpenTagPicker, modifier = Modifier.padding(end = 8.dp)) {
                        Icon(Icons.Filled.Add, contentDescription = "タグを追加", tint = DS.ink2)
                    }
                }
            }
            if (tags.isEmpty()) {
                Text("タグはまだありません", fontSize = 13.sp, color = DS.ink3,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp))
            } else {
                FlowRow(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    tags.forEach { tag ->
                        val bg = if (tag.mine) DS.pick.copy(alpha = 0.18f) else DS.fill
                        val fg = if (tag.mine) DS.pick else DS.ink
                        Row(
                            modifier = Modifier.clip(RoundedCornerShape(999.dp)).background(bg)
                                .clickable { onToggleTag(tag) }
                                .padding(horizontal = 12.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(tag.name, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = fg)
                            if (tag.voteCount > 0) {
                                Text(" ${tag.voteCount}", fontSize = 12.sp, color = DS.ink3)
                            }
                        }
                    }
                }
            }
        }
        // タグが似ているユニット (このユニットが好きな人にはこのユニットも, サーバ算出)
        if (similarUnits.isNotEmpty()) {
            Column {
                ImasSectionHeader("タグが似ているユニット", count = "${similarUnits.size}")
                FlowRow(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    similarUnits.forEach { unit ->
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            modifier = Modifier.width(64.dp).clickable { onUnitClick(unit.id) }
                        ) {
                            ImasAvatar(label = unit.name, seed = unit.id, brand = unit.brandId, size = 52.dp)
                            Text(unit.name, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = DS.ink2,
                                textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.padding(top = 6.dp))
                            val shared = similarSharedTags[unit.id]
                            if (shared != null) {
                                Text("タグ${shared}個一致", fontSize = 10.sp, color = DS.ink3, textAlign = TextAlign.Center,
                                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                }
            }
        }
    }
}
