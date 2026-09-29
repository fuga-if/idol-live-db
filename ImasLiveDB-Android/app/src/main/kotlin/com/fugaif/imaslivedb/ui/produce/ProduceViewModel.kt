package com.fugaif.imaslivedb.ui.produce

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.community.DiscordLinkService
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.ExpenseEntry
import uniffi.imas_core.LedgerFilter
import uniffi.imas_core.LedgerLinkage
import uniffi.imas_core.LedgerPeriod
import uniffi.imas_core.buildLedgerSummary
import uniffi.imas_core.formatYen
import uniffi.imas_core.votesRemaining

/** 「最近見た」チップ 1 件 (id を名前まで解決したもの)。 */
data class RecentChip(val kind: RecentKind, val entityId: String, val name: String)

/** プロデュース先頭に出す「開催中のお題」。票数・候補数・残り時間はお題詳細から取る。 */
data class FeaturedPoll(
    val id: String,
    val title: String,
    val totalVotes: Int,
    val entryCount: Int,
    val remainingLabel: String
)

data class ProduceUiState(
    val pickedIdols: List<Idol> = emptyList(),
    val favoriteIdols: List<Idol> = emptyList(),
    val favoriteSongs: List<Song> = emptyList(),
    /** 参加したライブ (開催日降順)。上位数件をインラインに出し、超過分は一覧へ。 */
    val attendedEvents: List<EventWithDateRange> = emptyList(),
    /** お気に入りの合計 (曲 + アイドル + ライブ)。内訳はお気に入り一覧側のタブ。 */
    val favoriteCount: Int = 0,
    val collectedCount: Int = 0,
    val masteryCount: Int = 0,
    val voteCount: Int = 0,
    val contributionCount: Int = 0,
    val recents: List<RecentChip> = emptyList(),
    val featuredPoll: FeaturedPoll? = null,
    /** 収支 (家計簿) の合計。金額の表記はコア (`formatYen`) 一本。 */
    val ledgerTotalLabel: String = formatYen(0),
    val isLoading: Boolean = true,
    /** Discord ロール受け取り: 認可 URL を発行してもらっている間 true (二度押し防止 + くるくる)。 */
    val isLinkingDiscord: Boolean = false,
    /** 発行できた認可 URL。画面がブラウザで開いたら [ProduceViewModel.consumeDiscordLinkUrl] で消す。 */
    val discordLinkUrl: String? = null,
    val discordErrorMessage: String? = null
) {
    val attendedCount: Int get() = attendedEvents.size

    /** 統計タイル / ヒーローの控えめなティントに使う担当アイドルの代表色。 */
    val pickSeed: String? get() = pickedIdols.firstOrNull()?.color
}

class ProduceViewModel(app: Application) : AndroidViewModel(app) {

    private val module = AppModule.from(app)
    private val marks = module.userMarkRepository
    private val recentsStore = RecentsStore.get(app)

    private val _uiState = MutableStateFlow(ProduceUiState())
    val uiState: StateFlow<ProduceUiState> = _uiState.asStateFlow()

    /**
     * 初期ロードは持たない。画面が前面に来るたび ([androidx.lifecycle.Lifecycle.Event.ON_RESUME])
     * に呼ばれるので、init でも読むと初回だけお題の往復が二重に走る。
     */
    fun refresh() {
        viewModelScope.launch {
            // ローカル (Room / SharedPreferences) 由来はまとめて 1 回で反映する。
            // 「参加ライブ」はイベント参加 ∪ 公演参加→所属イベント を重複なしで取った一覧で、
            // 件数もこの一覧の長さにする (タイルの数字と一覧の行数が食い違わない)。
            val attended = module.eventRepository.fetchAttendedEvents()
            val favoriteCount = marks.favoriteSongIds().size +
                marks.favoriteIdolIds().size +
                module.eventRepository.fetchFavoriteEvents().size
            // 合計はコアに出させる (画面で足し算しない)。
            val expenses = module.expenseRepository.getAll().map {
                ExpenseEntry(
                    id = it.id, date = it.date, category = it.categoryValue, amount = it.amount,
                    showId = it.showId, eventId = it.eventId, showLabel = null, note = it.note
                )
            }
            val ledgerTotal = buildLedgerSummary(
                expenses, LedgerPeriod.ALL,
                LedgerFilter(year = "", categories = emptyList(), linkage = LedgerLinkage.ALL, eventId = "")
            ).total
            _uiState.value = _uiState.value.copy(
                pickedIdols = marks.pickedIdols(),
                favoriteIdols = marks.favoriteIdols(),
                favoriteSongs = marks.favoriteSongs(),
                attendedEvents = attended,
                favoriteCount = favoriteCount,
                collectedCount = module.songRepository.fetchCollectedSongIds().size,
                masteryCount = marks.masteryLevels().size,
                voteCount = module.localPollVoteLog.allEntries().size,
                contributionCount = module.localContributionLog.total,
                recents = resolveRecents(),
                ledgerTotalLabel = formatYen(ledgerTotal),
                isLoading = false
            )
        }
        viewModelScope.launch { loadFeaturedPoll() }
    }

