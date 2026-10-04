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
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.CommunityPlaylistApi
import com.fugaif.imaslivedb.data.model.PlaylistSummary
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasListSummary
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
import com.fugaif.imaslivedb.ui.designsystem.ImasTextInputDialog
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * プレイリストの入口。「自分」(端末にだけ保存) と「みんな」(ユーザーが公開したもの) を切り替える。
 * プロデュースタブから開く。iOS `PlaylistsView` と対。
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

    /** 作ったらそのまま中へ入れて、曲を足すところから始めてもらう ([onCreated] に新しい id を渡す)。 */
    fun create(name: String, onCreated: (String) -> Unit) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        viewModelScope.launch {
            val playlist = repository.create(trimmed)
            load()
            onCreated(playlist.id)
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
    onCommunityPlaylistClick: (String) -> Unit,
    viewModel: PlaylistsViewModel = viewModel()
) {
    var tab by rememberSaveable { mutableStateOf(0) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("プレイリスト") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            Column(Modifier.fillMaxSize()) {
                ImasTabs(
                    labels = listOf("自分", "みんな"),
                    selection = tab,
                    onSelect = { tab = it },
                    modifier = Modifier.padding(horizontal = DS.Space.screen)
                )
                if (tab == 0) {
                    MyPlaylists(
                        viewModel = viewModel,
                        onPlaylistClick = onPlaylistClick
                    )
                } else {
                    CommunityPlaylistsList(onPlaylistClick = onCommunityPlaylistClick)
                }
            }
        }
    }
}

/** 自分のプレイリスト。作る入口はいつも一番上に出す (空のときだけでなく)。 */
@Composable
private fun MyPlaylists(viewModel: PlaylistsViewModel, onPlaylistClick: (String) -> Unit) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var isNaming by rememberSaveable { mutableStateOf(false) }
    var newName by rememberSaveable { mutableStateOf("") }

    Box(Modifier.fillMaxSize()) {
        when {
            state.isLoading -> ImasLoadingState()
            else -> LazyColumn(Modifier.fillMaxSize()) {
                item(key = "new") {
                    ImasNavRow(
                        title = "新しいプレイリスト",
                        subtitle = "名前を付けて作り、曲を検索して足す",
                        icon = Icons.Filled.Add,
                        showsChevron = false,
                        modifier = Modifier.padding(horizontal = DS.Space.screen),
                        onClick = { newName = ""; isNaming = true }
                    )
                }
                if (state.summaries.isEmpty()) {
                    item(key = "hint") {
                        ImasNote(
                            "曲の詳細・曲一覧の左スワイプ・歌詞プレイヤーからも足せます。",
                            modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gapTight)
                        )
                    }
                } else {
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
                }
                item { Spacer(Modifier.height(DS.Space.section)) }
            }
        }
    }

    if (isNaming) {
        ImasTextInputDialog(
            title = "新しいプレイリスト",
            confirmLabel = "作る",
            onDismiss = { isNaming = false },
            onConfirm = { name ->
                isNaming = false
                viewModel.create(name) { id -> onPlaylistClick(id) }
            }
        )
    }
}

@Composable
private fun PlaylistRow(summary: PlaylistSummary, onClick: () -> Unit, onDelete: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        ImasNavRow(
            title = summary.playlist.name,
            subtitle = subtitle(summary),
            icon = Icons.Filled.MusicNote,
            showsChevron = false,
            modifier = Modifier.weight(1f).padding(horizontal = DS.Space.screen),
            onClick = onClick
        )
        IconButton(onClick = onDelete) {
            Icon(Icons.Filled.Close, contentDescription = "削除")
        }
    }
}

private fun subtitle(summary: PlaylistSummary): String =
    if (summary.playlist.publishedId == null) "${summary.songCount}曲" else "${summary.songCount}曲 ・ 公開中"

/** みんなのプレイリストの一覧 (新しく更新された順)。下まで来たら続きを取る。 */
data class CommunityPlaylistsUiState(
    val playlists: List<CommunityPlaylistApi.CommunityPlaylist> = emptyList(),
    val next: String? = null,
    val loaded: Boolean = false,
    val failed: Boolean = false,
    val songsById: Map<String, Song> = emptyMap()
)

