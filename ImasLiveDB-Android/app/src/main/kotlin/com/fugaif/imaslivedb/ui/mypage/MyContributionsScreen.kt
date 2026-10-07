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
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeSpec
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasRecordRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.data.community.ContributionFeedbackService
import com.fugaif.imaslivedb.ui.edit.EditFeedFormat
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.QueueMusic
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import uniffi.imas_core.relativeTimes

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
    val feedbackService = remember { AppModule.from(context).contributionFeedbackService }
    val feedback by feedbackService.feedback.collectAsState()
    LaunchedEffect(Unit) { feedbackService.refresh(force = true) }
    // 開いている間は NEW を見せたまま、閉じたときに既読にする。
    DisposableEffect(Unit) { onDispose { feedbackService.markGoodsSeen() } }

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

            feedback?.let { FeedbackSections(it) }

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

/** 届いた Good と、先週セトリが見られた数 (iOS MyContributionsView.feedbackSections)。 */
@Composable
private fun FeedbackSections(feedback: ContributionFeedbackService.Feedback) {
    val reach = feedback.setlistReach
    if (reach.viewers > 0) {
        ImasSection(
            "先週の反響",
            style = ImasSectionHeaderStyle.SMALL,
            footer = "あなたが入れたセトリの公演ページを見た人の数です。公演ごとに 1 人 1 回で数え、いくつも見た人はその数だけ数えます (のべ人数)。"
        ) {
            ImasStatGrid(columns = 2) {
                ImasStatTile(icon = Icons.Filled.Visibility, value = "${reach.viewers}", unit = "人", label = "セトリを見た人 (のべ)")
                ImasStatTile(icon = Icons.Filled.QueueMusic, value = "${reach.shows}", unit = "公演", label = "見られた公演")
            }
        }
    }
    if (feedback.goods.isNotEmpty()) {
        val times = remember(feedback.goods) {
            relativeTimes(feedback.goods.map { it.latestGoodAt }, System.currentTimeMillis())
        }
        ImasSection("届いた Good", style = ImasSectionHeaderStyle.SMALL) {
            ImasCardList {
                feedback.goods.forEachIndexed { index, good ->
                    if (index > 0) ImasRowDivider()
                    val type = good.recordType ?: ""
                    ImasRecordRow(
                        title = good.summary ?: EditFeedFormat.recordTypeLabel(type),
                        icon = EditFeedFormat.recordTypeIcon(type),
                        tone = ImasIconTileTone.THEMED,
                        subtitle = "Good ${good.goodCount} ・ ${times.getOrElse(index) { "" }}",
                        badges = if (good.newGoodCount > 0) {
                            listOf(ImasBadgeSpec("NEW +${good.newGoodCount}", ImasBadgeKind.NEW))
                        } else emptyList()
                    )
                }
            }
        }
    }
}

private fun LocalContributionLog.Kind.icon(): ImageVector = when (this) {
    LocalContributionLog.Kind.SETLIST_EDIT -> Icons.Filled.EditNote
    LocalContributionLog.Kind.VIDEO -> Icons.Filled.Movie
    LocalContributionLog.Kind.TAG -> Icons.Filled.Sell
}
