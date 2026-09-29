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

/**
 * 一覧の 1 行。お題の要約と、いま 1 位の候補の名前 (まだ票が無ければ null)。
 * 候補ごとの票と投票は詳細画面で扱う (iOS の一覧と同じ)。
 */
data class PollCard(
    val poll: CommunityApi.PollSummary,
    val topEntityName: String?
)

data class PollsUiState(
    val cards: List<PollCard> = emptyList(),
    val isLoading: Boolean = true,
    /** 表示中のセグメント。true=開催中 / false=終了。 */
    val showActive: Boolean = true,
    /** 直近の取得に失敗した時の文言。既に一覧が出ている時は消さず、空の時だけ画面に出す。 */
    val loadError: String? = null
)

/**
 * 投票のお題の一覧。`GET /polls` を 1 回呼ぶだけで、要約 (票の合計・状態・候補の範囲・1 位) を出す。
 *
 * 以前はお題ごとに `GET /polls/:id` を順に取り、一覧に候補と投票のボタンまで並べていた。
 * 画面が前面に来るたびに Worker (D1) を 1+N 回読んでいたので、iOS と同じく要約だけにした。
 */
class PollsViewModel internal constructor(
    app: Application,
    private val api: CommunityApi,
    /** (種別, ID) → 表示名。端末の DB で引く (通信しない)。 */
    private val entityName: suspend (String, String) -> String
) : AndroidViewModel(app) {

    constructor(app: Application) : this(app, AppModule.from(app).communityApi, localNameResolver(app))

    private val _uiState = MutableStateFlow(PollsUiState())
    val uiState: StateFlow<PollsUiState> = _uiState.asStateFlow()

    // セグメントごとのキャッシュ。開催中/終了を往復するだけで取り直さない。
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

    private suspend fun buildCard(poll: CommunityApi.PollSummary) =
        PollCard(poll, poll.topEntityId?.let { entityName(poll.targetType, it) })

    private companion object {
        fun localNameResolver(app: Application): suspend (String, String) -> String {
            val module = AppModule.from(app)
            return { targetType, id ->
                when (targetType) {
                    "idol" -> module.idolRepository.fetchIdol(id)?.name ?: id
                    "unit" -> module.unitRepository.fetchUnit(id)?.displayName ?: id
                    else -> module.songRepository.fetchSong(id)?.title ?: id
                }
            }
        }
    }
}
