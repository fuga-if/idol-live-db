package com.fugaif.imaslivedb.ui.idols

import android.app.Application
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.theme.DS

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
                state.isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                state.idols.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    ImasEmptyState(icon = Icons.Filled.Person, title = "アイドルが見つかりません")
                }
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    item(key = "count") {
                        Text(
                            "${state.idols.size}人",
                            fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                        )
                    }
                    items(state.idols, key = { it.id }) { idol ->
                        IdolNameRow(idol) { onIdolClick(idol.id) }
                        HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                    }
                }
            }
        }
    }
}

/** iOS `IdolNameRow` と同じ並び (アバター + 名前 + よみ + シェブロン)。 */
@Composable
private fun IdolNameRow(idol: Idol, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 40.dp)
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Text(
                idol.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            idol.nameKana?.takeIf { it.isNotEmpty() }?.let {
                Text(it, fontSize = 12.sp, color = DS.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight, null,
            tint = DS.ink3, modifier = Modifier.size(16.dp)
        )
    }
}
