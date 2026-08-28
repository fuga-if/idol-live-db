package com.fugaif.imaslivedb.ui.produce

import android.app.Application
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MusicNote
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.SongRow
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * 「回収した楽曲」一覧。参加マークの付いたライブのセトリから自動判定した曲だけを並べる
 * (iOS の `FilteredSongsView(criterion: .songIds(collected, title: "回収した楽曲"))` にあたる)。
 *
 * 絞り込み一覧 (FilteredSongs) に相乗りしていないのは、あちらの条件が「CDシリーズ」
 * 「リリース年」のような**マスタ由来の条件**で、id の集合を経路に載せる形を持たないため。
 * 回収済みは端末ローカルのマークから毎回導出するので、条件を URL に焼けない。
 *
 * 行は曲一覧と同じ [SongRow] を使う — 「同じものは同じ見た目」でないと別のリストに見える。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CollectedSongsScreen(
    onBack: () -> Unit,
    onSongClick: (String) -> Unit,
    viewModel: CollectedSongsViewModel = viewModel(
        factory = CollectedSongsViewModel.Factory(LocalContext.current.applicationContext as Application)
    )
) {
    val state by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("回収した楽曲", fontWeight = FontWeight.Bold) },
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
                state.isLoading -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                state.songs.isEmpty() -> ImasEmptyState(
                    icon = Icons.Filled.MusicNote,
                    title = "まだ回収した楽曲がありません",
                    message = "ライブに「参加」を付けると、そのセトリの曲がここに集まります。"
                )
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    item(key = "count") {
                        Text(
                            "${state.songs.size}曲",
                            fontSize = 13.sp, color = DS.ink2,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
                        )
                    }
                    items(state.songs, key = { it.id }) { song ->
                        SongRow(
                            title = song.title,
                            artistNames = "",
                            unitName = song.unitName,
                            artworkUrl = song.artworkUrl,
                            previewUrl = song.previewUrl,
                            brandId = song.brandId,
                            releaseDate = song.releaseDate,
                            modifier = Modifier.fillMaxWidth()
                                .clickable { onSongClick(song.id) }
                                .padding(horizontal = 16.dp, vertical = 4.dp)
                        )
                        HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 68.dp))
                    }
                }
            }
        }
    }
}

data class CollectedSongsUiState(
    val songs: List<Song> = emptyList(),
    val isLoading: Boolean = true
)

class CollectedSongsViewModel(app: Application) : AndroidViewModel(app) {

    private val module = AppModule.from(app)

    private val _uiState = MutableStateFlow(CollectedSongsUiState())
    val uiState: StateFlow<CollectedSongsUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            // 回収済みの判定 (どの参加形態を数えるか) はマークのリポジトリが持っている。
            // ここで参加形態を見て絞り直すと、設定「配信も回収に含める」と食い違う。
            val ids = module.userMarkRepository.autoCollectedSongIds()
            val songs = module.songRepository.fetchSongsByIds(ids.toList())
                .sortedBy { it.title }
            _uiState.value = CollectedSongsUiState(songs = songs, isLoading = false)
        }
    }

    class Factory(private val app: Application) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            CollectedSongsViewModel(app) as T
    }
}
