package com.fugaif.imaslivedb.ui.polls

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasAwardChip

/**
 * 指定エンティティ(曲/アイドル)が「みんなの投票」の終了お題で取った順位をバッジ表示する。
 * 実績が無ければ何も描画しない。アイドル詳細・曲詳細のコミュニティタブに差し込んで使う。
 * タップで対象お題の詳細 (PollDetailScreen) へ遷移する。iOS PollAchievementBadges の移植。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PollAchievementBadges(entityId: String, onOpenPoll: (String) -> Unit) {
    val context = LocalContext.current
    var achievements by remember(entityId) { mutableStateOf<List<CommunityApi.PollAchievement>>(emptyList()) }

    LaunchedEffect(entityId) {
        val api = AppModule.from(context).communityApi
        achievements = runCatching { api.pollAchievements(entityId) }.getOrDefault(emptyList())
    }

    if (achievements.isEmpty()) return

    FlowRow(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        achievements.forEach { a ->
            Box(modifier = Modifier.clickable { onOpenPoll(a.pollId) }) {
                ImasAwardChip(title = a.title, rank = a.rank)
            }
        }
    }
}