class CommunityPlaylistsViewModel(app: Application) : AndroidViewModel(app) {
    private val api = AppModule.from(app).communityPlaylistApi
    private val songRepository = AppModule.from(app).songRepository

    private val _uiState = MutableStateFlow(CommunityPlaylistsUiState())
    val uiState: StateFlow<CommunityPlaylistsUiState> = _uiState.asStateFlow()

    fun reloadIfNeeded() {
        if (!_uiState.value.loaded) reload()
    }

    fun reload() {
        viewModelScope.launch {
            val page = api.page()
            if (page == null) {
                _uiState.value = _uiState.value.copy(failed = true, loaded = true)
                return@launch
            }
            _uiState.value = _uiState.value.copy(playlists = page.playlists, next = page.next, failed = false, loaded = true)
            resolveSongs(page.playlists)
        }
    }

    fun loadMore() {
        val cursor = _uiState.value.next ?: return
        viewModelScope.launch {
            val page = api.page(cursor)
            if (page == null) return@launch
            val existingIds = _uiState.value.playlists.map { it.id }.toSet()
            _uiState.value = _uiState.value.copy(
                playlists = _uiState.value.playlists + page.playlists.filter { it.id !in existingIds },
                next = page.next
            )
            resolveSongs(page.playlists)
        }
    }

    /** 一覧のジャケに使う先頭の曲を端末のカタログから引く。 */
    private suspend fun resolveSongs(page: List<CommunityPlaylistApi.CommunityPlaylist>) {
        val ids = page.mapNotNull { it.songIds.firstOrNull() }.filter { it !in _uiState.value.songsById }
        if (ids.isEmpty()) return
        val songs = runCatching { songRepository.fetchSongsByIds(ids) }.getOrDefault(emptyList())
        if (songs.isEmpty()) return
        _uiState.value = _uiState.value.copy(songsById = _uiState.value.songsById + songs.associateBy { it.id })
    }
}

@Composable
private fun CommunityPlaylistsList(
    onPlaylistClick: (String) -> Unit,
    viewModel: CommunityPlaylistsViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { viewModel.reloadIfNeeded() }

    Box(Modifier.fillMaxSize()) {
        when {
            state.failed && state.playlists.isEmpty() -> ImasEmptyState(
                icon = Icons.Filled.WifiOff,
                title = "読み込めませんでした"
            )
            state.loaded && state.playlists.isEmpty() -> ImasEmptyState(
                icon = Icons.Filled.MusicNote,
                title = "まだ公開されたプレイリストがありません",
                message = "自分のプレイリストを開いて、そのほかから公開できます。"
            )
            !state.loaded -> ImasLoadingState()
            else -> LazyColumn(Modifier.fillMaxSize()) {
                items(state.playlists, key = { it.id }) { playlist ->
                    if (playlist.id == state.playlists.last().id) {
                        LaunchedEffect(playlist.id) { viewModel.loadMore() }
                    }
                    CommunityPlaylistRow(
                        playlist = playlist,
                        firstSong = playlist.songIds.firstOrNull()?.let { state.songsById[it] },
                        onClick = { onPlaylistClick(playlist.id) }
                    )
                }
                item { Spacer(Modifier.height(DS.Space.section)) }
            }
        }
    }
}

@Composable
private fun CommunityPlaylistRow(
    playlist: CommunityPlaylistApi.CommunityPlaylist,
    firstSong: Song?,
    onClick: () -> Unit
) {
    val subtitle = listOfNotNull("${playlist.songCount}曲", playlist.description).joinToString(" ・ ")
    ImasRow(
        title = playlist.title,
        subtitle = subtitle,
        leading = ImasRowLeading.Artwork(
            title = firstSong?.title ?: playlist.title,
            brand = firstSong?.brandId,
            imageUrl = firstSong?.artworkUrl
        ),
        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen).imasRowPress(onClick = onClick)
    )
}
