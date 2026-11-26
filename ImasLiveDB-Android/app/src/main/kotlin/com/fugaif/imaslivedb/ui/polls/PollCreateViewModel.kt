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
import uniffi.imas_core.PollCreateQuotaNote
import uniffi.imas_core.pollCreateQuotaNote
import uniffi.imas_core.pollScopeBrandSelectable
import java.time.Instant
import java.time.ZoneId

/** 手動指定した候補 1 件 (表示名はローカル master から解決したもの)。 */
data class PollCandidate(val entityId: String, val displayName: String)

data class PollCreateUiState(
    val brands: List<Brand> = emptyList(),
    /** 候補指定スコープで選んだ候補。対象種別を切り替えたら混在させないため空にする。 */
    val candidates: List<PollCandidate> = emptyList(),
    val isSubmitting: Boolean = false,
    val errorMessage: String? = null,
    /** 今日あと何件作れるか。読めなかったとき (古いサーバ・オフライン) は出さず、送信も止めない。 */
    val quotaNote: PollCreateQuotaNote? = null
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
            // 「その他」は寄せ集めで限る意味が無いので並べない (規則はコア)。
            val brands = runCatching { statsRepo.fetchBrands() }.getOrDefault(emptyList())
                .filter { pollScopeBrandSelectable(it.id) }
            _uiState.value = _uiState.value.copy(brands = brands)
        }
    }

    /** 今日の作成枠を読み直す。シートを開くたびと、送信が弾かれたあとに呼ぶ (弾かれた送信も枠に数えられる)。 */
    fun loadQuota() {
        viewModelScope.launch {
            val quota = runCatching { api.pollCreateQuota() }.getOrNull() ?: return@launch
            _uiState.value = _uiState.value.copy(quotaNote = quotaNote(quota))
        }
    }

    /** 戻る時刻は端末の時刻で出す。文言はコア (`poll_create_quota_note`)。 */
    private fun quotaNote(quota: CommunityApi.PollCreateQuota): PollCreateQuotaNote {
        val reset = runCatching { Instant.parse(quota.resetAt).atZone(ZoneId.systemDefault()) }.getOrNull()
        return pollCreateQuotaNote(
            remaining = quota.remaining.coerceAtLeast(0).toUInt(),
            limit = quota.limit.coerceAtLeast(0).toUInt(),
            resetHour = (reset?.hour ?: 0).toUInt(),
            resetMinute = (reset?.minute ?: 0).toUInt(),
        )
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
            if (result !is CommunityApi.PollCreateResult.Success) loadQuota()
        }
    }

    private suspend fun resolveNames(targetType: String, ids: List<String>): Map<String, String> = when (targetType) {
        "idol" -> ids.associateWith { idolRepo.fetchIdol(it)?.name ?: it }
        "unit" -> unitRepo.fetchUnitsByIds(ids).associate { it.id to it.displayName }
        else -> songRepo.fetchSongsByIds(ids).associate { it.id to it.title }
    }
}
