package com.fugaif.imaslivedb.ui.polls

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme

/** 投票にはログインが必要です、のバナー (PollsScreen/PollDetailScreen 共通)。 */
@Composable
fun LoginPromptBanner(onSignIn: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
            .clip(RoundedCornerShape(10.dp)).background(DS.surface).padding(16.dp)
    ) {
        Text("投票にはログインが必要です", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
        Button(onClick = onSignIn, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
            Text("Googleでログイン")
        }
    }
}

/** お題の候補スコープ (ブランド限定 / 指定候補) を示す小さなチップ。 `all` の時は何も出さない。 */
@Composable
fun ScopeBadge(detail: CommunityApi.PollDetail) {
    val (icon, label) = when (detail.candidateScope) {
        CommunityApi.PollCandidateScope.ALL -> return
        CommunityApi.PollCandidateScope.BRAND -> {
            val n = detail.scopeBrandIds.size
            Icons.Filled.Sell to if (n <= 1) "ブランド限定" else "ブランド限定×$n"
        }
        CommunityApi.PollCandidateScope.MANUAL -> {
            Icons.AutoMirrored.Filled.List to "指定候補${detail.scopeEntityIds.size}件"
        }
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .padding(start = 8.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(DS.fill)
            .padding(horizontal = 8.dp, vertical = 3.dp)
    ) {
        Icon(icon, contentDescription = null, tint = DS.ink2, modifier = Modifier.size(12.dp))
        Text(label, fontSize = 11.sp, color = DS.ink2, modifier = Modifier.padding(start = 4.dp))
    }
}

/** お題候補の投票バー一覧 (票数降順・自分の一票をハイライト・タップでトグル)。PollsScreen/PollDetailScreen 共通。 */
@Composable
fun PollEntriesList(
    entries: List<CommunityApi.PollEntry>,
    entityNames: Map<String, String>,
    totalVotes: Int,
    isSignedIn: Boolean,
    onToggleVote: (String, Boolean) -> Unit
) {
    val total = totalVotes.coerceAtLeast(1)
    val t = ImasTheme.derive(null, null, dark = true)
    entries.sortedByDescending { it.voteCount }.forEach { entry ->
        val name = entityNames[entry.entityId] ?: entry.entityId
        val pct = (entry.voteCount.toFloat() / total).coerceIn(0f, 1f)
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
                .clip(RoundedCornerShape(10.dp))
                .then(if (entry.mine) Modifier.border(1.5.dp, DS.pick, RoundedCornerShape(10.dp)) else Modifier)
                .background(DS.surface)
                .then(if (isSignedIn) Modifier.clickable { onToggleVote(entry.entityId, entry.mine) } else Modifier)
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
}
