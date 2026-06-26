package com.fugaif.imaslivedb.ui.polls

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme

/** 投票・予想。Worker D1 のポールを表示し、選択肢に投票できる (端末ベース)。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PollsScreen(
    onBack: () -> Unit,
    viewModel: PollsViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
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
                items(state.cards, key = { it.poll.id }) { card ->
                    PollCardView(card) { entityId -> viewModel.vote(card.poll.id, entityId) }
                }
            }
        }
    }
}

@Composable
private fun PollCardView(card: PollCard, onVote: (String) -> Unit) {
    val detail = card.detail
    val total = (detail?.totalVotes ?: 0).coerceAtLeast(1)
    Column(Modifier.fillMaxWidth().padding(16.dp)) {
        Text(card.poll.title, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
        Text("${detail?.totalVotes ?: 0}票", fontSize = 12.sp, color = DS.ink3, modifier = Modifier.padding(bottom = 8.dp))
        val t = ImasTheme.derive(null, null, dark = true)
        detail?.entries?.sortedByDescending { it.voteCount }?.forEach { entry ->
            val name = card.entityNames[entry.entityId] ?: entry.entityId
            val pct = (entry.voteCount.toFloat() / total).coerceIn(0f, 1f)
            Column(
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .then(if (entry.mine) Modifier.border(1.5.dp, DS.pick, RoundedCornerShape(10.dp)) else Modifier)
                    .background(DS.surface)
                    .clickable { onVote(entry.entityId) }
                    .padding(horizontal = 12.dp, vertical = 10.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(name, fontSize = 14.sp, fontWeight = if (entry.mine) FontWeight.Bold else FontWeight.Medium,
                        color = DS.ink, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text("${entry.voteCount}", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
                }
                Box(Modifier.padding(top = 6.dp).fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)).background(DS.fill)) {
                    Box(Modifier.fillMaxWidth(pct).fillMaxHeight().clip(RoundedCornerShape(3.dp)).background(t.accent))
                }
            }
        }
        Text("タップで投票", fontSize = 11.sp, color = DS.ink3, modifier = Modifier.padding(top = 6.dp))
    }
}
