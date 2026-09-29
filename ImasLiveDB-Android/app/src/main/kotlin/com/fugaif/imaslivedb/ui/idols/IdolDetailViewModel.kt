package com.fugaif.imaslivedb.ui.idols

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.IdolPerformedSong
import com.fugaif.imaslivedb.data.model.IdolSongSection
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.PersonalTag
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.SimilarIdolCandidate
import uniffi.imas_core.nextShowIndex
import uniffi.imas_core.similarIdolsFetchLimit
import com.fugaif.imaslivedb.data.local.localWrite

data class IdolDetailUiState(
    val idol: Idol? = null,
    val brand: Brand? = null,
    val originalSongSections: List<IdolSongSection> = emptyList(),
    val performedSongs: List<IdolPerformedSong> = emptyList(),
    val unitsWithSongs: List<ImasUnit> = emptyList(),
    val unitsWithoutSongs: List<ImasUnit> = emptyList(),
    val castShows: List<CastShowRow> = emptyList(),
    val tags: List<CommunityApi.IdolTag> = emptyList(),
    /** タグが似ているアイドル (この人が好きな人にはこの人も, サーバ算出)。 */
    val similarTagIdols: List<Idol> = emptyList(),
    val similarSharedTags: Map<String, Int> = emptyMap(),
    /** 個人用タグ (端末ローカルのみ、サーバーには送信しない)。 */
    val personalTags: List<PersonalTag> = emptyList(),
    /** 出演履歴のうち今日以降で最も近い公演 (= 次の出演)。選び方はコア (nextShowIndex)。 */
    val nextShow: CastShowRow? = null,
    val isLoading: Boolean = true
)

class IdolDetailViewModel(app: Application, private val idolId: String) : AndroidViewModel(app) {

    private val repo = AppModule.from(app).idolRepository
    private val unitRepo = AppModule.from(app).unitRepository
    private val songRepo = AppModule.from(app).songRepository
    private val api = AppModule.from(app).communityApi
    private val personalTagRepo = AppModule.from(app).personalTagRepository

    private val _uiState = MutableStateFlow(IdolDetailUiState())
    val uiState: StateFlow<IdolDetailUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            val idol = repo.fetchIdol(idolId) ?: return@launch
            val brand = repo.fetchBrand(idol.brandId)
            val originalSongSections = songRepo.fetchIdolOriginalSongSections(idolId)
            val performedSongs = repo.fetchIdolPerformedSongs(idolId)
            val units = unitRepo.fetchUnitsForIdol(idolId)
            val unitIdsWithSongs = unitRepo.fetchUnitIdsForIdolWithSongs(idolId)
            val castShows = repo.fetchIdolShows(idolId)

            _uiState.value = IdolDetailUiState(
                idol = idol,
                brand = brand,
                originalSongSections = originalSongSections,
                performedSongs = performedSongs,
                unitsWithSongs = units.filter { it.id in unitIdsWithSongs },
                unitsWithoutSongs = units.filter { it.id !in unitIdsWithSongs },
                castShows = castShows,
                nextShow = nextShowIndex(castShows.map { it.date }, JstDay.today())?.let { castShows[it.toInt()] },
                isLoading = false
            )
            loadTags()
            loadSimilarIdols()
            loadPersonalTags()
        }
    }

    private suspend fun loadPersonalTags() {
        val tags = personalTagRepo.tagsFor(PersonalTag.IDOL, idolId)
        _uiState.value = _uiState.value.copy(personalTags = tags)
    }

    /** 個人用タグを追加。サーバーには送信しない。足せたときだけ [onAdded] (入力欄を空にする)。 */
    fun addPersonalTag(name: String, onAdded: () -> Unit) {
        viewModelScope.launch {
            localWrite("マイタグの追加") { personalTagRepo.addTag(PersonalTag.IDOL, idolId, name) }
                ?: return@launch
            onAdded()
            loadPersonalTags()
        }
    }

    /** 個人用タグを削除。 */
    fun removePersonalTag(name: String) {
        viewModelScope.launch {
            localWrite("マイタグの削除") { personalTagRepo.removeTag(PersonalTag.IDOL, idolId, name) }
            loadPersonalTags()
        }
    }

    private suspend fun loadTags() {
        val tags = runCatching { api.idolTags(idolId) }.getOrDefault(emptyList())
        _uiState.value = _uiState.value.copy(tags = tags)
    }

    /**
     * タグ類似のおすすめアイドル (サーバ算出)。サーバに頼む件数と、どれを出すか
     * (手元に無い id と外部ゲストを除き、サーバの並びのまま 10 件) はコアが決める。
     */
    private suspend fun loadSimilarIdols() {
        val entries = runCatching {
            api.similarIdolsByTags(idolId, limit = similarIdolsFetchLimit().toInt())
        }.getOrDefault(emptyList())
        if (entries.isEmpty()) return
        val picked = repo.pickSimilarIdols(entries.map { SimilarIdolCandidate(it.idolId, it.sharedTags.toUInt()) })
        val byId = repo.fetchIdolsByIds(picked.map { it.idolId }).associateBy { it.id }
        val ordered = picked.mapNotNull { byId[it.idolId] }
        val sharedTags = picked.associate { it.idolId to it.sharedTags.toInt() }
        _uiState.value = _uiState.value.copy(similarTagIdols = ordered, similarSharedTags = sharedTags)
    }

    /** タグ投票のトグル (端末ベース)。完了後にタグを再取得。 */
    fun toggleTag(tag: CommunityApi.IdolTag) {
        viewModelScope.launch {
            runCatching {
                if (tag.mine) api.removeIdolTag(idolId, tag.id) else api.applyIdolTags(idolId, listOf(tag.id))
            }
            loadTags()
        }
    }

    /** タグ追加ピッカー (IdolTagPickerSheet) で新規タグを適用した後の再取得。 */
    fun onTagsApplied() {
        viewModelScope.launch { loadTags() }
    }

    class Factory(private val app: Application, private val idolId: String) :
        ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            IdolDetailViewModel(app, idolId) as T
    }
}
