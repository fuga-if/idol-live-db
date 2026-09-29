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

/** 1つの選択肢 (自分が投票した曲/アイドル) の表示用。 */
data class MyVoteChoice(val entityId: String, val label: String)

/** 1お題ぶんの表示行。 */
data class MyVoteEntry(val poll: CommunityApi.PollDetail, val choices: List<MyVoteChoice>)

data class MyVotesUiState(
    val entries: List<MyVoteEntry> = emptyList(),
    val isLoading: Boolean = true
)

/** マイ投票履歴。iOS MyVotesView の移植 (ローカル LocalPollVoteLog に積んだ pollId/entityId から
 *  お題詳細と投票先の曲/アイドル名を解決して並べる)。 */
class MyVotesViewModel(app: Application) : AndroidViewModel(app) {

    private val api = AppModule.from(app).communityApi
    private val songRepo = AppModule.from(app).songRepository
    private val idolRepo = AppModule.from(app).idolRepository
    private val unitRepo = AppModule.from(app).unitRepository
    private val voteLog = AppModule.from(app).localPollVoteLog

    private val _uiState = MutableStateFlow(MyVotesUiState())
    val uiState: StateFlow<MyVotesUiState> = _uiState.asStateFlow()

    init { load() }

    private fun load() {
        viewModelScope.launch {
            val log = voteLog.votes.value
            if (log.isEmpty()) {
                _uiState.value = MyVotesUiState(entries = emptyList(), isLoading = false)
                return@launch
            }
            val entries = log.mapNotNull { (pollId, entityIds) ->
                val detail = runCatching { api.pollDetail(pollId) }.getOrNull() ?: return@mapNotNull null
                val choices = entityIds.sorted().map { id ->
                    val label = when (detail.targetType) {
                        "idol" -> idolRepo.fetchIdol(id)?.name ?: "(削除済み)"
                        "unit" -> unitRepo.fetchUnit(id)?.displayName ?: "(削除済み)"
                        else -> songRepo.fetchSong(id)?.title ?: "(削除済み)"
                    }
                    MyVoteChoice(id, label)
                }
                MyVoteEntry(detail, choices)
            }
            // 開催中→終了 の順、内部は締切新しい順。
            val sorted = entries.sortedWith(
                compareByDescending<MyVoteEntry> { it.poll.isActive }.thenByDescending { it.poll.endsAtMs }
            )
            _uiState.value = MyVotesUiState(entries = sorted, isLoading = false)
        }
    }
}
