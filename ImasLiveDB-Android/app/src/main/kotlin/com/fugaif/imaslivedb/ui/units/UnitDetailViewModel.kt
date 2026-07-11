package com.fugaif.imaslivedb.ui.units

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.PersonalTag
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class UnitDetailUiState(
    val unit: ImasUnit? = null,
    val members: List<Idol> = emptyList(),
    val songs: List<Song> = emptyList(),
    val tags: List<CommunityApi.UnitTag> = emptyList(),
    /** タグが似ているユニット (このユニットが好きな人にはこのユニットも, サーバ算出)。 */
    val similarUnits: List<ImasUnit> = emptyList(),
    val similarSharedTags: Map<String, Int> = emptyMap(),
    /** 個人用タグ (端末ローカルのみ、サーバーには送信しない)。 */
    val personalTags: List<PersonalTag> = emptyList(),
    val isLoading: Boolean = true
)

class UnitDetailViewModel(app: Application, private val unitId: String) : AndroidViewModel(app) {

    private val unitRepo = AppModule.from(app).unitRepository
    private val songRepo = AppModule.from(app).songRepository
    private val api = AppModule.from(app).communityApi
    private val personalTagRepo = AppModule.from(app).personalTagRepository

    private val _uiState = MutableStateFlow(UnitDetailUiState())
    val uiState: StateFlow<UnitDetailUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            val unit = unitRepo.fetchUnit(unitId) ?: return@launch
            val members = unitRepo.fetchUnitMembers(unitId)
            val songs = songRepo.fetchUnitSongs(unitId)
            _uiState.value = UnitDetailUiState(
                unit = unit,
                members = members,
                songs = songs,
                isLoading = false
            )
            loadTags()
            loadSimilarUnits()
            loadPersonalTags()
        }
    }

    private suspend fun loadTags() {
        val tags = runCatching { api.unitTags(unitId) }.getOrDefault(emptyList())
        _uiState.value = _uiState.value.copy(tags = tags)
    }

    /** タグ類似のおすすめユニットをサーバから取得し、ローカル DB で ImasUnit に解決する (共有タグ数の降順を維持)。 */
    private suspend fun loadSimilarUnits() {
        val entries = runCatching { api.similarUnitsByTags(unitId) }.getOrDefault(emptyList())
        if (entries.isEmpty()) return
        val resolved = unitRepo.fetchUnitsByIds(entries.map { it.unitId })
        val byId = resolved.associateBy { it.id }
        val ordered = entries.mapNotNull { byId[it.unitId] }
        val sharedTags = entries.associate { it.unitId to it.sharedTags }
        _uiState.value = _uiState.value.copy(similarUnits = ordered, similarSharedTags = sharedTags)
    }

    private suspend fun loadPersonalTags() {
        val tags = personalTagRepo.tagsFor(PersonalTag.UNIT, unitId)
        _uiState.value = _uiState.value.copy(personalTags = tags)
    }

    /** 個人用タグを追加。サーバーには送信しない。 */
    fun addPersonalTag(name: String) {
        viewModelScope.launch {
            personalTagRepo.addTag(PersonalTag.UNIT, unitId, name)
            loadPersonalTags()
        }
    }

    /** 個人用タグを削除。 */
    fun removePersonalTag(name: String) {
        viewModelScope.launch {
            personalTagRepo.removeTag(PersonalTag.UNIT, unitId, name)
            loadPersonalTags()
        }
    }

    /** タグ投票のトグル (端末ベース)。完了後にタグを再取得。 */
    fun toggleTag(tag: CommunityApi.UnitTag) {
        viewModelScope.launch {
            runCatching {
                if (tag.mine) api.removeUnitTag(unitId, tag.id) else api.applyUnitTags(unitId, listOf(tag.id))
            }
            loadTags()
        }
    }

    /** タグ追加ピッカー (UnitTagPickerSheet) で新規タグを適用した後の再取得。 */
    fun onTagsApplied() {
        viewModelScope.launch { loadTags() }
    }

    class Factory(private val app: Application, private val unitId: String) :
        ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            UnitDetailViewModel(app, unitId) as T
    }
}
