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
import androidx.compose.material.icons.filled.AddCircle
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
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch

/** 投票・予想。Worker D1 のポールを表示し、選択肢に投票できる (端末ベース)。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PollsScreen(
    onBack: () -> Unit,
    onPollClick: (String) -> Unit = {},
    viewModel: PollsViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    var pickerForPollId by remember { mutableStateOf<String?>(null) }

    val context = LocalContext.current
    val authService = remember { AppModule.from(context).authService }
    val authState by authService.state.collectAsState()
    val scope = rememberCoroutineScope()
    fun signIn() { scope.launch { authService.signIn(context) } }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("投票・予想", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                }
            )
        }
    ) { padding ->
        if (state.isLoading) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        } else if (state.cards.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                ImasEmptyState(Icons.Filled.HowToVote, "投票はまだありません", "進行中の投票・予想がここに表示されます。")
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
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
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(16.dp)) {
        Text(card.poll.title, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 8.dp)) {
            Text("${detail?.totalVotes ?: 0}票", fontSize = 12.sp, color = DS.ink3)
            if (detail != null) ScopeBadge(detail)
        }
        if (detail != null) {
            PollEntriesList(detail.entries, card.entityNames, detail.totalVotes, isSignedIn, onToggleVote)
        }
        if (isSignedIn) {
            Text("タップで投票/取消 (残り${remaining}/3)", fontSize = 11.sp, color = DS.ink3, modifier = Modifier.padding(top = 6.dp))
        }

        // 候補が指定制 (manual) でなければ、新規候補を追加できる (曲・アイドル共通)。
        if (isSignedIn && detail?.candidateScope != CommunityApi.PollCandidateScope.MANUAL) {
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
