package com.fugaif.imaslivedb.ui.events

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.auth.canEdit
import com.fugaif.imaslivedb.data.auth.startCommunityEdit
import com.fugaif.imaslivedb.ui.components.CommunityLoginPromptDialog
import com.fugaif.imaslivedb.ui.components.ImasArtwork
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.polls.SongPollCandidatePicker
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import uniffi.imas_core.ForecastSongRecord
import uniffi.imas_core.voteLimitPerTarget
import kotlin.math.roundToInt

/**
 * 未来の公演のセトリ予想。iOS `SetlistPredictionView` の移植で、みんなの予想 (投票) と
 * 機械予測 (コアの `setlistForecast`) を縦に並べる。
 *
 * iOS にある Apple Music のプレイリスト作成・プレビュー連続再生・予想のシェア・
 * 歌唱メンバー予想は、Android に土台が無いのでまだ出さない。
 *
 * @param seed 公演のブランド色 (hex)。投稿導線の差し色。
 */
@Composable
fun SetlistPredictionSection(
    showId: String,
    seed: String?,
    viewModel: SetlistPredictionViewModel = viewModel(
        key = "prediction_$showId",
        factory = SetlistPredictionViewModel.factory(showId)
    )
) {
    val state by viewModel.uiState.collectAsState()
    val forecast by viewModel.forecast.state.collectAsState()
    val authState by viewModel.authState.collectAsState()
    val showLoginPrompt by viewModel.loginPrompt.collectAsState()
    val isSignedIn = remember(authState) { authState.canEdit }
    var showPicker by remember { mutableStateOf(false) }

    /** ログインが要る操作の共通ゲート。未ログインならログイン誘導、BAN は無反応。 */
    fun requireLogin(action: () -> Unit) {
        authState.startCommunityEdit(promptLogin = viewModel::requestLogin, present = action)
    }

    val t = ImasTheme.derive(seed, null, dark = true)
    val limit = remember { voteLimitPerTarget().toInt() }
    val remaining = state.remaining
    // 未ログインはログイン誘導のため常に押せる (残票はログイン後に効く)。
    val canAddVote = !isSignedIn || remaining > 0

    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        PredictionHeader(
            totalVotes = state.totalVotes,
            remainingLabel = if (isSignedIn) "残り$remaining/$limit" else null,
            remainingIsZero = remaining <= 0,
            canAdd = canAddVote,
            accent = t.accent,
            onAdd = { requireLogin { showPicker = true } }
        )

        if (!isSignedIn) {
            LoginHintRow(accent = t.accent, onLogin = viewModel::requestLogin)
        }

        when {
            state.isLoading && state.predictions.isEmpty() -> InlineLoading()
            state.predictions.isEmpty() -> ImasEmptyState(
                icon = Icons.Filled.LibraryMusic,
                title = "まだ予想がありません",
                message = "「予想を追加」から、来そうな曲に投票しよう",
                seed = seed
            )
            else -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ListCard {
                    state.predictions.forEachIndexed { index, row ->
                        if (index > 0) RowDivider()
                        PredictionRowView(
                            row = row,
                            rank = index + 1,
                            seed = seed,
                            // 残票 0 なら未投票曲は押せない (投票済みの取り消しは常にできる)。
                            canAddVote = remaining > 0,
                            onVote = { requireLogin { viewModel.toggleVote(row) } }
                        )
                    }
                }
                val mine = state.myVotedSongIds.size
                if (mine > 0) {
                    Text(
                        "あなたの予想 $mine/$limit",
                        fontSize = 12.sp,
                        color = DS.ink3,
                        modifier = Modifier.padding(start = 4.dp)
                    )
                }
            }
        }

        state.errorMessage?.let { ErrorRow(it) }

        ForecastBlock(
            forecast = forecast,
            predictedSongIds = state.predictedSongIds,
            canAdd = canAddVote,
            seed = seed,
            onPromote = { songId -> requireLogin { viewModel.promoteForecast(songId) } }
        )
    }

    if (showPicker) {
        SongPollCandidatePicker(
            alreadySelected = state.myVotedSongIds.toSet(),
            remaining = remaining,
            onDismiss = { showPicker = false },
            onConfirm = { ids ->
                showPicker = false
                viewModel.addPredictions(ids)
            }
        )
    }

    if (showLoginPrompt) {
        CommunityLoginPromptDialog(
            message = "セトリ予想の投票にはログインが必要です。",
            onDismiss = viewModel::dismissLoginPrompt
        )
    }
}

