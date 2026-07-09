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

data class TagSongRankRow(val songId: String, val voteCount: Int, val song: Song?)
data class TagIdolRankRow(val idolId: String, val voteCount: Int, val idol: Idol?)

data class TagDetailUiState(
    val isLoading: Boolean = true,
    val tag: CommunityApi.CommunityTag? = null,
    val songs: List<TagSongRankRow> = emptyList(),
    val idols: List<TagIdolRankRow> = emptyList(),
    val reportSubmitted: Boolean = false,
    val reportError: String? = null
)

/** タグ詳細。iOS TagDetailView の移植 (説明 + 付いた曲ランキング + 編集/履歴/通報)。 */
class TagDetailViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(TagDetailUiState())
    val uiState: StateFlow<TagDetailUiState> = _uiState.asStateFlow()

    private var api: CommunityApi? = null
    private var appModule: AppModule? = null
    private var tagId: String? = null

    fun load(context: Context, tagId: String) {
        this.tagId = tagId
        val module = AppModule.from(context)
        appModule = module
        api = module.communityApi
        viewModelScope.launch { reload() }
    }

    private suspend fun reload() {
        val id = tagId ?: return
        val a = api ?: return
        val module = appModule ?: return
        _uiState.value = _uiState.value.copy(isLoading = true)
        val detail = runCatching { a.tagDetail(id) }.getOrNull()
        if (detail == null) {
            _uiState.value = _uiState.value.copy(isLoading = false)
            return
        }
        val songs = module.songRepository.fetchSongsByIds(detail.songs.map { it.songId })
        val songsById = songs.associateBy { it.id }
        val songRows = detail.songs.map { TagSongRankRow(it.songId, it.voteCount, songsById[it.songId]) }
        val idolRows = detail.idols.map { TagIdolRankRow(it.idolId, it.voteCount, module.idolRepository.fetchIdol(it.idolId)) }
        _uiState.value = _uiState.value.copy(isLoading = false, tag = detail.tag, songs = songRows, idols = idolRows)
    }

    fun onTagUpdated(tag: CommunityApi.CommunityTag) {
        _uiState.value = _uiState.value.copy(tag = tag)
    }

    fun reportTag(reason: String? = null) {
        val id = tagId ?: return
        val a = api ?: return
        viewModelScope.launch {
            val ok = runCatching { a.reportTag(id, reason) }.getOrDefault(false)
            _uiState.value = if (ok) {
                _uiState.value.copy(reportSubmitted = true, reportError = null)
            } else {
                _uiState.value.copy(reportError = "通報に失敗しました。しばらくしてからお試しください。")
            }
        }
    }

    fun clearReportState() {
        _uiState.value = _uiState.value.copy(reportSubmitted = false, reportError = null)
    }
}
