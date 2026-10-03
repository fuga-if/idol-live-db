package com.fugaif.imaslivedb.ui.playlists

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.PlaylistSummary
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasListSummary
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasTextInputDialog
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * プレイリストの一覧。プロデュースタブから開く。iOS `PlaylistsView` と対。
 * プレイリストは**端末ローカル唯一データ** (クラウドにもサーバにも無い)。
 */
data class PlaylistsUiState(
    val summaries: List<PlaylistSummary> = emptyList(),
    val isLoading: Boolean = true
)

class PlaylistsViewModel(app: Application) : AndroidViewModel(app) {
    private val repository = AppModule.from(app).playlistRepository

    private val _uiState = MutableStateFlow(PlaylistsUiState())
    val uiState: StateFlow<PlaylistsUiState> = _uiState.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _uiState.value = PlaylistsUiState(summaries = repository.summaries(), isLoading = false)
        }
    }

    fun create(name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        viewModelScope.launch {
            repository.create(trimmed)
            load()
        }
    }

    fun delete(id: String) {
        viewModelScope.launch {
            repository.delete(id)
            load()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaylistsScreen(
    onBack: () -> Unit,
    onPlaylistClick: (String) -> Unit,
    viewModel: PlaylistsViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var isNaming by rememberSaveable { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("プレイリスト") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                actions = {
                    IconButton(onClick = { isNaming = true }) {
                        Icon(Icons.Filled.Add, contentDescription = "新しいプレイリスト")
                    }
                }
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when {
                state.isLoading -> ImasLoadingState()
                state.summaries.isEmpty() -> ImasEmptyState(
                    icon = Icons.Filled.MusicNote,
                    title = "プレイリストがありません",
                    message = "曲の詳細の記号のボタンから、曲を足せます。",
                    actionTitle = "新しいプレイリスト",
                    onAction = { isNaming = true }
                )
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    item(key = "count") {
                        ImasListSummary<Unit>(count = state.summaries.size, unit = "件")
                    }
                    items(state.summaries, key = { it.id }) { summary ->
                        PlaylistRow(
                            summary = summary,
                            onClick = { onPlaylistClick(summary.id) },
                            onDelete = { viewModel.delete(summary.id) }
                        )
                    }
                    item { Spacer(Modifier.height(DS.Space.section)) }
                }
            }
        }
    }

    if (isNaming) {
        ImasTextInputDialog(
            title = "新しいプレイリスト",
            confirmLabel = "作る",
            onDismiss = { isNaming = false },
            onConfirm = { name -> viewModel.create(name); isNaming = false }
        )
    }
}

@Composable
private fun PlaylistRow(summary: PlaylistSummary, onClick: () -> Unit, onDelete: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        ImasNavRow(
            title = summary.playlist.name,
            subtitle = "${summary.songCount}曲",
            icon = Icons.Filled.MusicNote,
            showsChevron = false,
            modifier = Modifier.weight(1f),
            onClick = onClick
        )
        IconButton(onClick = onDelete) {
            Icon(Icons.Filled.Close, contentDescription = "削除")
        }
    }
}

