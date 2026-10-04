package com.fugaif.imaslivedb.ui.playlists

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.MoreVert
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.CommunityPlaylistApi
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.PlaylistPlayback
import com.fugaif.imaslivedb.ui.components.ImasSongRow
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasListSummary
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * みんなのプレイリスト 1 つ。そのまま再生するか、自分のプレイリストとして保存する。
 * 自分が公開したもの・モデレーターは取り下げられる。iOS `CommunityPlaylistDetailView` と対。
 */
data class CommunityPlaylistDetailUiState(
    val playlist: CommunityPlaylistApi.CommunityPlaylist? = null,
    val songs: List<Song> = emptyList(),
    val loaded: Boolean = false,
    val isOwn: Boolean = false
)

class CommunityPlaylistDetailViewModel(app: Application) : AndroidViewModel(app) {
    private val module = AppModule.from(app)
    private val api = module.communityPlaylistApi

    private val _uiState = MutableStateFlow(CommunityPlaylistDetailUiState())
    val uiState: StateFlow<CommunityPlaylistDetailUiState> = _uiState.asStateFlow()

    private var id: String? = null

    fun load(playlistId: String) {
        id = playlistId
        viewModelScope.launch {
            val playlist = api.playlist(playlistId)
            val found = playlist?.let { module.songRepository.fetchSongsByIds(it.songIds) } ?: emptyList()
            val byId = found.associateBy { it.id }
            val songs = playlist?.songIds?.mapNotNull { byId[it] } ?: emptyList()
            val isOwn = if (module.authService.state.value.isSignedIn) {
                api.mine()?.any { it.id == playlistId } ?: false
            } else {
                false
            }
            _uiState.value = CommunityPlaylistDetailUiState(playlist = playlist, songs = songs, loaded = true, isOwn = isOwn)
        }
    }

    suspend fun play(startAt: Int): Boolean =
        PlaylistPlayback.play(module.lyricsPlayback, _uiState.value.songs, startAt)

    suspend fun saveCopy(): Boolean {
        val playlist = _uiState.value.playlist ?: return false
        return try {
            module.playlistRepository.saveCopy(playlist)
            true
        } catch (e: Exception) {
            false
        }
    }

    suspend fun remove(): Boolean {
        val playlistId = id ?: return false
        return api.remove(playlistId)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommunityPlaylistDetailScreen(
    playlistId: String,
    onBack: () -> Unit,
    viewModel: CommunityPlaylistDetailViewModel = viewModel()
) {
    val context = LocalContext.current
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val authState by AppModule.from(context).authService.state.collectAsState()
    val scope = rememberCoroutineScope()
    var showMenu by remember { mutableStateOf(false) }
    var playFailed by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(playlistId) { viewModel.load(playlistId) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(state.playlist?.title ?: "プレイリスト") },
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
                            text = { Text("自分のプレイリストに保存") },
                            leadingIcon = { Icon(Icons.Filled.Download, contentDescription = null) },
                            onClick = {
                                showMenu = false
                                scope.launch {
                                    message = if (viewModel.saveCopy()) "自分のプレイリストに保存しました。" else "保存できませんでした。"
                                }
                            }
                        )
                        if (state.isOwn || authState.isAdmin) {
                            DropdownMenuItem(
                                text = { Text(if (state.isOwn) "公開をやめる" else "非表示にする (モデレーター)") },
                                leadingIcon = { Icon(Icons.Filled.VisibilityOff, contentDescription = null) },
                                onClick = {
                                    showMenu = false
                                    scope.launch {
                                        if (viewModel.remove()) onBack() else message = "取り下げられませんでした。"
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
                !state.loaded -> ImasLoadingState()
                else -> {
                    val unplayable = PlaylistPlayback.unplayableCount(state.songs)
                    val missing = (state.playlist?.songCount ?: 0) - state.songs.size
                    LazyColumn(Modifier.fillMaxSize()) {
                        item {
                            Column(Modifier.padding(DS.Space.card)) {
                                state.playlist?.description?.takeIf { it.isNotEmpty() }?.let {
                                    ImasNote(it, modifier = Modifier.padding(bottom = DS.Space.header))
                                }
                                ImasButton(
                                    title = "再生",
                                    icon = Icons.Filled.PlayArrow,
                                    role = ImasButtonRole.PRIMARY,
                                    size = ImasButtonSize.LARGE,
                                    onClick = { scope.launch { playFailed = !viewModel.play(0) } },
                                    modifier = Modifier.fillMaxWidth()
                                )
                                if (playFailed) {
                                    ImasNote("プレイリストの再生には Apple Music の契約が要ります。", modifier = Modifier.padding(top = DS.Space.header))
                                }
                                if (unplayable > 0) {
                                    ImasNote("Apple Music に無い $unplayable 曲は飛ばします。", modifier = Modifier.padding(top = DS.Space.header))
                                }
                                if (missing > 0) {
                                    // 端末のカタログにまだ無い曲 (新曲の取り込み待ち) は出せない。
                                    ImasNote("この端末にまだ無い $missing 曲は表示していません。", modifier = Modifier.padding(top = DS.Space.header))
                                }
                            }
                        }
                        item(key = "count") { ImasListSummary<Unit>(count = state.songs.size, unit = "曲") }
                        itemsIndexed(state.songs, key = { _, song -> song.id }) { index, song ->
                            ImasSongRow(
                                song = song,
                                density = ImasRowDensity.COMPACT,
                                modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen),
                                onClick = { scope.launch { playFailed = !viewModel.play(index) } }
                            )
                        }
                        item { Spacer(Modifier.height(DS.Space.section)) }
                    }
                }
            }
        }
    }

    ImasErrorAlert(message = message, onDismiss = { message = null }, title = "みんなのプレイリスト")
}
