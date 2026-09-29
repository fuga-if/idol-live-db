package com.fugaif.imaslivedb.ui.tags

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class TagActivityUiState(
    val isLoading: Boolean = true,
    val activity: CommunityApi.TagActivityResponse? = null,
    val songs: Map<String, Song> = emptyMap(),
    val idols: Map<String, Idol> = emptyMap()
)

/** タグ付けの盛り上がり (GET /tags/activity)。iOS TagActivityView の移植。
 * 「伸びてるタグ」「タグが急増中」「最近つけられたタグ」を曲/アイドルのドメインタブで横断表示する。 */
class TagActivityViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(TagActivityUiState())
    val uiState: StateFlow<TagActivityUiState> = _uiState.asStateFlow()

    private var api: CommunityApi? = null
    private var appModule: AppModule? = null

    fun load(context: Context) {
        if (appModule != null) return
        val module = AppModule.from(context)
        appModule = module
        api = module.communityApi
        viewModelScope.launch { reload() }
    }

    fun refresh() {
        viewModelScope.launch { reload() }
    }

    private suspend fun reload() {
        val a = api ?: return
        val module = appModule ?: return
        _uiState.value = _uiState.value.copy(isLoading = _uiState.value.activity == null)
        val response = runCatching { a.tagActivity() }.getOrNull()
        if (response == null) {
            _uiState.value = _uiState.value.copy(isLoading = false)
            return
        }

        val songIds = mutableSetOf<String>()
        val idolIds = mutableSetOf<String>()
        response.recent.forEach {
            if (it.domain == CommunityApi.TagActivityDomain.SONG) songIds += it.entityId else idolIds += it.entityId
        }
        response.risingEntities.forEach {
            if (it.domain == CommunityApi.TagActivityDomain.SONG) songIds += it.entityId else idolIds += it.entityId
        }
        songIds -= _uiState.value.songs.keys
        idolIds -= _uiState.value.idols.keys

        val fetchedSongs = if (songIds.isNotEmpty()) module.songRepository.fetchSongsByIds(songIds.toList()) else emptyList()
        val fetchedIdols = if (idolIds.isNotEmpty()) module.idolRepository.fetchIdolsByIds(idolIds.toList()) else emptyList()

        _uiState.value = _uiState.value.copy(
            isLoading = false,
            activity = response,
            songs = _uiState.value.songs + fetchedSongs.associateBy { it.id },
            idols = _uiState.value.idols + fetchedIdols.associateBy { it.id }
        )
    }
}
