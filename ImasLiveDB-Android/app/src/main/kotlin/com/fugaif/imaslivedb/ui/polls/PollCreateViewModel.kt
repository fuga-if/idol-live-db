package com.fugaif.imaslivedb.ui.polls

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** 手動指定した候補 1 件 (表示名はローカル master から解決したもの)。 */
data class PollCandidate(val entityId: String, val displayName: String)

data class PollCreateUiState(
    val brands: List<Brand> = emptyList(),
    /** 候補指定スコープで選んだ候補。対象種別を切り替えたら混在させないため空にする。 */
    val candidates: List<PollCandidate> = emptyList(),
    val isSubmitting: Boolean = false,
    val errorMessage: String? = null
)

/**
 * お題作成フォームのうち、ローカル master / サーバに触る部分だけを持つ ViewModel。
 * タイトル等の素の入力値はシート側の `remember` に置き、ここは
 * 「ブランド一覧の読み込み」「候補 ID → 表示名の解決」「作成リクエスト」に絞る。
 */
class PollCreateViewModel(app: Application) : AndroidViewModel(app) {

    private val api = AppModule.from(app).communityApi
    private val songRepo = AppModule.from(app).songRepository
    private val idolRepo = AppModule.from(app).idolRepository
    private val unitRepo = AppModule.from(app).unitRepository
    private val statsRepo = AppModule.from(app).statsRepository

    private val _uiState = MutableStateFlow(PollCreateUiState())
    val uiState: StateFlow<PollCreateUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val brands = runCatching { statsRepo.fetchBrands() }.getOrDefault(emptyList())
            _uiState.value = _uiState.value.copy(brands = brands)
        }
    }

    /** ピッカーで選ばれた ID 群を、選択順を保ったまま候補リストへ反映する。 */
    fun setCandidates(targetType: String, entityIds: List<String>) {
        viewModelScope.launch {
            val names = resolveNames(targetType, entityIds)
            _uiState.value = _uiState.value.copy(
                candidates = entityIds.map { PollCandidate(it, names[it] ?: it) }
            )
        }
    }

    fun removeCandidate(entityId: String) {
        _uiState.value = _uiState.value.copy(
            candidates = _uiState.value.candidates.filterNot { it.entityId == entityId }
        )
    }

    /** 対象種別 (曲/アイドル/ユニット) を切り替えた時は候補を捨てる (種別をまたいだ候補は作れない)。 */
    fun clearCandidates() {
        _uiState.value = _uiState.value.copy(candidates = emptyList())
    }

    /** 作成に成功したら [onCreated] に新しいお題を渡す。失敗理由は uiState.errorMessage に出す。 */
    fun submit(
        title: String,
        description: String?,
        targetType: String,
        days: Int,
        scope: CommunityApi.PollCandidateScope,
        brandIds: Set<String>,
        onCreated: (CommunityApi.PollSummary) -> Unit
    ) {
        if (_uiState.value.isSubmitting) return
        _uiState.value = _uiState.value.copy(isSubmitting = true, errorMessage = null)
        viewModelScope.launch {
            val result = runCatching {
                api.createPoll(
                    title = title,
                    description = description,
                    targetType = targetType,
                    days = days,
                    candidateScope = scope,
                    // スコープ外の ID は送らない (サーバも無視するが、意図を body に出す)。
                    scopeBrandIds = brandIds.sorted(),
                    scopeEntityIds = _uiState.value.candidates.map { it.entityId },
                )
            }.getOrElse { CommunityApi.PollCreateResult.Error(null) }

            when (result) {
                is CommunityApi.PollCreateResult.Success -> {
                    _uiState.value = _uiState.value.copy(isSubmitting = false)
                    onCreated(result.poll)
                }
                is CommunityApi.PollCreateResult.RateLimited -> _uiState.value = _uiState.value.copy(
                    isSubmitting = false,
                    errorMessage = "本日のお題作成上限に達しました。明日また試してください。"
                )
                is CommunityApi.PollCreateResult.Error -> _uiState.value = _uiState.value.copy(
                    isSubmitting = false,
                    errorMessage = result.message ?: "作成に失敗しました。時間をおいて再試行してください。"
                )
            }
        }
    }

    private suspend fun resolveNames(targetType: String, ids: List<String>): Map<String, String> = when (targetType) {
        "idol" -> ids.associateWith { idolRepo.fetchIdol(it)?.name ?: it }
        "unit" -> unitRepo.fetchUnitsByIds(ids).associate { it.id to it.displayName }
        else -> songRepo.fetchSongsByIds(ids).associate { it.id to it.title }
    }
}