/** 見出し「セトリ予想」+ 票数 + 残り票 + 「予想を追加」。 */
@Composable
private fun PredictionHeader(
    totalVotes: Int,
    remainingLabel: String?,
    remainingIsZero: Boolean,
    canAdd: Boolean,
    accent: Color,
    onAdd: () -> Unit
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("セトリ予想", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DS.ink)
        if (totalVotes > 0) {
            Text(
                "${totalVotes}票",
                fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3,
                modifier = Modifier.padding(start = 8.dp)
            )
        }
        // 残り票数はログイン済みのときだけ意味を持つ。
        if (remainingLabel != null) {
            Text(
                remainingLabel,
                fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                color = if (remainingIsZero) DS.danger else DS.ink3,
                modifier = Modifier.padding(start = 8.dp)
            )
        }
        Spacer(Modifier.weight(1f))
        val fg = if (canAdd) accent else DS.ink3
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(50))
                .clickable(enabled = canAdd, onClick = onAdd)
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = fg, modifier = Modifier.size(16.dp))
            Text("予想を追加", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = fg)
        }
    }
}

/** 未ログインのときの一言 (押すとログイン)。iOS `InlineLoginPrompt`。 */
@Composable
private fun LoginHintRow(accent: Color, onLogin: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(DS.surface)
            .clickable(onClick = onLogin)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            "セトリ予想の投票にはログインが必要です",
            fontSize = 13.sp, color = DS.ink2,
            modifier = Modifier.weight(1f)
        )
        Text("ログイン", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = accent)
    }
}

/** 予想の 1 行。順位 + ジャケ + 曲名/票数 + 投票トグル。 */
@Composable
private fun PredictionRowView(
    row: PredictionRow,
    rank: Int,
    seed: String?,
    canAddVote: Boolean,
    onVote: () -> Unit
) {
    val t = ImasTheme.derive(seed, null, dark = true)
    val voteDisabled = !row.hasUserVoted && !canAddVote
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        RankText(rank)
        ImasArtwork(title = row.title, seed = seed, brand = row.brandId, size = 44.dp, imageUrl = row.artworkUrl)
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(row.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 2)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.ThumbUp, contentDescription = null, tint = DS.ink3, modifier = Modifier.size(11.dp))
                Text("${row.voteCount}票", fontSize = 12.sp, fontFamily = FontFamily.Monospace, color = DS.ink2)
            }
        }
        CapsuleButton(
            enabled = !voteDisabled,
            filled = row.hasUserVoted,
            accent = t.accent,
            onAccent = t.onAccent,
            chipBg = t.chipBg,
            description = if (row.hasUserVoted) "投票を取り消す" else "この曲に投票",
            onClick = onVote
        ) { fg ->
            Icon(
                if (row.hasUserVoted) Icons.Filled.ThumbUp else Icons.Outlined.ThumbUp,
                contentDescription = null, tint = fg, modifier = Modifier.size(15.dp)
            )
            Text(if (row.hasUserVoted) "投票済" else "予想", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = fg)
        }
    }
}

/** 機械予測の節。読み込みに失敗したとき・出す曲が無いときは節ごと出さない。 */
@Composable
private fun ForecastBlock(
    forecast: SetlistForecastModel.State,
    predictedSongIds: Set<String>,
    canAdd: Boolean,
    seed: String?,
    onPromote: (String) -> Unit
) {
    when (forecast.phase) {
        SetlistForecastModel.Phase.Loading -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            ForecastHeading(note = null)
            InlineLoading()
        }
        SetlistForecastModel.Phase.Unavailable -> Unit
        is SetlistForecastModel.Phase.Loaded -> {
            val songs = forecast.visibleSongs(predictedSongIds)
            if (songs.isEmpty()) return
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ForecastHeading(note = forecast.castUnannouncedNote)
                ListCard {
                    songs.forEachIndexed { index, song ->
                        if (index > 0) RowDivider()
                        ForecastRowView(
                            song = song,
                            seed = seed,
                            canPromote = canAdd && forecast.promotingSongId == null,
                            isPromoting = forecast.promotingSongId == song.songId,
                            onPromote = { onPromote(song.songId) }
                        )
                    }
                }
            }
        }
    }
}

