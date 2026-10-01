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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.HowToVote
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
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.share.ShareMessage
import com.fugaif.imaslivedb.ui.share.SocialShareIconButton
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch
import androidx.compose.material3.HorizontalDivider
import androidx.compose.ui.text.style.TextOverflow

/** 投票・予想。Worker D1 のポールを表示し、選択肢に投票できる (端末ベース)。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PollsScreen(
    onBack: (() -> Unit)?,
    onPollClick: (String) -> Unit = {},
    onHallOfFameClick: () -> Unit = {},
    viewModel: PollsViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
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
                    // サイドバーの根として開いたときは戻る先が無いので出さない。
                    onBack?.let { back ->
                        IconButton(onClick = back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                    }
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
                        PollRow(card = card, onClick = { onPollClick(card.poll.id) })
                        HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
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
}

/**
 * 一覧の 1 行 (要約だけ)。題・状態・票の合計・候補の範囲・いまの 1 位を出し、押すと詳細へ。
 * 候補ごとの票と投票は詳細画面で行う (iOS の PollRowView と同じ役割)。
 */
@Composable
private fun PollRow(card: PollCard, onClick: () -> Unit) {
    val poll = card.poll
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(start = 16.dp, top = 12.dp, bottom = 12.dp)
    ) {
        Column(Modifier.weight(1f)) {
            Text(poll.title, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
                Text(
                    poll.statusLabel, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                    color = if (poll.isActive) DS.pick else DS.ink3
                )
                if (poll.totalVotes > 0) {
                    Text("計${poll.totalVotes}票", fontSize = 12.sp, color = DS.ink3, modifier = Modifier.padding(start = 8.dp))
                }
                ScopeBadge(poll)
            }
            card.topEntityName?.let { name ->
                Text(
                    "1位 $name", fontSize = 13.sp, color = DS.ink2, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp)
                )
            }
        }
        // 一覧から直接お題を拡散できるように (詳細を開かずに誘える)。
        SocialShareIconButton(
            payload = ShareMessage.pollInvitePayload(poll.id, poll.title, poll.endsAtMs, poll.isActive),
            contentDescription = "このお題をシェア"
        )
    }
}
