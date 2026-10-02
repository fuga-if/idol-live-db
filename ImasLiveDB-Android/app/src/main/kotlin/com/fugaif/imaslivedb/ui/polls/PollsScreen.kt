package com.fugaif.imaslivedb.ui.polls

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.HowToVote
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasContentState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyStateKind
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSignInPrompt
import com.fugaif.imaslivedb.ui.designsystem.ImasSkeletonKind
import com.fugaif.imaslivedb.ui.designsystem.ImasStateContainer
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
import com.fugaif.imaslivedb.ui.designsystem.ImasToolbarButton
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.share.ShareMessage
import com.fugaif.imaslivedb.ui.share.SocialShareIconButton

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

    // 詳細でお題を削除したり投票したりして戻ってきた時に一覧を追従させる
    // (この画面はバックスタックに残るので、composable の初回起動だけでは古いままになる)。
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { viewModel.refresh() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("投票・予想") },
                navigationIcon = {
                    // サイドバーの根として開いたときは戻る先が無いので出さない。
                    onBack?.let { back ->
                        IconButton(onClick = back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                    }
                },
                actions = {
                    ImasToolbarButton(icon = Icons.Filled.EmojiEvents, label = "殿堂を見る", onClick = onHallOfFameClick, tint = DS.warning)
                    // 作成はログイン必須 (サーバが 401 を返す)。未ログインでは押せるボタンを出さない。
                    if (authState.isSignedIn) {
                        ImasToolbarButton(icon = Icons.Filled.Add, label = "お題を作成", onClick = { showCreateSheet = true })
                    }
                }
            )
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            ImasTabs(
                labels = listOf("開催中", "終了"),
                selection = if (state.showActive) 0 else 1,
                onSelect = { viewModel.setShowActive(it == 0) },
                modifier = Modifier.padding(horizontal = DS.Space.screen)
            )
            val uiContentState = when {
                state.isLoading -> ImasContentState.Loading
                state.cards.isEmpty() -> ImasContentState.Empty
                else -> ImasContentState.Loaded
            }
            ImasStateContainer(
                state = uiContentState,
                modifier = Modifier.fillMaxSize(),
                skeleton = ImasSkeletonKind.List(),
                empty = {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        // 一覧が出せない理由は「まだ無い」と「取れなかった」で違うので出し分ける。
                        if (state.loadError != null) {
                            ImasEmptyState(Icons.Filled.ErrorOutline, "読み込みに失敗しました", state.loadError)
                        } else {
                            ImasEmptyState(
                                Icons.Filled.HowToVote,
                                if (state.showActive) "開催中のお題がありません" else "終了したお題がありません",
                                if (state.showActive) "右上の「＋」から新しいお題を投稿できます。" else null
                            )
                        }
                    }
                }
            ) {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    if (!authState.isSignedIn) {
                        item {
                            ImasSignInPrompt(
                                message = "投票にはログインが必要です",
                                buttonTitle = "Googleでログイン",
                                modifier = Modifier.padding(DS.Space.screen)
                            )
                        }
                    }
                    itemsIndexed(state.cards, key = { _, c -> c.poll.id }) { idx, card ->
                        PollRow(
                            card = card,
                            onClick = { onPollClick(card.poll.id) },
                            position = if (idx == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING
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
}

/**
 * 一覧の 1 行 (要約だけ)。題・状態・票の合計・候補の範囲・いまの 1 位を出し、押すと詳細へ。
 * 候補ごとの票と投票は詳細画面で行う (iOS の PollRowView と同じ役割)。
 */
@Composable
private fun PollRow(
    card: PollCard,
    onClick: () -> Unit,
    position: ImasRowPosition
) {
    val poll = card.poll
    ImasRow(
        title = poll.title,
        // 前は行数制限なし (利用者が付けたお題名を途中で切らない)。
        titleLineLimit = Int.MAX_VALUE,
        modifier = Modifier.fillMaxWidth().imasRowPress(onClick = onClick),
        position = position,
        trailing = ImasRowTrailing.Custom {
            SocialShareIconButton(
                payload = ShareMessage.pollInvitePayload(poll.id, poll.title, poll.endsAtMs, poll.isActive),
                contentDescription = "このお題をシェア"
            )
        }
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                poll.statusLabel, style = ImasTextRole.META.style,
                color = if (poll.isActive) DS.pick else DS.ink3
            )
            if (poll.totalVotes > 0) {
                Text("計${poll.totalVotes}票", style = ImasTextRole.META.style, color = DS.ink3, modifier = Modifier.padding(start = DS.Space.gap))
            }
            ScopeBadge(poll)
        }
        card.topEntityName?.let { name ->
            Text("1位 $name", style = ImasTextRole.ROW_SUBTITLE.style, color = DS.ink2, maxLines = 1)
        }
    }
}
