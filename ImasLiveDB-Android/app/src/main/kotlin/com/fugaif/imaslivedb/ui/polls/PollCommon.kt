package com.fugaif.imaslivedb.ui.polls

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Sell
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.ui.designsystem.ImasBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.theme.DS

/** お題の候補スコープ (ブランド限定 / 指定候補) を示す小さな札。 `all` の時は何も出さない。 */
@Composable
fun ScopeBadge(detail: CommunityApi.PollDetail, modifier: Modifier = Modifier) =
    ScopeBadge(detail.candidateScope, detail.scopeBrandIds.size, detail.scopeEntityIds.size, modifier)

/** 一覧の行 (要約だけを持つ) 用。 */
@Composable
fun ScopeBadge(poll: CommunityApi.PollSummary, modifier: Modifier = Modifier) =
    ScopeBadge(poll.candidateScope, poll.scopeBrandIds.size, poll.scopeEntityIds.size, modifier)

@Composable
private fun ScopeBadge(scope: CommunityApi.PollCandidateScope, brandCount: Int, entityCount: Int, modifier: Modifier = Modifier) {
    val (icon, label) = when (scope) {
        CommunityApi.PollCandidateScope.ALL -> return
        CommunityApi.PollCandidateScope.BRAND ->
            Icons.Filled.Sell to if (brandCount <= 1) "ブランド限定" else "ブランド限定×$brandCount"
        CommunityApi.PollCandidateScope.MANUAL ->
            Icons.AutoMirrored.Filled.List to "指定候補${entityCount}件"
    }
    ImasBadge(text = label, icon = icon, kind = ImasBadgeKind.NEUTRAL, modifier = modifier.padding(start = DS.Space.gapTight))
}

