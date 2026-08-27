package com.fugaif.imaslivedb.ui.filtered

import android.app.Application
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material3.MaterialTheme
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
import com.fugaif.imaslivedb.ui.components.SongRow
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * 絞り込んだ楽曲一覧 (iOS `FilteredSongsView` の移植)。
 *
 * CDシリーズ / シリーズ / リリース年 / ブランド / 曲タイプ / クリエイターの 6 通りを 1 画面で扱う。
 * 行は曲一覧と同じ [SongRow] を使い回す — 「同じものは同じ見た目」でないと、絞り込んだ先が
 * 別のリストに見えてしまう。クリエイター絞り込みのときだけ、行の下に役割 (作曲・編曲) を足す。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FilteredSongsScreen(
    kind: String,
    value: String,
    onBack: () -> Unit,
    onSongClick: (String) -> Unit,
    // ViewModel は遷移エントリ単位で持たれるので、同じ画面を条件違いで積んでも別インスタンスになる。
    viewModel: FilteredSongsViewModel = viewModel(
        key = "$kind/$value",
        factory = FilteredSongsViewModel.Factory(
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
                state.songs.isEmpty() -> FilteredEmptyState(Icons.Filled.MusicNote, "楽曲が見つかりません")
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    item(key = "count") { FilteredCountHeader("${state.songs.size}曲") }
                    items(state.songs, key = { it.song.id }) { item ->
                        val song = item.song
                        Column {
                            SongRow(
                                title = song.title,
                                artistNames = item.artistNames,
                                unitName = song.unitName,
                                artworkUrl = song.artworkUrl,
                                previewUrl = song.previewUrl,
                                brandId = song.brandId,
                                releaseDate = song.releaseDate,
                                modifier = Modifier.fillMaxWidth()
                                    .clickable { onSongClick(song.id) }
                                    .padding(horizontal = 16.dp, vertical = 4.dp)
                            )
                            // 役割はクリエイター絞り込みのときだけ付く。ジャケ写のぶん字下げして
                            // 曲名の左端に揃える (iOS の padding(.leading, 62) と同じ狙い)。
                            state.rolesBySongId[song.id]?.let { roles ->
                                Text(
                                    roles,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = DS.ink3,
                                    modifier = Modifier.padding(start = 68.dp, bottom = 6.dp)
                                )
                            }
                        }
                        HorizontalDivider(color = DS.sep, modifier = Modifier.padding(start = 68.dp))
                    }
                }
            }
        }
    }
}
