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

    fun vote(pollId: String, entityId: String) {
        viewModelScope.launch {
            runCatching { api.votePoll(pollId, entityId) }
            // 再取得して票数/自分の投票を反映
            val polls = _uiState.value.cards.map { it.poll }
            val cards = polls.map { p ->
                val detail = runCatching { api.pollDetail(p.id) }.getOrNull()
                PollCard(p, detail, resolveNames(p.targetType, detail))
            }
            _uiState.value = _uiState.value.copy(cards = cards)
        }
    }
}
