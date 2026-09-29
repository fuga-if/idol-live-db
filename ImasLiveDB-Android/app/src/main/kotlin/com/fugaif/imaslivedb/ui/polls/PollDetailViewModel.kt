package com.fugaif.imaslivedb.ui.polls

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.planVoteSelection

data class PollDetailUiState(
    val isLoading: Boolean = true,
    val detail: CommunityApi.PollDetail? = null,
    val entityNames: Map<String, String> = emptyMap(),
    val isDeleting: Boolean = false,
    val deleteError: String? = null
)

/** お題詳細。iOS PollDetailView の移植 (単体お題の投票・候補追加)。 */
class PollDetailViewModel(app: Application) : AndroidViewModel(app) {

    private val api = AppModule.from(app).communityApi
    private val songRepo = AppModule.from(app).songRepository
    private val idolRepo = AppModule.from(app).idolRepository
    private val unitRepo = AppModule.from(app).unitRepository
    private val voteLog = AppModule.from(app).localPollVoteLog

    private val _uiState = MutableStateFlow(PollDetailUiState())
    val uiState: StateFlow<PollDetailUiState> = _uiState.asStateFlow()

    private var pollId: String? = null

    fun load(pollId: String) {
        if (this.pollId == pollId && _uiState.value.detail != null) return
        this.pollId = pollId
        viewModelScope.launch { reload() }
    }

    private suspend fun reload() {
        val id = pollId ?: return
        _uiState.value = _uiState.value.copy(isLoading = true)
        val detail = runCatching { api.pollDetail(id) }.getOrNull()
        if (detail == null) {
            _uiState.value = _uiState.value.copy(isLoading = false)
            return
        }
        val names = resolveNames(detail.targetType, detail.entries.map { it.entityId })
        _uiState.value = PollDetailUiState(isLoading = false, detail = detail, entityNames = names)
    }

    private suspend fun resolveNames(targetType: String, ids: List<String>): Map<String, String> =
        ids.associateWith { resolveOneName(targetType, it) }

    private suspend fun resolveOneName(targetType: String, id: String): String = when (targetType) {
        "idol" -> idolRepo.fetchIdol(id)?.name ?: id
        "unit" -> unitRepo.fetchUnit(id)?.displayName ?: id
        else -> songRepo.fetchSong(id)?.title ?: id
    }

    /** 削除に成功したら [onDeleted] (詳細を閉じる) を呼ぶ。失敗理由は uiState.deleteError に出す。 */
    fun delete(onDeleted: () -> Unit) {
        val id = pollId ?: return
        if (_uiState.value.isDeleting) return
        _uiState.value = _uiState.value.copy(isDeleting = true, deleteError = null)
        viewModelScope.launch {
            val ok = runCatching { api.deletePoll(id) }.getOrDefault(false)
            _uiState.value = _uiState.value.copy(
                isDeleting = false,
                deleteError = if (ok) null else "削除に失敗しました。時間をおいて再試行してください。"
            )
            if (ok) onDeleted()
        }
    }

    fun clearDeleteError() {
        _uiState.value = _uiState.value.copy(deleteError = null)
    }

    /** 既存候補へワンタップ投票/取消のトグル。 */
    fun toggleVote(entityId: String, currentlyMine: Boolean) {
        if (currentlyMine) unvote(entityId) else vote(entityId)
    }

    fun vote(entityId: String) {
        val id = pollId ?: return
        viewModelScope.launch {
            val result = runCatching { api.votePoll(id, entityId) }.getOrNull() ?: return@launch
            voteLog.recordVote(id, entityId)
            applyVoteResult(entityId, result, mine = true)
        }
    }

    fun unvote(entityId: String) {
        val id = pollId ?: return
        viewModelScope.launch {
            val result = runCatching { api.unvotePoll(id, entityId) }.getOrNull() ?: return@launch
            voteLog.removeVote(id, entityId)
            applyVoteResult(entityId, result, mine = false)
        }
    }

    /**
     * ピッカーの選択 (選択肢の表示順) からまとめて投票/取消する。何を入れて何を取り消すか・
     * 残りの票数での打ち切りはコア ([planVoteSelection])。取り消しを先に流す。
     */
    fun applyPickerSelection(selectedInOrder: List<String>, unvoteDeselected: Boolean) {
        val id = pollId ?: return
        val detail = _uiState.value.detail ?: return
        val plan = planVoteSelection(
            detail.entries.filter { it.mine }.map { it.entityId },
            selectedInOrder,
            detail.myVoteCount.coerceAtLeast(0).toUInt(),
            unvoteDeselected
        )
        viewModelScope.launch {
            for (entityId in plan.toUnvote) {
                val result = runCatching { api.unvotePoll(id, entityId) }.getOrNull() ?: continue
                voteLog.removeVote(id, entityId)
                applyVoteResult(entityId, result, mine = false)
            }
            for (entityId in plan.toVote) {
                val result = runCatching { api.votePoll(id, entityId) }.getOrNull() ?: continue
                voteLog.recordVote(id, entityId)
                applyVoteResult(entityId, result, mine = true)
            }
        }
    }

    /** 投票/取消の結果をローカルに楽観反映 (票数降順で並べ替え)。新規候補は名前を解決して追加する。 */
    private suspend fun applyVoteResult(entityId: String, result: CommunityApi.PollVoteResult, mine: Boolean) {
        val detail = _uiState.value.detail ?: return
        val keepZeroVote = detail.candidateScope == CommunityApi.PollCandidateScope.MANUAL
        val entries = detail.entries.toMutableList()
        val idx = entries.indexOfFirst { it.entityId == entityId }
        val updated = CommunityApi.PollEntry(entityId, result.voteCount, mine)
        if (idx >= 0) {
            if (result.voteCount == 0 && !mine && !keepZeroVote) entries.removeAt(idx) else entries[idx] = updated
        } else if (result.voteCount > 0 || keepZeroVote) {
            entries.add(updated)
        }
        entries.sortByDescending { it.voteCount }
        val names = if (_uiState.value.entityNames.containsKey(entityId)) _uiState.value.entityNames
        else _uiState.value.entityNames + (entityId to resolveOneName(detail.targetType, entityId))

        _uiState.value = _uiState.value.copy(
            detail = detail.copy(entries = entries, myVoteCount = result.myVoteCount, totalVotes = entries.sumOf { it.voteCount }),
            entityNames = names
        )
    }
}
