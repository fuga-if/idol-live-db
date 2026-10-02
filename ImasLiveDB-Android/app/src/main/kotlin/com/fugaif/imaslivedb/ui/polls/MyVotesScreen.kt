package com.fugaif.imaslivedb.ui.polls

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.HowToVote
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole

/**
 * 自分が投票したお題の履歴。プロデュースタブ「投票」タイル → ここに飛ぶ。iOS MyVotesView の移植。
 * サーバに my-votes API が無いため、端末ローカル (LocalPollVoteLog) 駆動の履歴になっている
 * (再インストールで消えうる)。詳細画面への遷移導線は未配線のため、選択肢はラベル表示のみ。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyVotesScreen(
    onBack: () -> Unit,
    viewModel: MyVotesViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("マイ投票") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                }
            )
        }
    ) { padding ->
        when {
            state.isLoading && state.entries.isEmpty() -> {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { ImasLoadingState() }
            }
            state.entries.isEmpty() -> {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    ImasEmptyState(
                        Icons.Filled.HowToVote,
                        "まだ投票していません",
                        "みんなの投票でお題に投票すると、ここに履歴が残ります"
                    )
                }
            }
            else -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentPadding = PaddingValues(vertical = DS.Space.gap)
                ) {
                    items(state.entries, key = { it.poll.id }) { entry ->
                        ImasListSection(title = entry.poll.title, count = entry.poll.statusLabel) {
                            entry.choices.forEach { choice ->
                                ImasRow(
                                    title = choice.label,
                                    leading = ImasRowLeading.Icon(Icons.Filled.CheckCircle, tone = ImasIconTileTone.POSITIVE),
                                    density = ImasRowDensity.COMPACT,
                                    titleRole = ImasTextRole.ROW_LABEL,
                                    titleLineLimit = 2
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