    /**
     * Worker から 1 回限りの Discord 認可 URL をもらう。開くのは画面 (ブラウザへ渡す)。
     * ロール付与の結果は Worker のページが出すので、ここは URL を渡すところまで。
     */
    fun requestDiscordLink() {
        if (_uiState.value.isLinkingDiscord) return
        _uiState.value = _uiState.value.copy(isLinkingDiscord = true, discordErrorMessage = null)
        viewModelScope.launch {
            _uiState.value = try {
                val url = module.discordLinkService.authorizeUrl()
                _uiState.value.copy(isLinkingDiscord = false, discordLinkUrl = url)
            } catch (e: DiscordLinkService.LinkException) {
                _uiState.value.copy(isLinkingDiscord = false, discordErrorMessage = e.message)
            }
        }
    }

    fun consumeDiscordLinkUrl() {
        _uiState.value = _uiState.value.copy(discordLinkUrl = null)
    }

    fun clearDiscordError() {
        _uiState.value = _uiState.value.copy(discordErrorMessage = null)
    }

    /** 保存されているのは id だけなので、表示のたびにローカルのカタログで名前を引く。 */
    private suspend fun resolveRecents(): List<RecentChip> =
        recentsStore.items().mapNotNull { item ->
            val name = when (item.kind) {
                RecentKind.EVENT -> module.eventRepository.fetchEvent(item.entityId)?.name
                RecentKind.SONG -> module.songRepository.fetchSong(item.entityId)?.title
                RecentKind.IDOL -> module.idolRepository.fetchIdol(item.entityId)?.name
            }
            // 消えた (統合された) エンティティはチップごと落とす。id だけのチップは押しても何も無い。
            name?.let { RecentChip(item.kind, item.entityId, it) }
        }

    /**
     * 先頭に出す「開催中のお題」を 1 件選ぶ。まだ投票していないお題を優先し、
     * その中からランダムで選ぶ (毎回違うお題に触れてもらう導線)。
     *
     * iOS は一覧のレスポンスに自分の投票数が入っているのでその場で絞れるが、Android の
     * `polls()` は id/タイトル/対象種別しか読まない。ここで一覧を全部詳細まで引くと
     * タブを開くたびにお題の数だけ往復するので、シャッフルした先頭から数件だけ詳細を見て
     * 「未投票が見つかったら即採用」で打ち切る。全部投票済み (3/3) なら出さない。
     */
    private suspend fun loadFeaturedPoll() {
        val polls = runCatching { module.communityApi.polls() }.getOrNull().orEmpty()
        var fallback: FeaturedPoll? = null
        for (summary in polls.shuffled().take(MAX_POLL_PROBES)) {
            val detail = runCatching { module.communityApi.pollDetail(summary.id) }.getOrNull() ?: continue
            if (!detail.isActive) continue
            // 票を使い切ったお題はバナーに出さない (押しても投票できない)。票の上限はコア。
            if (votesRemaining(detail.myVoteCount.coerceAtLeast(0).toUInt()) == 0u) continue
            val card = detail.toFeaturedPoll(summary)
            if (detail.myVoteCount == 0) {
                _uiState.value = _uiState.value.copy(featuredPoll = card)
                return
            }
            if (fallback == null) fallback = card
        }
        _uiState.value = _uiState.value.copy(featuredPoll = fallback)
    }

    private fun CommunityApi.PollDetail.toFeaturedPoll(summary: CommunityApi.PollSummary) = FeaturedPoll(
        id = id.ifEmpty { summary.id },
        title = title.ifEmpty { summary.title },
        totalVotes = totalVotes,
        entryCount = entries.size,
        remainingLabel = statusLabel
    )

    companion object {
        /** 1 タブ表示あたりに詳細を引くお題の上限。 */
        private const val MAX_POLL_PROBES = 3
    }
}
