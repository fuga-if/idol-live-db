package com.fugaif.imaslivedb.ui.filtered

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Mic
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
 * 「◯◯のライブ」「N年のライブ」の一覧 (iOS `FilteredEventsView` の移植)。
 *
 * 行はライブ一覧と同じ [FilteredEventRow]。件数だけの小見出しを頭に置き、
 * 年やブランドでの並べ替え UI は持たない (絞った結果を最初の公演日の降順で見せる画面)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FilteredEventsScreen(
    kind: String,
    value: String,
    onBack: () -> Unit,
    onEventClick: (String) -> Unit,
    viewModel: FilteredEventsViewModel = viewModel(
        key = "$kind/$value",
        factory = FilteredEventsViewModel.Factory(
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
                state.events.isEmpty() -> FilteredEmptyState(Icons.Filled.Mic, "ライブが見つかりません")
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    item(key = "count") { FilteredCountHeader("${state.events.size}件") }
                    items(state.events, key = { it.event.id }) { item ->
                        FilteredEventRow(item) { onEventClick(item.event.id) }
                        HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                    }
                }
            }
        }
    }
}