/** 「機械予測」の見出しと注記。出演者未発表の注記はコアの label をそのまま出す。 */
@Composable
private fun ForecastHeading(note: String?) {
    Column(modifier = Modifier.padding(start = 4.dp, top = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("機械予測", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DS.ink)
        Text("過去のセトリから推定", fontSize = 12.sp, color = DS.ink3)
        if (note != null) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = DS.ink2, modifier = Modifier.size(13.dp))
                Text(note, fontSize = 12.sp, color = DS.ink2)
            }
        }
    }
}

/** 機械予測の 1 行。順位・曲名・点数・理由の札 (コアの label) と「予想に入れる」。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ForecastRowView(
    song: ForecastSongRecord,
    seed: String?,
    canPromote: Boolean,
    isPromoting: Boolean,
    onPromote: () -> Unit
) {
    val t = ImasTheme.derive(seed, null, dark = true)
    // 札は表示の都合で先頭 2 個まで (並びはコアの優先順)。
    val reasonLabels = song.reasons.take(2).map { it.label }
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        RankText(song.rank.toInt(), modifier = Modifier.padding(top = 2.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    song.title,
                    fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 2,
                    modifier = Modifier.weight(1f, fill = false)
                )
                Text(
                    "${(song.score * 100).roundToInt()}%",
                    fontSize = 12.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace,
                    color = DS.ink2
                )
            }
            if (reasonLabels.isNotEmpty()) {
                // 札は省略せずに全文を出す。横に収まらなければ折り返す。
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    reasonLabels.forEach { label ->
                        Text(
                            label,
                            fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2,
                            modifier = Modifier
                                .clip(RoundedCornerShape(50))
                                .background(DS.fill)
                                .padding(horizontal = 8.dp, vertical = 3.dp)
                        )
                    }
                }
            }
        }
        CapsuleButton(
            enabled = canPromote,
            filled = false,
            accent = t.accent,
            onAccent = t.onAccent,
            chipBg = t.chipBg,
            description = "${song.title}を予想に入れる",
            onClick = onPromote
        ) { fg ->
            if (isPromoting) {
                CircularProgressIndicator(color = t.accent, strokeWidth = 2.dp, modifier = Modifier.size(14.dp))
            } else {
                Text("予想に入れる", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = fg)
            }
        }
    }
}

/** 行の右端の丸いボタン (投票 / 予想に入れる)。 */
@Composable
private fun CapsuleButton(
    enabled: Boolean,
    filled: Boolean,
    accent: Color,
    onAccent: Color,
    chipBg: Color,
    description: String,
    onClick: () -> Unit,
    content: @Composable (fg: Color) -> Unit
) {
    val fg = when {
        filled -> onAccent
        enabled -> accent
        else -> DS.ink3
    }
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(if (filled) accent else chipBg)
            .clickable(enabled = enabled, onClick = onClick)
            .semantics { contentDescription = description }
            .padding(horizontal = 11.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) { content(fg) }
}

@Composable
private fun RankText(rank: Int, modifier: Modifier = Modifier) {
    Text(
        "$rank",
        fontSize = 12.sp, fontFamily = FontFamily.Monospace, color = DS.ink3,
        textAlign = TextAlign.End,
        modifier = modifier.width(22.dp)
    )
}

/** 角丸のカード (iOS `ImasListContainer`)。行の間は [RowDivider]。 */
@Composable
private fun ListCard(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(DS.surface)
    ) { content() }
}

@Composable
private fun RowDivider() {
    HorizontalDivider(color = DS.sep, thickness = 0.5.dp)
}

@Composable
private fun InlineLoading() {
    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 16.dp), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
    }
}

@Composable
private fun ErrorRow(message: String) {
    Row(
        modifier = Modifier.padding(start = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Icon(Icons.Filled.Warning, contentDescription = null, tint = DS.danger, modifier = Modifier.size(13.dp))
        Text(message, fontSize = 12.sp, color = DS.danger)
    }
}
