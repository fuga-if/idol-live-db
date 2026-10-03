package com.fugaif.imaslivedb.ui.polls

import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasCardListStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasConfirmDestructive
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasForecastAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasForecastMeasure
import com.fugaif.imaslivedb.ui.designsystem.ImasForecastRow
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasSignInPrompt
import com.fugaif.imaslivedb.ui.share.ShareMessage
import com.fugaif.imaslivedb.ui.share.SocialShareChip
import com.fugaif.imaslivedb.ui.share.SocialShareIconButton
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
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
                        ImasIconButton(
                            icon = Icons.Filled.Delete,
                            label = "このお題を削除",
                            style = ImasIconButtonStyle.PLAIN,
                            isLoading = state.isDeleting,
                            onClick = { showDeleteConfirm = true }
                        )
                    }
                }
            )
        }
    ) { padding ->
        if (state.isLoading || detail == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                ImasLoadingState()
            }
        } else {
            // 1 対象あたりの票数と残りはコアが決める。
            val limit = voteLimitPerTarget().toInt()
            val remaining = votesRemaining(detail.myVoteCount.coerceAtLeast(0).toUInt()).toInt()

            ImasPage(modifier = Modifier.fillMaxSize().padding(padding)) {
                // お題の頭 (状態・候補の範囲・説明・票の合計)。
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(detail.statusLabel, style = ImasTextRole.META.style, color = if (detail.isActive) DS.pick else DS.ink3)
                    ScopeBadge(detail)
                }
                if (!detail.description.isNullOrEmpty()) {
                    Text(detail.description, style = ImasTextRole.BODY.style, color = DS.ink2)
                }
                Text("${detail.totalVotes}票 ・ ${detail.entries.size}件の候補", style = ImasTextRole.META.style, color = DS.ink3)

                if (!authState.isSignedIn) {
                    ImasSignInPrompt(message = "投票にはログインが必要です", buttonTitle = "Googleでログイン")
                }

                if (detail.entries.isEmpty()) {
                    ImasEmptyState(icon = Icons.Filled.AddCircle, title = "まだ票がありません", message = "最初の一票を入れましょう！")
                } else {
                    ImasCardList(style = ImasCardListStyle.PANEL) {
                        detail.entries.forEachIndexed { index, entry ->
                            if (index > 0) ImasRowDivider(inset = DS.Space.rowH)
                            PollEntryRow(
                                rank = index + 1,
                                entry = entry,
                                totalVotes = detail.totalVotes,
                                targetType = detail.targetType,
                                song = state.songsById[entry.entityId],
                                idol = state.idolsById[entry.entityId],
                                unit = state.unitsById[entry.entityId],
                                fallbackName = state.entityNames[entry.entityId],
                                canVote = authState.isSignedIn && detail.isActive,
                                remaining = remaining,
                                onVote = { viewModel.vote(entry.entityId) },
                                onUnvote = { viewModel.unvote(entry.entityId) }
                            )
                        }
                    }
                }

                if (authState.isSignedIn && detail.isActive) {
                    ImasNote("タップで投票/取消 (残り${remaining}/${limit})")
                }

                if (authState.isSignedIn && detail.isActive && detail.candidateScope != CommunityApi.PollCandidateScope.MANUAL) {
                    ImasButton(
                        title = if (remaining > 0) "候補を追加して投票 (残り${remaining}/${limit})" else "投票済み (${limit}/${limit})",
                        onClick = { showPicker = true },
                        icon = Icons.Filled.AddCircle,
                        role = ImasButtonRole.PRIMARY,
                        size = ImasButtonSize.LARGE,
                        enabled = remaining > 0
                    )
                }

                // 自分の投票のシェアは締切後も残す (結果が出てからの方が話題になる)。
                val myVoteNames = detail.entries
                    .filter { it.mine }
                    .map { state.entityNames[it.entityId] ?: it.entityId }
                if (myVoteNames.isNotEmpty()) {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Text("あなたの投票 ${myVoteNames.size}/${voteLimitPerTarget()}", style = ImasTextRole.META.style, color = DS.ink3)
                        Spacer(Modifier.weight(1f))
                        SocialShareChip(
                            title = "投票をシェア",
                            payload = ShareMessage.pollVotesPayload(detail.id, detail.title, myVoteNames)
                        )
                    }
                }
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

    ImasConfirmDestructive(
        title = "このお題を削除しますか？",
        message = "ランキング・投票データも一緒に削除され、元に戻せません。",
        isPresented = showDeleteConfirm,
        onDismiss = { showDeleteConfirm = false },
        onConfirm = {
            // 削除できた時だけ戻る。一覧は再表示時の再ロードでこのお題が消える。
            viewModel.delete(onDeleted = onBack)
        },
        actionTitle = "削除"
    )

    if (state.deleteError != null) {
        ImasErrorAlert(message = state.deleteError, onDismiss = { viewModel.clearDeleteError() }, title = "エラー")
    }
}

