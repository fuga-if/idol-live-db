package com.fugaif.imaslivedb.ui.polls

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.HowToVote
import androidx.compose.material3.Button
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.share.ShareMessage
import com.fugaif.imaslivedb.ui.share.SocialShareIconButton
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch

/** 投票・予想。Worker D1 のポールを表示し、選択肢に投票できる (端末ベース)。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PollsScreen(
    onBack: () -> Unit,
    onPollClick: (String) -> Unit = {},
    onHallOfFameClick: () -> Unit = {},
    viewModel: PollsViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    var pickerForPollId by remember { mutableStateOf<String?>(null) }
    var showCreateSheet by remember { mutableStateOf(false) }

    val context = LocalContext.current
    val authService = remember { AppModule.from(context).authService }
    val authState by authService.state.collectAsState()
    val scope = rememberCoroutineScope()
    fun signIn() { scope.launch { authService.signIn(context) } }

    // 詳細でお題を削除したり投票したりして戻ってきた時に一覧を追従させる
    // (この画面はバックスタックに残るので、composable の初回起動だけでは古いままになる)。
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { viewModel.refresh() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("投票・予想", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                },
                actions = {
                    IconButton(onClick = onHallOfFameClick) {
                        Icon(Icons.Filled.EmojiEvents, contentDescription = "殿堂を見る", tint = DS.warning)
                    }
                    // 作成はログイン必須 (サーバが 401 を返す)。未ログインでは押せるボタンを出さない。
                    if (authState.isSignedIn) {
                        IconButton(onClick = { showCreateSheet = true }) {
                            Icon(Icons.Filled.Add, contentDescription = "お題を作成")
                        }
                    }
                }
            )
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            ImasSegmented(
                labels = listOf("開催中", "終了"),
                selection = if (state.showActive) 0 else 1,
                onSelect = { viewModel.setShowActive(it == 0) },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
            )
            if (state.isLoading) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            } else if (state.cards.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    // 一覧が出せない理由は「まだ無い」と「取れなかった」で違うので出し分ける。
                    if (state.loadError != null) {
                        ImasEmptyState(
                            Icons.Filled.ErrorOutline, "読み込みに失敗しました", state.loadError
                        )
                    } else {
                        ImasEmptyState(
                            Icons.Filled.HowToVote,
                            if (state.showActive) "開催中のお題がありません" else "終了したお題がありません",
                            if (state.showActive) "右上の「＋」から新しいお題を投稿できます。" else null
                        )
                    }
                }
            } else {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    if (!authState.isSignedIn) {
                        item { LoginPromptBanner(onSignIn = ::signIn) }
                    }
                    items(state.cards, key = { it.poll.id }) { card ->
                        PollCardView(
                            card = card,
                            isSignedIn = authState.isSignedIn,
                            onToggleVote = { entityId, mine -> viewModel.toggleVote(card.poll.id, entityId, mine) },
                            onAddCandidate = { pickerForPollId = card.poll.id },
                            onClick = { onPollClick(card.poll.id) }
                        )
                    }
                }
            }
        }
    }

    if (showCreateSheet) {
        PollCreateSheet(
            onDismiss = { showCreateSheet = false },
            onCreated = { viewModel.insertCreated(it) }
        )
    }

    val pickerCard = state.cards.firstOrNull { it.poll.id == pickerForPollId }
    if (pickerCard != null) {
        val remaining = (3 - (pickerCard.detail?.myVoteCount ?: 0)).coerceAtLeast(0)
        val alreadySelected = pickerCard.detail?.entries?.filter { it.mine }?.map { it.entityId }?.toSet() ?: emptySet()
        when (pickerCard.poll.targetType) {
            "idol" -> IdolPollCandidatePicker(
                alreadySelected = alreadySelected,
                remaining = remaining,
                onDismiss = { pickerForPollId = null },
                onConfirm = { newIds ->
                    viewModel.voteForNewEntities(pickerCard.poll.id, newIds)
                    pickerForPollId = null
                }
            )
            "unit" -> UnitPollCandidatePicker(
                alreadySelected = alreadySelected,
                remaining = remaining,
                onDismiss = { pickerForPollId = null },
                onConfirm = { newIds ->
                    viewModel.voteForNewEntities(pickerCard.poll.id, newIds)
                    pickerForPollId = null
                }
            )
            else -> {
                val scope2 = pickerCard.detail?.candidateScope
                val restrictedBrandIds = if (scope2 == CommunityApi.PollCandidateScope.BRAND) {
                    pickerCard.detail.scopeBrandIds.toSet()
                } else null
                SongPollCandidatePicker(
                    alreadySelected = alreadySelected,
                    remaining = remaining,
                    restrictedBrandIds = restrictedBrandIds,
                    onDismiss = { pickerForPollId = null },
                    onConfirm = { newIds ->
                        viewModel.voteForNewEntities(pickerCard.poll.id, newIds)
                        pickerForPollId = null
                    }
                )
            }
        }
    }
}

@Composable
private fun PollCardView(
    card: PollCard,
    isSignedIn: Boolean,
    onToggleVote: (String, Boolean) -> Unit,
    onAddCandidate: () -> Unit,
    onClick: () -> Unit
) {
    val detail = card.detail
    val remaining = (3 - (detail?.myVoteCount ?: 0)).coerceAtLeast(0)
    // 終了セグメントには締切済みのお題が並ぶ。投票はサーバが弾くので、押せる導線は出さない
    // (詳細画面 PollDetailScreen も同じ isActive で出し分けている)。
    val canVote = isSignedIn && detail?.isActive == true
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                card.poll.title,
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                color = DS.ink,
                modifier = Modifier.weight(1f)
            )
            // 一覧から直接お題を拡散できるように (詳細を開かずに誘える)。
            SocialShareIconButton(
                payload = ShareMessage.pollInvitePayload(
                    card.poll.id, card.poll.title, detail?.endsAtMs, detail?.isActive == true
                ),
                contentDescription = "このお題をシェア"
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 8.dp)) {
            Text("${detail?.totalVotes ?: 0}票", fontSize = 12.sp, color = DS.ink3)
            if (detail != null) {
                Text(
                    detail.statusLabel, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                    color = if (detail.isActive) DS.pick else DS.ink3,
                    modifier = Modifier.padding(start = 8.dp)
                )
                ScopeBadge(detail)
            }
        }
        if (detail != null) {
            PollEntriesList(detail.entries, card.entityNames, detail.totalVotes, canVote, onToggleVote)
        }
        if (canVote) {
            Text("タップで投票/取消 (残り${remaining}/3)", fontSize = 11.sp, color = DS.ink3, modifier = Modifier.padding(top = 6.dp))
        }

        // 候補が指定制 (manual) でなければ、新規候補を追加できる (曲・アイドル共通)。
        if (canVote && detail?.candidateScope != CommunityApi.PollCandidateScope.MANUAL) {
            Button(
                onClick = onAddCandidate,
                enabled = remaining > 0,
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
            ) {
                Icon(Icons.Filled.AddCircle, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(
                    if (remaining > 0) "候補を追加して投票 (残り${remaining}/3)" else "投票済み (3/3)",
                    fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(start = 6.dp)
                )
            }
        }
    }
}
