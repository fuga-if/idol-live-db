package com.fugaif.imaslivedb.ui.idols

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.IdolPerformedSong
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.PersonalTag
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class IdolDetailUiState(
    val idol: Idol? = null,
    val brand: Brand? = null,
    val originalSongs: List<Song> = emptyList(),
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
    val isLoading: Boolean = true
) {
    /** 出演履歴のうち今日以降で最も近い公演 (= 次の出演)。無ければ null。 */
    val nextShow: CastShowRow?
        get() {
            val today = JstDay.today()
            return castShows.filter { it.date >= today }.minByOrNull { it.date }
        }
}

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
            val originalSongs = songRepo.fetchIdolSongs(idolId, "original")
            val performedSongs = repo.fetchIdolPerformedSongs(idolId)
            val units = unitRepo.fetchUnitsForIdol(idolId)
            val unitIdsWithSongs = unitRepo.fetchUnitIdsForIdolWithSongs(idolId)
            val castShows = repo.fetchIdolShows(idolId)

            _uiState.value = IdolDetailUiState(
                idol = idol,
                brand = brand,
                originalSongs = originalSongs,
                performedSongs = performedSongs,
                unitsWithSongs = units.filter { it.id in unitIdsWithSongs },
                unitsWithoutSongs = units.filter { it.id !in unitIdsWithSongs },
                castShows = castShows,
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

    /** 個人用タグを追加。サーバーには送信しない。 */
    fun addPersonalTag(name: String) {
        viewModelScope.launch {
            personalTagRepo.addTag(PersonalTag.IDOL, idolId, name)
            loadPersonalTags()
        }
    }

    /** 個人用タグを削除。 */
    fun removePersonalTag(name: String) {
        viewModelScope.launch {
            personalTagRepo.removeTag(PersonalTag.IDOL, idolId, name)
            loadPersonalTags()
        }
    }

    private suspend fun loadTags() {
        val tags = runCatching { api.idolTags(idolId) }.getOrDefault(emptyList())
        _uiState.value = _uiState.value.copy(tags = tags)
    }

    /**
     * タグ類似のおすすめアイドルをサーバから取得し、ローカル DB で Idol に解決する (共有タグ数の降順を維持)。
     * D1 に idols テーブルが無くサーバー側では is_external によるフィルタができないため、
     * 外部ゲスト演者 (isExternal) はここでローカル解決後に除外する (一覧/検索/統計と同じ扱い)。
     * サーバーには表示件数より多めの [SIMILAR_IDOLS_FETCH_LIMIT] 件を要求してから除外・trim することで、
     * 上位に外部ゲストが混ざっても表示件数が [SIMILAR_IDOLS_DISPLAY_LIMIT] 未満に痩せにくくする。
     */
    private suspend fun loadSimilarIdols() {
        val entries = runCatching {
            api.similarIdolsByTags(idolId, limit = SIMILAR_IDOLS_FETCH_LIMIT)
        }.getOrDefault(emptyList())
        if (entries.isEmpty()) return
        val resolved = repo.fetchIdolsByIds(entries.map { it.idolId }).filterNot { it.isExternal }
        val byId = resolved.associateBy { it.id }
        val ordered = entries.mapNotNull { byId[it.idolId] }.take(SIMILAR_IDOLS_DISPLAY_LIMIT)
        val sharedTags = ordered.associate { idol -> idol.id to entries.first { it.idolId == idol.id }.sharedTags }
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

    companion object {
        private const val SIMILAR_IDOLS_FETCH_LIMIT = 25
        private const val SIMILAR_IDOLS_DISPLAY_LIMIT = 10
    }
}
