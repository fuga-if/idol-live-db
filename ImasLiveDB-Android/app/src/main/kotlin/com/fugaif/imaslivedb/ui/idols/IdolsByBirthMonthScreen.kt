package com.fugaif.imaslivedb.ui.idols

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Person
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasCardListStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasIdolRow
import com.fugaif.imaslivedb.ui.designsystem.ImasListSummary
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.theme.imasRowPress

/**
 * 誕生月で絞ったアイドル一覧。アイドル詳細のプロフィール「誕生日」行から開く。
 *
 * iOS の `FilteredIdolsView(criterion: .birthMonth)` と同じ中身 (件数見出し + 名前行) を、
 * Android のタブ内スタックへ載せ替えたもの。**どの行が押せるか**はコアの `RowAction` が
 * 決めるので、この画面は「押されたときの行き先」を実在させるためにある。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IdolsByBirthMonthScreen(
    month: Int,
    onBack: () -> Unit,
    onIdolClick: (String) -> Unit,
    // ViewModel は遷移エントリ単位で持たれるので、3 月と 4 月を続けて積んでも別インスタンスになる
    // (IdolDetailScreen が idolId を Factory に渡しているのと同じ形)。
    viewModel: IdolsByBirthMonthViewModel = viewModel(
        factory = IdolsByBirthMonthViewModel.Factory(
            LocalContext.current.applicationContext as Application, month
        )
    )
) {
    val state by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("${month}月生まれのアイドル", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when {
                state.isLoading -> ImasLoadingState(modifier = Modifier.fillMaxSize())
                state.idols.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    ImasEmptyState(icon = Icons.Filled.Person, title = "アイドルが見つかりません")
                }
                // iOS `FilteredIdolsView(criterion: .birthMonth)` と同じ中身 (ImasListSummary + ImasIdolRow)。
                // よみの併記は Android だけの要素 (iOS 版はアイドル名のみ) なので subtitle として残す。
                else -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    ImasListSummary<Unit>(count = state.idols.size, unit = "人")
                    ImasCardList(items = state.idols, style = ImasCardListStyle.PLAIN, key = { it.id }) { idol ->
                        ImasIdolRow(
                            idol = idol,
                            subtitle = idol.nameKana?.takeIf { it.isNotEmpty() },
                            trailing = ImasRowTrailing.Chevron,
                            density = ImasRowDensity.COMPACT,
                            modifier = Modifier.imasRowPress(onClick = { onIdolClick(idol.id) })
                        )
                    }
                }
            }
        }
    }
}
