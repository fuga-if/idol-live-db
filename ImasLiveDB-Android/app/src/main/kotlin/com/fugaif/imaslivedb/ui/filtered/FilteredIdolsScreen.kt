package com.fugaif.imaslivedb.ui.filtered

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * 絞り込んだアイドル一覧 (iOS `FilteredIdolsView` の移植)。
 *
 * ブランド / 星座 / 出身地 / 血液型 の 4 通り。誕生月だけは既存の
 * [com.fugaif.imaslivedb.ui.idols.IdolsByBirthMonthScreen] が同じ役割を持っており、
 * プロフィール行の行き先としてコア (RowAction) が名指ししているのでそちらのまま。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FilteredIdolsScreen(
    kind: String,
    value: String,
    onBack: () -> Unit,
    onIdolClick: (String) -> Unit,
    viewModel: FilteredIdolsViewModel = viewModel(
        key = "$kind/$value",
        factory = FilteredIdolsViewModel.Factory(
            LocalContext.current.applicationContext as Application, kind, value
        )
    )
) {
    val state by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(state.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
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
                state.idols.isEmpty() -> FilteredEmptyState(Icons.Filled.Person, "アイドルが見つかりません")
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    item(key = "count") { FilteredCountHeader("${state.idols.size}人") }
                    items(state.idols, key = { it.id }) { idol ->
                        FilteredIdolRow(idol) { onIdolClick(idol.id) }
                        HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                    }
                }
            }
        }
    }
}
