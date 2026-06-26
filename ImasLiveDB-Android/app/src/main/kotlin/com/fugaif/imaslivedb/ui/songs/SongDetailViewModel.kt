package com.fugaif.imaslivedb.ui.songs

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.PerformanceHistoryRow
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongCall
import com.fugaif.imaslivedb.data.model.SongVideo
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SongDetailUiState(
    val isLoading: Boolean = true,
    val song: Song? = null,
    val originalArtists: List<Idol> = emptyList(),
    val performerArtists: List<Idol> = emptyList(),
    val performanceHistory: List<PerformanceHistoryRow> = emptyList(),
    val unit: ImasUnit? = null,
    val songCalls: List<SongCall> = emptyList(),
    val songVideos: List<SongVideo> = emptyList(),
    val tags: List<CommunityApi.SongTag> = emptyList(),
    val penlight: CommunityApi.PenlightResult? = null
)

class SongDetailViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(SongDetailUiState())
    val uiState: StateFlow<SongDetailUiState> = _uiState.asStateFlow()

    private var api: CommunityApi? = null
    private var currentSongId: String? = null

    fun load(context: Context, songId: String) {
        currentSongId = songId
        viewModelScope.launch {
            val module = AppModule.from(context)
            api = module.communityApi
            val song = module.songRepository.fetchSong(songId)
            val originalArtists = module.songRepository.fetchSongArtists(songId, "original")
            val performerArtists = module.songRepository.fetchSongArtists(songId, "performer")
            val history = module.songRepository.fetchSongPerformanceHistory(songId)
            val unit = if (song?.unitId != null) {
                module.idolRepository.fetchUnit(song.unitId)
            } else {
                null
            }
            val calls = module.database.communityDao().callsForSong(songId)
            val videos = module.database.communityDao().videosForSong(songId)
            _uiState.value = SongDetailUiState(
                isLoading = false,
                song = song,
                originalArtists = originalArtists,
                performerArtists = performerArtists,
                performanceHistory = history,
                unit = unit,
                songCalls = calls,
                songVideos = videos
            )
            // 集計系コミュニティ (Worker D1) はネットワーク。失敗しても本体表示は維持。
            loadCommunity(songId)
        }
    }

    private suspend fun loadCommunity(songId: String) {
        val a = api ?: return
        val tags = runCatching { a.songTags(songId) }.getOrDefault(emptyList())
        val pen = runCatching { a.penlightVotes(songId) }.getOrNull()
        if (currentSongId == songId) {
            _uiState.value = _uiState.value.copy(tags = tags, penlight = pen)
        }
    }

    /** タグ投票のトグル (端末ベース)。完了後にタグを再取得。 */
    fun toggleTag(tag: CommunityApi.SongTag) {
        val songId = currentSongId ?: return
        val a = api ?: return
        viewModelScope.launch {
            runCatching {
                if (tag.mine) a.removeTag(songId, tag.id) else a.applyTag(songId, tag.id)
            }
            loadCommunity(songId)
        }
    }
}
