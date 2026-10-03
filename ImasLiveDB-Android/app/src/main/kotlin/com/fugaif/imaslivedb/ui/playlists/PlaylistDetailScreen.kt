package com.fugaif.imaslivedb.ui.playlists

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Playlist
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.PlaylistPlayback
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasListSummary
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasTextInputDialog
import com.fugaif.imaslivedb.ui.components.ImasSongRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.playlistMoveSong

/**
 * プレイリスト 1 つ。上から順に Apple Music で鳴らす。並べ替え・外すは行の操作で。
 * iOS `PlaylistDetailView` と対 (ドラッグ並べ替えの代わりに上下ボタンにしている)。
 */
data class PlaylistDetailUiState(
    val playlist: Playlist? = null,
    val songs: List<Song> = emptyList(),
    val isLoading: Boolean = true
)

class PlaylistDetailViewModel(app: Application) : AndroidViewModel(app) {
    private val module = AppModule.from(app)
    private val repository = module.playlistRepository

    private val _uiState = MutableStateFlow(PlaylistDetailUiState())
    val uiState: StateFlow<PlaylistDetailUiState> = _uiState.asStateFlow()

    private var playlistId: String? = null

    fun load(playlistId: String) {
        this.playlistId = playlistId
        viewModelScope.launch {
            val ids = repository.songIds(playlistId)
            val found = module.songRepository.fetchSongsByIds(ids)
            val byId = found.associateBy { it.id }
            val songs = ids.mapNotNull { byId[it] }
            val playlist = repository.summaries().firstOrNull { it.id == playlistId }?.playlist
            _uiState.value = PlaylistDetailUiState(playlist = playlist, songs = songs, isLoading = false)
        }
    }

    fun rename(name: String) {
        val id = playlistId ?: return
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        viewModelScope.launch {
            repository.rename(id, trimmed)
            _uiState.value = _uiState.value.copy(playlist = _uiState.value.playlist?.copy(name = trimmed))
        }
    }

    fun moveUp(index: Int) = move(index, index - 1)
    fun moveDown(index: Int) = move(index, index + 1)

    private fun move(from: Int, to: Int) {
        val id = playlistId ?: return
        val songs = _uiState.value.songs
        if (from < 0 || to < 0 || from >= songs.size || to >= songs.size) return
        val ids = playlistMoveSong(songs.map { it.id }, from.toUInt(), to.toUInt())
        save(id, ids)
    }

    fun remove(songId: String) {
        val id = playlistId ?: return
        save(id, _uiState.value.songs.map { it.id }.filter { it != songId })
    }

    private fun save(id: String, ids: List<String>) {
        val byId = _uiState.value.songs.associateBy { it.id }
        _uiState.value = _uiState.value.copy(songs = ids.mapNotNull { byId[it] })
        viewModelScope.launch { repository.setSongIds(id, ids) }
    }

    suspend fun play(startAt: Int): Boolean =
        PlaylistPlayback.play(module.lyricsPlayback, _uiState.value.songs, startAt)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaylistDetailScreen(
    playlistId: String,
    onBack: () -> Unit,
    viewModel: PlaylistDetailViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var isRenaming by remember { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    var playFailed by remember { mutableStateOf(false) }

    LaunchedEffect(playlistId) { viewModel.load(playlistId) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(state.playlist?.name ?: "プレイリスト") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                actions = {
                    IconButton(onClick = { showMenu = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "そのほか")
                    }
                    DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                        DropdownMenuItem(
                            text = { Text("名前を変える") },
                            leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
                            onClick = { showMenu = false; isRenaming = true }
                        )
                    }
                }
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when {
                state.isLoading -> ImasLoadingState()
                state.songs.isEmpty() -> ImasEmptyState(
                    icon = Icons.Filled.MusicNote,
                    title = "曲がまだありません",
                    message = "曲の詳細の記号のボタンから足せます。"
                )
                else -> {
                    val unplayable = PlaylistPlayback.unplayableCount(state.songs)
                    LazyColumn(Modifier.fillMaxSize()) {
                        item {
                            Column(Modifier.padding(DS.Space.card)) {
                                ImasButton(
                                    title = "再生",
                                    icon = Icons.Filled.PlayArrow,
                                    role = ImasButtonRole.PRIMARY,
                                    size = ImasButtonSize.LARGE,
                                    onClick = {
                                        scope.launch { playFailed = !viewModel.play(0) }
                                    },
                                    modifier = Modifier.fillMaxWidth()
                                )
                                if (playFailed) {
                                    ImasNote("プレイリストの再生には Apple Music の契約が要ります。", modifier = Modifier.padding(top = DS.Space.header))
                                }
                                if (unplayable > 0) {
                                    ImasNote("Apple Music に無い $unplayable 曲は飛ばします。", modifier = Modifier.padding(top = DS.Space.header))
                                }
                            }
                        }
                        item(key = "count") { ImasListSummary<Unit>(count = state.songs.size, unit = "曲") }
                        itemsIndexed(state.songs, key = { _, song -> song.id }) { index, song ->
                            PlaylistSongRow(
                                song = song,
                                isFirst = index == 0,
                                isLast = index == state.songs.size - 1,
                                onPlay = { scope.launch { playFailed = !viewModel.play(index) } },
                                onMoveUp = { viewModel.moveUp(index) },
                                onMoveDown = { viewModel.moveDown(index) },
                                onRemove = { viewModel.remove(song.id) }
                            )
                        }
                        item { Spacer(Modifier.height(DS.Space.section)) }
                    }
                }
            }
        }
    }

    if (isRenaming) {
        ImasTextInputDialog(
            title = "名前を変える",
            confirmLabel = "変える",
            initialValue = state.playlist?.name.orEmpty(),
            onDismiss = { isRenaming = false },
            onConfirm = { name -> viewModel.rename(name); isRenaming = false }
        )
    }
}

@Composable
private fun PlaylistSongRow(
    song: Song,
    isFirst: Boolean,
    isLast: Boolean,
    onPlay: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onRemove: () -> Unit
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        ImasSongRow(
            song = song,
            density = ImasRowDensity.COMPACT,
            modifier = Modifier.weight(1f),
            onClick = onPlay
        )
        IconButton(onClick = onMoveUp, enabled = !isFirst) {
            Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "上へ")
        }
        IconButton(onClick = onMoveDown, enabled = !isLast) {
            Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "下へ")
        }
        IconButton(onClick = onRemove) {
            Icon(Icons.Filled.Close, contentDescription = "外す")
        }
    }
}
