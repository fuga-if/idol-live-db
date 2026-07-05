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

data class PollCard(
    val poll: CommunityApi.PollSummary,
    val detail: CommunityApi.PollDetail?,
    val entityNames: Map<String, String>
)

data class PollsUiState(
    val cards: List<PollCard> = emptyList(),
    val isLoading: Boolean = true
)

class PollsViewModel(app: Application) : AndroidViewModel(app) {

    private val api = AppModule.from(app).communityApi
    private val songRepo = AppModule.from(app).songRepository
    private val idolRepo = AppModule.from(app).idolRepository
    private val voteLog = AppModule.from(app).localPollVoteLog

    private val _uiState = MutableStateFlow(PollsUiState())
    val uiState: StateFlow<PollsUiState> = _uiState.asStateFlow()

    init { load() }

    private fun load() {
        viewModelScope.launch {
            val polls = runCatching { api.polls() }.getOrDefault(emptyList())
            val cards = polls.map { p ->
                val detail = runCatching { api.pollDetail(p.id) }.getOrNull()
                PollCard(p, detail, resolveNames(p.targetType, detail))
            }
            _uiState.value = PollsUiState(cards = cards, isLoading = false)
        }
    }

    private suspend fun resolveNames(targetType: String, detail: CommunityApi.PollDetail?): Map<String, String> {
        val ids = detail?.entries?.map { it.entityId } ?: return emptyMap()
        return ids.associateWith { id ->
            when (targetType) {
                "idol" -> idolRepo.fetchIdol(id)?.name ?: id
                else -> songRepo.fetchSong(id)?.title ?: id
            }
        }
    }

    /** 既存候補へワンタップ投票/取消のトグル。 */
    fun toggleVote(pollId: String, entityId: String, currentlyMine: Boolean) {
        if (currentlyMine) unvote(pollId, entityId) else vote(pollId, entityId)
    }

    fun vote(pollId: String, entityId: String) {
        viewModelScope.launch {
            val result = runCatching { api.votePoll(pollId, entityId) }.getOrNull() ?: return@launch
            voteLog.recordVote(pollId, entityId)
            applyVoteResult(pollId, entityId, result, mine = true)
        }
    }

    fun unvote(pollId: String, entityId: String) {
        viewModelScope.launch {
            val result = runCatching { api.unvotePoll(pollId, entityId) }.getOrNull() ?: return@launch
            voteLog.removeVote(pollId, entityId)
            applyVoteResult(pollId, entityId, result, mine = false)
        }
    }

    /** ピッカーから新規候補へまとめて投票 (残り票数分だけ呼び出し側が絞って渡す想定)。 */
    fun voteForNewEntities(pollId: String, entityIds: List<String>) {
        viewModelScope.launch {
            for (id in entityIds) {
                val result = runCatching { api.votePoll(pollId, id) }.getOrNull() ?: continue
                voteLog.recordVote(pollId, id)
                applyVoteResult(pollId, id, result, mine = true)
            }
        }
    }

    /** 投票/取消の結果をローカルに楽観反映 (票数降順で並べ替え)。新規候補は名前を解決して追加する。 */
    private suspend fun applyVoteResult(
        pollId: String,
        entityId: String,
        result: CommunityApi.PollVoteResult,
        mine: Boolean
    ) {
        val card = _uiState.value.cards.firstOrNull { it.poll.id == pollId } ?: return
        val detail = card.detail ?: return
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
        val newDetail = detail.copy(entries = entries, myVoteCount = result.myVoteCount)
        val names = if (card.entityNames.containsKey(entityId)) card.entityNames
        else card.entityNames + (entityId to resolveOneName(card.poll.targetType, entityId))

        _uiState.value = _uiState.value.copy(
            cards = _uiState.value.cards.map {
                if (it.poll.id == pollId) it.copy(detail = newDetail, entityNames = names) else it
            }
        )
    }

    private suspend fun resolveOneName(targetType: String, id: String): String = when (targetType) {
        "idol" -> idolRepo.fetchIdol(id)?.name ?: id
        else -> songRepo.fetchSong(id)?.title ?: id
    }
}
