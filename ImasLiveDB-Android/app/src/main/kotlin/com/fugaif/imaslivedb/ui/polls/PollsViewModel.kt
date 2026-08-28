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
    val isLoading: Boolean = true,
    /** 表示中のセグメント。true=開催中 / false=終了。 */
    val showActive: Boolean = true,
    /** 直近の取得に失敗した時の文言。既に一覧が出ている時は消さず、空の時だけ画面に出す。 */
    val loadError: String? = null
)

class PollsViewModel(app: Application) : AndroidViewModel(app) {

    private val api = AppModule.from(app).communityApi
    private val songRepo = AppModule.from(app).songRepository
    private val idolRepo = AppModule.from(app).idolRepository
    private val unitRepo = AppModule.from(app).unitRepository
    private val voteLog = AppModule.from(app).localPollVoteLog

    private val _uiState = MutableStateFlow(PollsUiState())
    val uiState: StateFlow<PollsUiState> = _uiState.asStateFlow()

    // セグメントごとのキャッシュ。1 お題につき詳細を 1 リクエスト引くので、
    // 切り替えのたびに取り直すと開催中/終了を往復するだけで通信が積み上がる。
    private var activeCards: List<PollCard>? = null
    private var pastCards: List<PollCard>? = null

    // 初回ロードは画面側の ON_RESUME (refresh) が担う。ここでも読むと、画面に出た瞬間に
    // 同じ一覧を 2 回取りに行くことになる。

    /** セグメント切替。読み込み済みならキャッシュを即出し、未読込のときだけ取りに行く。 */
    fun setShowActive(active: Boolean) {
        if (_uiState.value.showActive == active) return
        val cached = if (active) activeCards else pastCards
        _uiState.value = PollsUiState(
            cards = cached.orEmpty(),
            isLoading = cached == null,
            showActive = active,
        )
        if (cached == null) load()
    }

    /**
     * 表示中セグメントを取り直す。詳細画面での削除・投票が一覧に反映されるよう、
     * 画面が前面に戻るたびに呼ばれる (iOS PollListView の .onAppear 再ロードと同じ意図)。
     */
    fun refresh() {
        if (_uiState.value.showActive) activeCards = null else pastCards = null
        load()
    }

    private fun load() {
        val active = _uiState.value.showActive
        viewModelScope.launch {
            val polls = runCatching { api.polls(if (active) "active" else "past") }.getOrNull()
            // 読み込み中に利用者がセグメントを切り替えていたら、こちらの結果は捨てる
            // (遅れて届いた前のセグメントの一覧で上書きしないため)。
            val stillCurrent = { _uiState.value.showActive == active }
            if (polls == null) {
                // 取得失敗。表示中の一覧はそのまま残す (一度の通信エラーで全消えにしない)。
                if (stillCurrent()) _uiState.value = _uiState.value.copy(isLoading = false, loadError = "通信エラー")
                return@launch
            }
            val cards = polls.map { buildCard(it) }
            if (active) activeCards = cards else pastCards = cards
            if (stillCurrent()) {
                _uiState.value = _uiState.value.copy(cards = cards, isLoading = false, loadError = null)
            }
        }
    }

    /** 作成直後のお題を一覧の先頭へ差し込む (開催中セグメントのみ)。iOS insertCreated の移植。 */
    fun insertCreated(poll: CommunityApi.PollSummary) {
        if (!poll.isActive) return
        viewModelScope.launch {
            val card = buildCard(poll)
            activeCards = listOf(card) + activeCards.orEmpty()
            if (_uiState.value.showActive) {
                _uiState.value = _uiState.value.copy(cards = activeCards.orEmpty(), isLoading = false)
            }
        }
    }

    private suspend fun buildCard(poll: CommunityApi.PollSummary): PollCard {
        val detail = runCatching { api.pollDetail(poll.id) }.getOrNull()
        return PollCard(poll, detail, resolveNames(poll.targetType, detail))
    }

    private suspend fun resolveNames(targetType: String, detail: CommunityApi.PollDetail?): Map<String, String> {
        val ids = detail?.entries?.map { it.entityId } ?: return emptyMap()
        return ids.associateWith { resolveOneName(targetType, it) }
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

        val cards = _uiState.value.cards.map {
            if (it.poll.id == pollId) it.copy(detail = newDetail, entityNames = names) else it
        }
        // 楽観反映はキャッシュにも書き戻す。さもないとセグメントを往復した瞬間に票が巻き戻る。
        if (_uiState.value.showActive) activeCards = cards else pastCards = cards
        _uiState.value = _uiState.value.copy(cards = cards)
    }

    private suspend fun resolveOneName(targetType: String, id: String): String = when (targetType) {
        "idol" -> idolRepo.fetchIdol(id)?.name ?: id
        "unit" -> unitRepo.fetchUnit(id)?.displayName ?: id
        else -> songRepo.fetchSong(id)?.title ?: id
    }
}
