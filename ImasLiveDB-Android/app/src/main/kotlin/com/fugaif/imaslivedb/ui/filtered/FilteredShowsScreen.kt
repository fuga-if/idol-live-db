package com.fugaif.imaslivedb.ui.filtered

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ConfirmationNumber
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
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * 「この会場での公演」「この日の公演」の一覧 (iOS `FilteredShowsView` の移植)。
 *
 * 会場での一覧は数年ぶんが並ぶので年で束ねる。見出しはライブ一覧と同じ [ImasSectionHeader]
 * (tight) を使う — 同じ「年の区切り」が画面ごとに別の見た目になると、束ね方が違うように見える。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FilteredShowsScreen(
    kind: String,
    value: String,
    onBack: () -> Unit,
    onShowClick: (String) -> Unit,
    viewModel: FilteredShowsViewModel = viewModel(
        key = "$kind/$value",
        factory = FilteredShowsViewModel.Factory(
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
                state.groups.isEmpty() -> FilteredEmptyState(Icons.Filled.ConfirmationNumber, "公演が見つかりません")
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    item(key = "count") { FilteredCountHeader("${state.showCount}公演") }
                    state.groups.forEach { group ->
                        item(key = "year_${group.year}") {
                            ImasSectionHeader(title = "${group.year}年", tight = true)
                        }
                        items(group.rows, key = { it.showId }) { row ->
                            FilteredShowRow(
                                title = row.title,
                                subtitle = row.subtitle,
                                brandId = row.brandId,
                                rainbow = row.rainbow
                            ) { onShowClick(row.showId) }
                            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
                        }
                    }
                }
            }
        }
    }
}
