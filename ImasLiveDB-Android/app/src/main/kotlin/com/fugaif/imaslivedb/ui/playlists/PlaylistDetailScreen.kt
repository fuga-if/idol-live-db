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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.IosShare
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.auth.startCommunityEdit
import com.fugaif.imaslivedb.data.community.CommunityPlaylistApi
import com.fugaif.imaslivedb.data.model.Playlist
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.PlaylistPlayback
import com.fugaif.imaslivedb.ui.components.CommunityLoginPromptDialog
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasListSummary
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasTextInputDialog
import com.fugaif.imaslivedb.ui.designsystem.ImasTwoFieldTextInputDialog
import com.fugaif.imaslivedb.ui.components.ImasSongRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.polls.SongPollCandidatePicker
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.playlistMoveSong

/**
 * プレイリスト 1 つ。上から順に Apple Music で鳴らす。並べ替え・外すは行の操作で。
 * 曲は「曲を足す」で検索して足す。そのほかから「みんなのプレイリスト」に公開できる。
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
    private val communityApi = module.communityPlaylistApi

    private val _uiState = MutableStateFlow(PlaylistDetailUiState())
    val uiState: StateFlow<PlaylistDetailUiState> = _uiState.asStateFlow()

    private var playlistId: String? = null

    sealed class PublishOutcome {
        data class Success(val message: String) : PublishOutcome()
        data class Error(val message: String) : PublishOutcome()
    }

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

    /** 曲を検索ピッカーで足す。既に入っている曲は変えない。 */
    fun add(songIds: List<String>) {
        val id = playlistId ?: return
        if (songIds.isEmpty()) return
        viewModelScope.launch {
            repository.append(id, songIds)
            load(id)
        }
    }

    suspend fun play(startAt: Int): Boolean =
        PlaylistPlayback.play(module.lyricsPlayback, _uiState.value.songs, startAt)

    /** みんなに公開する / 公開中の中身を更新する。 */
    suspend fun publish(title: String, description: String?): PublishOutcome {
        val id = playlistId ?: return PublishOutcome.Error("公開できませんでした。")
        val current = _uiState.value.playlist ?: return PublishOutcome.Error("公開できませんでした。")
        val trimmedTitle = title.trim().take(40)
        if (trimmedTitle.isEmpty()) return PublishOutcome.Error("タイトルを入れてください。")
        val trimmedDescription = description?.trim()?.take(200)?.ifEmpty { null }
        val input = CommunityPlaylistApi.Input(trimmedTitle, trimmedDescription, _uiState.value.songs.map { it.id })
        val result = if (current.publishedId != null) {
            communityApi.update(current.publishedId, input)
        } else {
            communityApi.publish(input)
        }
        return when (result) {
            is CommunityPlaylistApi.SaveResult.Success -> {
                repository.setPublishedId(id, result.playlist.id)
                _uiState.value = _uiState.value.copy(playlist = current.copy(publishedId = result.playlist.id))
                PublishOutcome.Success("公開しました。みんなのプレイリストに数分で並びます。")
            }
            is CommunityPlaylistApi.SaveResult.Error -> PublishOutcome.Error(result.message ?: "公開できませんでした。")
        }
    }

    /** 公開をやめる。 */
    suspend fun unpublish(): PublishOutcome {
        val id = playlistId ?: return PublishOutcome.Error("公開をやめられませんでした。")
        val current = _uiState.value.playlist ?: return PublishOutcome.Error("公開をやめられませんでした。")
        val publishedId = current.publishedId ?: return PublishOutcome.Error("公開をやめられませんでした。")
        if (!communityApi.remove(publishedId)) return PublishOutcome.Error("公開をやめられませんでした。")
        repository.setPublishedId(id, null)
        _uiState.value = _uiState.value.copy(playlist = current.copy(publishedId = null))
        return PublishOutcome.Success("公開をやめました。")
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaylistDetailScreen(
    playlistId: String,
    onBack: () -> Unit,
    viewModel: PlaylistDetailViewModel = viewModel()
) {
    val context = LocalContext.current
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val authState by AppModule.from(context).authService.state.collectAsState()
    val scope = rememberCoroutineScope()
    var isRenaming by remember { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    var showsSpotifyExport by remember { mutableStateOf(false) }
    var playFailed by remember { mutableStateOf(false) }
    var showsPicker by remember { mutableStateOf(false) }
    var isPublishing by remember { mutableStateOf(false) }
    var showsLoginPrompt by remember { mutableStateOf(false) }
    var publishMessage by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(playlistId) { viewModel.load(playlistId) }

    fun beginPublish() {
        authState.startCommunityEdit(promptLogin = { showsLoginPrompt = true }) {
            isPublishing = true
        }
    }

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
                        if (state.songs.isNotEmpty()) {
                            DropdownMenuItem(
                                text = { Text("Spotify に書き出す") },
                                leadingIcon = { Icon(Icons.Filled.IosShare, contentDescription = null) },
                                onClick = { showMenu = false; showsSpotifyExport = true }
                            )
                        }
                        if (state.songs.isNotEmpty()) {
                            DropdownMenuItem(
                                text = { Text(if (state.playlist?.publishedId == null) "みんなに公開する" else "公開中の中身を更新する") },
                                leadingIcon = { Icon(Icons.Filled.Group, contentDescription = null) },
                                onClick = { showMenu = false; beginPublish() }
                            )
                        }
                        if (state.playlist?.publishedId != null) {
                            DropdownMenuItem(
                                text = { Text("公開をやめる") },
                                leadingIcon = { Icon(Icons.Filled.VisibilityOff, contentDescription = null) },
                                onClick = {
                                    showMenu = false
                                    scope.launch {
                                        when (val outcome = viewModel.unpublish()) {
                                            is PlaylistDetailViewModel.PublishOutcome.Success -> publishMessage = outcome.message
                                            is PlaylistDetailViewModel.PublishOutcome.Error -> publishMessage = outcome.message
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when {
                state.isLoading -> ImasLoadingState()
                state.songs.isEmpty() -> Column(
                    Modifier.fillMaxSize().padding(horizontal = DS.Space.screen),
                ) {
                    Spacer(Modifier.height(DS.Space.section))
                    ImasEmptyState(
                        icon = Icons.Filled.MusicNote,
                        title = "曲がまだありません",
                        message = "曲を検索して足しましょう。曲の詳細や曲一覧の左スワイプからも足せます。"
                    )
                    ImasButton(
                        title = "曲を足す",
                        icon = Icons.Filled.Add,
                        role = ImasButtonRole.PRIMARY,
                        onClick = { showsPicker = true },
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                else -> {
                    val unplayable = PlaylistPlayback.unplayableCount(AppModule.from(context).lyricsPlayback, state.songs)
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
                        item(key = "add") {
                            ImasNavRow(
                                title = "曲を足す",
                                icon = Icons.Filled.Add,
                                showsChevron = false,
                                modifier = Modifier.padding(horizontal = DS.Space.screen),
                                onClick = { showsPicker = true }
                            )
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

    if (showsSpotifyExport) {
        SpotifyExportSheet(
            name = state.playlist?.name ?: "プレイリスト",
            songs = state.songs.map { SpotifyExportSong(it.id, it.title) },
            onDismiss = { showsSpotifyExport = false },
        )
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

    if (isPublishing) {
        ImasTwoFieldTextInputDialog(
            title = if (state.playlist?.publishedId == null) "みんなに公開する" else "公開中の中身を更新する",
            message = "タイトル・ひとこと・曲の並びが「みんなのプレイリスト」に載ります。名前は出ません。",
            confirmLabel = if (state.playlist?.publishedId == null) "公開する" else "更新する",
            initialValue1 = state.playlist?.name.orEmpty(),
            label1 = "タイトル (40 文字まで)",
            label2 = "ひとこと (なくてもよい)",
            onDismiss = { isPublishing = false },
            onConfirm = { title, description ->
                isPublishing = false
                scope.launch {
                    when (val outcome = viewModel.publish(title, description)) {
                        is PlaylistDetailViewModel.PublishOutcome.Success -> publishMessage = outcome.message
                        is PlaylistDetailViewModel.PublishOutcome.Error -> publishMessage = outcome.message
                    }
                }
            }
        )
    }

    if (showsLoginPrompt) {
        CommunityLoginPromptDialog(
            message = "プレイリストの公開にはログインが必要です。",
            onDismiss = { showsLoginPrompt = false }
        )
    }

    ImasErrorAlert(message = publishMessage, onDismiss = { publishMessage = null }, title = "みんなのプレイリスト")

    if (showsPicker) {
        SongPollCandidatePicker(
            alreadySelected = state.songs.map { it.id }.toSet(),
            remaining = Int.MAX_VALUE,
            onDismiss = { showsPicker = false },
            onConfirm = { picked ->
                showsPicker = false
                val existing = state.songs.map { it.id }.toSet()
                viewModel.add(picked.filter { it !in existing })
            }
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
