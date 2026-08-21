package com.fugaif.imaslivedb.ui.mypage

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MusicNote
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.components.SongRow
import com.fugaif.imaslivedb.ui.components.ImasSegmented
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
    private val marks = AppModule.from(app).userMarkRepository

    private val _uiState = MutableStateFlow(FavoritesUiState())
    val uiState: StateFlow<FavoritesUiState> = _uiState.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _uiState.value = FavoritesUiState(
                songs = marks.favoriteSongs(),
                idols = marks.favoriteIdols(),
                events = marks.favoriteEvents(),
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
                title = { Text("お気に入り", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).background(DS.bg)) {
            ImasSegmented(
                labels = tabs.map { it.label },
                selection = tabIndex,
                onSelect = { tabIndex = it },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)
            )

            if (state.isLoading) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
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
    if (songs.isEmpty()) {
        EmptyBox { ImasEmptyState(icon = Icons.Filled.MusicNote, title = "お気に入りの曲がありません") }
        return
    }
    LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 4.dp)) {
        items(songs, key = { it.id }) { song ->
            SongRow(
                title = song.title,
                artistNames = "",
                unitName = song.unitName,
                artworkUrl = song.artworkUrl,
                previewUrl = song.previewUrl,
                brandId = song.brandId,
                modifier = Modifier.clickable { onClick(song.id) }.padding(horizontal = 16.dp, vertical = 6.dp)
            )
            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
        }
    }
}

@Composable
private fun IdolsTab(idols: List<Idol>, onClick: (String) -> Unit) {
    if (idols.isEmpty()) {
        EmptyBox { ImasEmptyState(icon = Icons.Filled.Person, title = "お気に入りのアイドルがいません") }
        return
    }
    LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 4.dp)) {
        items(idols, key = { it.id }) { idol ->
            Box(modifier = Modifier.clickable { onClick(idol.id) }) {
                androidx.compose.foundation.layout.Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 40.dp)
                    Column(Modifier.padding(start = 12.dp)) {
                        Text(idol.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                        idol.nameKana?.takeIf { it.isNotEmpty() }?.let {
                            Text(it, fontSize = 12.sp, color = DS.ink3, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
        }
    }
}

@Composable
private fun EventsTab(events: List<EventWithDateRange>) {
    if (events.isEmpty()) {
        EmptyBox { ImasEmptyState(icon = Icons.Filled.MusicNote, title = "お気に入りのライブがありません") }
        return
    }
    LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 4.dp)) {
        items(events, key = { it.event.id }) { ew ->
            androidx.compose.foundation.layout.Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)
            ) {
                ImasLeadBar(brandId = ew.event.brandId, height = 38.dp, rainbow = ew.event.jointBrandIdList.isNotEmpty())
                Column(Modifier.weight(1f)) {
                    Text(
                        text = ew.event.name,
                        fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                        maxLines = 2, overflow = TextOverflow.Ellipsis
                    )
                    ew.dateRange?.let { d ->
                        Text(text = d, fontSize = 12.sp, color = DS.ink2)
                    }
                }
            }
            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 16.dp))
        }
    }
}

@Composable
private fun EmptyBox(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { content() }
}
