package com.fugaif.imaslivedb.ui.mypage

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.community.LocalContributionLog
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasStatGrid
import com.fugaif.imaslivedb.ui.designsystem.ImasStatTile

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
                title = { Text("マイ投稿") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る") }
                }
            )
        }
    ) { padding ->
        ImasPage(modifier = Modifier.padding(padding)) {
            ImasStatTile(
                icon = Icons.Filled.EditNote,
                value = "$total",
                unit = "件",
                label = "コミュニティへの投稿累計"
            )

            ImasSection("内訳", style = ImasSectionHeaderStyle.SMALL) {
                ImasStatGrid(columns = 2) {
                    LocalContributionLog.Kind.entries.forEach { kind ->
                        ImasStatTile(
                            icon = kind.icon(),
                            value = "${counts[kind] ?: 0}",
                            unit = "件",
                            label = kind.label
                        )
                    }
                }
            }

            ImasNote("セトリ編集・動画追加・タグ追加が累計に含まれます。再インストールするとカウントはリセットされます (端末ローカル記録)。")
        }
    }
}

private fun LocalContributionLog.Kind.icon(): ImageVector = when (this) {
    LocalContributionLog.Kind.SETLIST_EDIT -> Icons.Filled.EditNote
    LocalContributionLog.Kind.VIDEO -> Icons.Filled.Movie
    LocalContributionLog.Kind.TAG -> Icons.Filled.Sell
}
