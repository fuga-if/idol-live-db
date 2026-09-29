package com.fugaif.imaslivedb.ui.polls

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.share.ShareMessage
import com.fugaif.imaslivedb.ui.share.SocialShareChip
import com.fugaif.imaslivedb.ui.share.SocialShareIconButton
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch
import uniffi.imas_core.voteLimitPerTarget
import uniffi.imas_core.votesRemaining

/** お題(投票)の単体詳細。iOS PollDetailView の移植。実績バッジのタップ先や、お題一覧カードからの深掘りに使う。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PollDetailScreen(
    pollId: String,
    onBack: () -> Unit,
    viewModel: PollDetailViewModel = viewModel()
) {
    val context = LocalContext.current
    val state by viewModel.uiState.collectAsState()
    var showPicker by remember { mutableStateOf(false) }
    // 削除は取り返しがつかないので、ボタンタップ→即実行にせず確認を挟む。
    var showDeleteConfirm by remember { mutableStateOf(false) }
    val authService = remember { AppModule.from(context).authService }
    val authState by authService.state.collectAsState()
    val scope = rememberCoroutineScope()
    fun signIn() { scope.launch { authService.signIn(context) } }

    LaunchedEffect(pollId) { viewModel.load(pollId) }

    val detail = state.detail
    // 削除は作成者本人か管理者だけ (iOS PollDetailView.canDelete と同じ条件)。自分のお題かは
    // サーバ (is_own_poll) が決める。最終判定もサーバ (403) なので、ここは前さばき。
    val canDelete = authState.isAdmin || detail?.isOwnPoll == true

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(detail?.title ?: "", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                },
                actions = {
                    // お題そのもののシェア (「このお題に投票しよう！」)。投票有無に関係なく常に出す。
                    if (detail != null) {
                        SocialShareIconButton(
                            payload = ShareMessage.pollInvitePayload(
                                detail.id, detail.title, detail.endsAtMs, detail.isActive
                            ),
                            contentDescription = "このお題をシェア"
                        )
                    }
                    if (canDelete) {
                        IconButton(onClick = { showDeleteConfirm = true }, enabled = !state.isDeleting) {
                            if (state.isDeleting) {
                                CircularProgressIndicator(modifier = Modifier.size(18.dp), color = DS.ink2)
                            } else {
                                Icon(Icons.Filled.Delete, contentDescription = "このお題を削除", tint = DS.danger)
                            }
                        }
                    }
                }
            )
        }
    ) { padding ->
        if (state.isLoading || detail == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            // 1 対象あたりの票数と残りはコアが決める。
            val limit = voteLimitPerTarget().toInt()
            val remaining = votesRemaining(detail.myVoteCount.coerceAtLeast(0).toUInt()).toInt()
            Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
                Column(Modifier.fillMaxWidth().padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        StatusLabel(detail)
                        ScopeBadge(detail)
                    }
                    if (!detail.description.isNullOrEmpty()) {
                        Text(detail.description, fontSize = 14.sp, color = DS.ink2, modifier = Modifier.padding(top = 8.dp))
                    }
                    Text("${detail.totalVotes}票 ・ ${detail.entries.size}件の候補", fontSize = 12.sp, color = DS.ink3, modifier = Modifier.padding(top = 6.dp))
                }
                HorizontalDivider(color = DS.sep)

                Column(Modifier.padding(top = 12.dp)) {
                    if (!authState.isSignedIn) {
                        LoginPromptBanner(onSignIn = ::signIn)
                    }
                    PollEntriesList(detail.entries, state.entityNames, detail.totalVotes, authState.isSignedIn, viewModel::toggleVote)

                    if (authState.isSignedIn && detail.isActive) {
                        Text("タップで投票/取消 (残り${remaining}/${limit})", fontSize = 11.sp, color = DS.ink3, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp))
                    }

                    if (authState.isSignedIn && detail.isActive && detail.candidateScope != CommunityApi.PollCandidateScope.MANUAL) {
                        Button(
                            onClick = { showPicker = true },
                            enabled = remaining > 0,
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
                        ) {
                            Icon(Icons.Filled.AddCircle, contentDescription = null, modifier = Modifier.size(18.dp))
                            Text(
                                if (remaining > 0) "候補を追加して投票 (残り${remaining}/${limit})" else "投票済み (${limit}/${limit})",
                                fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.padding(start = 6.dp)
                            )
                        }
                    }

                    // 自分の投票のシェアは締切後も残す (結果が出てからの方が話題になる)。
                    val myVoteNames = detail.entries
                        .filter { it.mine }
                        .map { state.entityNames[it.entityId] ?: it.entityId }
                    if (myVoteNames.isNotEmpty()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
                        ) {
                            Text("あなたの投票 ${myVoteNames.size}/${voteLimitPerTarget()}", fontSize = 12.sp, color = DS.ink3)
                            Spacer(Modifier.weight(1f))
                            SocialShareChip(
                                title = "投票をシェア",
                                payload = ShareMessage.pollVotesPayload(detail.id, detail.title, myVoteNames)
                            )
                        }
                    }
                }
                Box(Modifier.size(24.dp))
            }
        }
    }

    if (showPicker && detail != null) {
        val alreadySelected = detail.entries.filter { it.mine }.map { it.entityId }.toSet()
        val remaining = votesRemaining(detail.myVoteCount.coerceAtLeast(0).toUInt()).toInt()
        // 選択状態を見せる選択肢 (アイドル・ユニット) は外したものを取り消す。曲は足すだけ (iOS と同じ)。
        when (detail.targetType) {
            "idol" -> IdolPollCandidatePicker(
                alreadySelected = alreadySelected,
                remaining = remaining,
                onDismiss = { showPicker = false },
                onConfirm = { ordered -> viewModel.applyPickerSelection(ordered, unvoteDeselected = true); showPicker = false }
            )
            "unit" -> UnitPollCandidatePicker(
                alreadySelected = alreadySelected,
                remaining = remaining,
                onDismiss = { showPicker = false },
                onConfirm = { ordered -> viewModel.applyPickerSelection(ordered, unvoteDeselected = true); showPicker = false }
            )
            else -> SongPollCandidatePicker(
                alreadySelected = alreadySelected,
                remaining = remaining,
                restrictedBrandIds = if (detail.candidateScope == CommunityApi.PollCandidateScope.BRAND) detail.scopeBrandIds.toSet() else null,
                onDismiss = { showPicker = false },
                onConfirm = { ordered -> viewModel.applyPickerSelection(ordered, unvoteDeselected = false); showPicker = false }
            )
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("このお題を削除しますか？") },
            text = { Text("ランキング・投票データも一緒に削除され、元に戻せません。") },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    // 削除できた時だけ戻る。一覧は再表示時の再ロードでこのお題が消える。
                    viewModel.delete(onDeleted = onBack)
                }) { Text("削除", color = DS.danger) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("キャンセル") }
            }
        )
    }

    if (state.deleteError != null) {
        AlertDialog(
            onDismissRequest = { viewModel.clearDeleteError() },
            title = { Text("エラー") },
            text = { Text(state.deleteError ?: "") },
            confirmButton = { TextButton(onClick = { viewModel.clearDeleteError() }) { Text("OK") } }
        )
    }
}

@Composable
private fun StatusLabel(detail: CommunityApi.PollDetail) {
    Text(
        detail.statusLabel, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
        color = if (detail.isActive) DS.pick else DS.ink3
    )
}
