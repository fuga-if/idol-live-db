package com.fugaif.imaslivedb.ui.mypage

import android.app.Application
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.SongRow
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEventRow
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasIdolRow
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * お気に入り一覧。iOS FavoritesListView 相当: 曲/アイドル/ライブをセグメントで切替。
 */
data class FavoritesUiState(
    val songs: List<Song> = emptyList(),
    val idols: List<Idol> = emptyList(),
    val events: List<EventWithDateRange> = emptyList(),
    val isLoading: Boolean = true
)

class FavoritesViewModel(app: Application) : AndroidViewModel(app) {
    private val module = AppModule.from(app)
    private val marks = module.userMarkRepository

    private val _uiState = MutableStateFlow(FavoritesUiState())
    val uiState: StateFlow<FavoritesUiState> = _uiState.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _uiState.value = FavoritesUiState(
                songs = marks.favoriteSongs(),
                idols = marks.favoriteIdols(),
                events = module.eventRepository.fetchFavoriteEvents(),
                isLoading = false
            )
        }
    }
}

private enum class FavoritesTab(val label: String) {
    SONG("曲"), IDOL("アイドル"), EVENT("ライブ")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FavoritesScreen(
    onBack: () -> Unit,
    onNavigateToSong: (String) -> Unit,
    onNavigateToIdol: (String) -> Unit,
    viewModel: FavoritesViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var tabIndex by rememberSaveable { mutableIntStateOf(0) }
    val tabs = remember { FavoritesTab.entries }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("お気に入り") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            ImasTabs(
                labels = tabs.map { it.label },
                selection = tabIndex,
                onSelect = { tabIndex = it },
                modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gap)
            )

            if (state.isLoading) {
                ImasLoadingState()
            } else {
                when (tabs[tabIndex]) {
                    FavoritesTab.SONG -> SongsTab(state.songs, onNavigateToSong)
                    FavoritesTab.IDOL -> IdolsTab(state.idols, onNavigateToIdol)
                    FavoritesTab.EVENT -> EventsTab(state.events)
                }
            }
        }
    }
}

@Composable
private fun SongsTab(songs: List<Song>, onClick: (String) -> Unit) {
    EntityListSection(
        isEmpty = songs.isEmpty(),
        emptyIcon = Icons.Filled.MusicNote,
        emptyTitle = "お気に入りの曲がありません",
        sectionTitle = "${songs.size}曲"
    ) {
        songs.forEach { song ->
            SongRow(
                title = song.title,
                songId = song.id,
                artistNames = "",
                unitName = song.unitName,
                artworkUrl = song.artworkUrl,
                previewUrl = song.previewUrl,
                brandId = song.brandId,
                modifier = Modifier.clickable { onClick(song.id) }
            )
        }
    }
}

@Composable
private fun IdolsTab(idols: List<Idol>, onClick: (String) -> Unit) {
    EntityListSection(
        isEmpty = idols.isEmpty(),
        emptyIcon = Icons.Filled.Person,
        emptyTitle = "お気に入りのアイドルがいません",
        sectionTitle = "${idols.size}人"
    ) {
        idols.forEach { idol ->
            ImasIdolRow(
                idol = idol,
                subtitle = idol.nameKana?.takeIf { it.isNotEmpty() },
                onClick = { onClick(idol.id) }
            )
        }
    }
}

@Composable
private fun EventsTab(events: List<EventWithDateRange>) {
    // iOS は行から詳細へ飛べるが、Android はこの画面に遷移先 (onNavigateToEvent) が無い既存の形。
    // 無い導線を足さず、表示のみ移植する。
    EntityListSection(
        isEmpty = events.isEmpty(),
        emptyIcon = Icons.Filled.MusicNote,
        emptyTitle = "お気に入りのライブがありません",
        sectionTitle = "${events.size}件"
    ) {
        events.forEach { ew ->
            ImasEventRow(event = ew.event, date = ew.firstDate, subtitle = ew.dateRange, rainbow = ew.isJoint)
        }
    }
}

@Composable
private fun EntityListSection(
    isEmpty: Boolean,
    emptyIcon: ImageVector,
    emptyTitle: String,
    sectionTitle: String,
    rows: @Composable () -> Unit
) {
    if (isEmpty) {
        Box(Modifier.fillMaxSize()) {
            ImasEmptyState(icon = emptyIcon, title = emptyTitle, modifier = Modifier.align(Alignment.Center))
        }
        return
    }
    ImasFormBackdrop(modifier = Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            ImasListSection(sectionTitle) { rows() }
        }
    }
}
