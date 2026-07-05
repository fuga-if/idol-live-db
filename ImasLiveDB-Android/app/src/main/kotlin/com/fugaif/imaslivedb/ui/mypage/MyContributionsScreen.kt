package com.fugaif.imaslivedb.ui.mypage

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.community.LocalContributionLog
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme

/**
 * 自分の投稿累計の内訳画面。プロデュースタブ「投稿」タイル → ここに飛ぶ。
 * ローカル LocalContributionLog のカウントを内訳として並べる (iOS MyContributionsView の移植)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyContributionsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val log = remember { AppModule.from(context).localContributionLog }
    val counts by log.counts.collectAsState()
    val total = counts.values.sum()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("マイ投稿", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            SummaryCard(total = total)
            Breakdown(counts = counts)
            Text(
                "セトリ編集・コーレス・動画追加・タグ追加が累計に含まれます。再インストールするとカウントはリセットされます (端末ローカル記録)。",
                fontSize = 12.sp, color = DS.ink3
            )
        }
    }
}

@Composable
private fun SummaryCard(total: Int) {
    val t = ImasTheme.derive(null, null, dark = true)
    Column(
        modifier = Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(16.dp)).background(DS.surface)
            .padding(vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(Icons.Filled.EditNote, contentDescription = null, tint = t.accent, modifier = Modifier.size(36.dp))
        Spacer(Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.Bottom) {
            Text("$total", fontSize = 36.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            Text("件", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink3, modifier = Modifier.padding(start = 4.dp, bottom = 4.dp))
        }
        Text("コミュニティへの投稿累計", fontSize = 13.sp, color = DS.ink3, modifier = Modifier.padding(top = 4.dp))
    }
}

@Composable
private fun Breakdown(counts: Map<LocalContributionLog.Kind, Int>) {
    Column {
        ImasSectionHeader(title = "内訳", tight = true)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            LocalContributionLog.Kind.entries.forEach { kind ->
                BreakdownRow(kind = kind, count = counts[kind] ?: 0)
            }
        }
    }
}

@Composable
private fun BreakdownRow(kind: LocalContributionLog.Kind, count: Int) {
    val t = ImasTheme.derive(null, null, dark = true)
    Row(
        modifier = Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(12.dp)).background(DS.surface)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier.size(36.dp).clip(RoundedCornerShape(10.dp)).background(DS.fill),
            contentAlignment = Alignment.Center
        ) {
            Icon(kind.icon(), contentDescription = null, tint = t.accent, modifier = Modifier.size(18.dp))
        }
        Text(kind.label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, modifier = Modifier.padding(start = 12.dp).weight(1f))
        Text("$count", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
        Text("件", fontSize = 12.sp, color = DS.ink3, modifier = Modifier.padding(start = 2.dp))
    }
}

private fun LocalContributionLog.Kind.icon(): ImageVector = when (this) {
    LocalContributionLog.Kind.SETLIST_EDIT -> Icons.Filled.EditNote
    LocalContributionLog.Kind.CALL_RESPONSE -> Icons.Filled.Campaign
    LocalContributionLog.Kind.VIDEO -> Icons.Filled.Movie
    LocalContributionLog.Kind.TAG -> Icons.Filled.Sell
}