/** 試聴に使える URL (http/https でホストがあるものだけ)。 */
private fun safeHttp(url: String?): String? {
    if (url.isNullOrEmpty()) return null
    val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return null
    val scheme = uri.scheme?.lowercase()
    return url.takeIf { (scheme == "https" || scheme == "http") && !uri.host.isNullOrEmpty() }
}

/**
 * ランキング 1 行。曲は試聴・歌唱者副題・長押しコピーを持ち、アイドル/ユニットは判子のアイコンで出す。
 * 投票ボタンだけを無効にし、残票切れでも行自体はいつでも開ける (iOS PollEntryRow と同じ)。
 */
@Composable
private fun PollEntryRow(
    rank: Int,
    entry: CommunityApi.PollEntry,
    totalVotes: Int,
    targetType: String,
    song: Song?,
    idol: Idol?,
    unit: ImasUnit?,
    fallbackName: String?,
    canVote: Boolean,
    remaining: Int,
    onVote: () -> Unit,
    onUnvote: () -> Unit
) {
    val title = when (targetType) {
        "idol" -> idol?.name
        "unit" -> unit?.displayName
        else -> song?.title
    } ?: fallbackName ?: entry.entityId
    val subtitle = if (targetType == "song") song?.let { it.unitName ?: it.singerLabel } else null
    val previewUrl = if (targetType == "song") safeHttp(song?.previewUrl) else null
    val playback by AudioPreviewManager.playbackState.collectAsState()
    val isPreviewing = previewUrl != null && song != null && playback.isPlaying(song.id)
    val share = if (totalVotes > 0) entry.voteCount.toDouble() / totalVotes else 0.0
    // 未投票だが残票が無い (この候補にはこれ以上投票できない)。
    val voteDisabled = !entry.mine && remaining <= 0

    ImasForecastRow(
        rank = rank,
        title = title,
        measure = ImasForecastMeasure.Votes(entry.voteCount, share = share),
        subtitle = subtitle,
        artworkUrl = if (targetType == "song") song?.artworkUrl else null,
        brand = if (targetType == "song") song?.brandId else null,
        avatar = if (targetType == "idol") ImasForecastAvatar(label = idol?.shortName ?: "?", seed = idol?.color, entityId = idol?.id) else null,
        unit = if (targetType == "unit") unit else null,
        previewUrl = previewUrl,
        isPreviewing = isPreviewing,
        onPreviewTap = { if (previewUrl != null && song != null) AudioPreviewManager.togglePreview(previewUrl, song.id) },
        isMine = entry.mine,
        onVote = if (canVote) {
            { if (!voteDisabled) { if (entry.mine) onUnvote() else onVote() } }
        } else null,
        voteLabel = "投票する",
        votedLabel = "投票済み",
        voteAccessibilityLabel = "投票",
        votedAccessibilityLabel = "投票を取消",
        voteDisabled = voteDisabled
    )
}
