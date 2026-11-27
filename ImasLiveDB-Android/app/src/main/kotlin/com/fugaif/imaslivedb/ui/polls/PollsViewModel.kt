package com.fugaif.imaslivedb.ui.polls

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.async
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

/** 終了タブの 1 か月分 (iOS PollMonthSection の移植)。 */
data class PollMonthSection(
    val month: CommunityApi.PollMonth,
    val cards: List<PollCard>
)

data class PollsUiState(
    /** 開催中タブの一覧。 */
    val cards: List<PollCard> = emptyList(),
    /** 開催中タブ: まだ読んでいない次のページがあるか (直前のページが満杯だった)。 */
    val hasMoreActive: Boolean = false,
    /** 終了タブ: 締切の月 (日本時間) ごとのセクション (新しい月から)。 */
    val pastSections: List<PollMonthSection> = emptyList(),
    /** まだ読んでいない古い月があるか。 */
    val hasMorePast: Boolean = false,
    val isLoading: Boolean = true,
    /** 開催中タブの次のページ / 終了タブの「1 か月古い月」を読んでいる最中か。 */
    val isLoadingMore: Boolean = false,
    /** 表示中のセグメント。true=開催中 / false=終了。 */
    val showActive: Boolean = true,
    /** 直近の取得に失敗した時の文言。既に一覧が出ている時は消さず、空の時だけ画面に出す。 */
    val loadError: String? = null,
    /** 表示中のセグメントの並び (軸と向き)。 */
    val sort: CommunityApi.PollListSort = CommunityApi.PollListSort.standard(active = true),
    /**
     * 表示中のセグメントのお題の総数。開催中は `GET /polls/counts`、終了は月ごとの件数の合計。
     * 取れていなければ null (読んだ件数を総数のように見せない)。
     */
    val totalCount: Int? = null
)

/**
 * 投票のお題の一覧。`GET /polls` を 1 回呼ぶだけで、要約 (票の合計・状態・候補の範囲・1 位) を出す。
 *
 * 以前はお題ごとに `GET /polls/:id` を順に取り、一覧に候補と投票のボタンまで並べていた。
 * 画面が前面に来るたびに Worker (D1) を 1+N 回読んでいたので、iOS と同じく要約だけにした。
 *
 * 開催中タブは `status=active` を 20 件ずつ読み、末尾まで見たら offset を進めて次のページを読む。
 * 終了タブは `status=past` の件数既定 20 で古いお題が切れるため、月 (日本時間) ごとに読む。
 * 最初は新しい月だけ取り、末尾まで見たら 1 か月ずつさかのぼる (iOS PollListViewModel と同じ契約)。
 *
 * 並び (残り日数・作成日・票数 × 昇順 / 降順) はセグメントごとに持ち、サーバが並べる
 * (開催中は 20 件ずつしか読まないので、手元で並べ直すと続きのページと食い違う)。
 * 終了タブでは月の区切りは新しい月からのままで、月の中が選んだ並びになる。
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
    /** 開催中の次のページがあるか (直前に読んだページが満杯だった)。 */
    private var activeHasMore: Boolean = false
    /** 終了したお題がある月 (新しい月から)。`pastSections` の先頭から順に埋まる。 */
    private var pastMonths: List<CommunityApi.PollMonth>? = null
    private var pastSections: List<PollMonthSection>? = null
    /** セグメントごとの並び。締切の既定の向きがセグメントで逆なので別々に持つ。 */
    private var activeSort = CommunityApi.PollListSort.standard(active = true)
    private var pastSort = CommunityApi.PollListSort.standard(active = false)
    /** 開催中のお題の総数 (開催中を読むたびに取り直す)。 */
    private var activeTotal: Int? = null

    // 初回ロードは画面側の ON_RESUME (refresh) が担う。ここでも読むと、画面に出た瞬間に
    // 同じ一覧を 2 回取りに行くことになる。

    /** セグメント切替。読み込み済みならキャッシュを即出し、未読込のときだけ取りに行く。 */
    fun setShowActive(active: Boolean) {
        if (_uiState.value.showActive == active) return
        if (active) {
            val cached = activeCards
            _uiState.value = PollsUiState(
                cards = cached.orEmpty(),
                hasMoreActive = cached != null && activeHasMore,
                isLoading = cached == null,
                showActive = true,
                sort = activeSort,
                totalCount = activeTotal
            )
            if (cached == null) loadActive()
        } else {
            val cachedSections = pastSections
            _uiState.value = PollsUiState(
                pastSections = cachedSections.orEmpty(),
                hasMorePast = hasMorePast(pastMonths, cachedSections),
                isLoading = cachedSections == null,
                showActive = false,
                sort = pastSort,
                totalCount = pastTotal(pastMonths)
            )
            if (cachedSections == null) loadPast()
        }
    }

    /**
     * 表示中セグメントを取り直す。詳細画面での削除・投票が一覧に反映されるよう、
     * 画面が前面に戻るたびに呼ばれる (iOS PollListView の .onAppear 再ロードと同じ意図)。
     */
    fun refresh() {
        if (_uiState.value.showActive) {
            // 詳細から戻ったときの読み直しで、読み進めたページを畳まない (loadActive が既存の件数を保つ)。
            loadActive()
        } else {
            // 詳細から戻ったときの読み直しで、さかのぼった月を畳まない (loadPast が既存の件数を保つ)。
            loadPast()
        }
    }

    /**
     * 並びの軸を変える (表示中のセグメント)。向きはその軸の既定に戻す。前の軸で選んだ向きを持ち越すと、
     * 「票数順」が少ない順から始まるような、選んだ直後に意図と逆の並びになる (曲一覧と同じ)。
     */
    fun setSortKey(key: CommunityApi.PollSortKey) {
        val active = _uiState.value.showActive
        applySort(CommunityApi.PollListSort(key, key.defaultAscending(active)))
    }

    /** 並びの向き (昇順 / 降順) を変える (表示中のセグメント)。 */
    fun setSortAscending(ascending: Boolean) {
        applySort(_uiState.value.sort.copy(ascending = ascending))
    }

    /**
     * 読み進めた続きは古い並びのものなので捨て、先頭 (開催中は 20 件、終了は新しい月だけ) から読み直す。
     * 読み直すまでは今の一覧を出しておく (空にすると読み込み中の表示に切り替わって画面が跳ねる)。
     */
    private fun applySort(sort: CommunityApi.PollListSort) {
        if (sort == _uiState.value.sort) return
        if (_uiState.value.showActive) {
            activeSort = sort
            _uiState.value = _uiState.value.copy(sort = sort)
            loadActive(resetPaging = true)
        } else {
            pastSort = sort
            _uiState.value = _uiState.value.copy(sort = sort)
            loadPast(resetPaging = true)
        }
    }

    private fun loadActive(resetPaging: Boolean = false) {
        viewModelScope.launch {
            val sort = activeSort
            // 既に読んだ件数 (最低 1 ページ、上限はサーバの 100) ぶんを先頭から読み直す。並びを変えたときは 1 ページだけ。
            val limit = if (resetPaging) ACTIVE_PAGE_SIZE
            else (activeCards?.size ?: 0).coerceIn(ACTIVE_PAGE_SIZE, ACTIVE_MAX_LIMIT)
            // 総数は一覧と並べて取る。取れなくても一覧は出す (並び替えの行に件数が出ないだけ)。
            val counts = async { runCatching { api.pollCounts() }.getOrNull() }
            val polls = runCatching { api.activePolls(offset = 0, limit = limit, sort = sort) }.getOrNull()
            counts.await()?.let { activeTotal = it.active }
            // 待っている間に並びを変えられていたら、古い並びの結果は捨てる。
            if (sort != activeSort) return@launch
            // 読み込み中に利用者がセグメントを切り替えていたら、こちらの結果は捨てる
            // (遅れて届いた前のセグメントの一覧で上書きしないため)。
            val stillCurrent = { _uiState.value.showActive }
            if (polls == null) {
                // 取得失敗。表示中の一覧はそのまま残す (一度の通信エラーで全消えにしない)。
                if (stillCurrent()) _uiState.value = _uiState.value.copy(isLoading = false, loadError = "通信エラー")
                return@launch
            }
            val cards = polls.map { buildCard(it) }
            activeCards = cards
            activeHasMore = polls.size >= limit
            if (stillCurrent()) {
                _uiState.value = _uiState.value.copy(
                    cards = cards,
                    hasMoreActive = activeHasMore,
                    isLoading = false,
                    loadError = null,
                    totalCount = activeTotal
                )
            }
        }
    }

    /** 開催中タブの次のページ (20 件) を読む。末尾の行が見えたときに呼ぶ。 */
    fun loadMoreActive() {
        val cards = activeCards ?: return
        if (!activeHasMore) return
        if (_uiState.value.isLoadingMore || _uiState.value.isLoading) return
        _uiState.value = _uiState.value.copy(isLoadingMore = true)
        val sort = activeSort
        viewModelScope.launch {
            val polls = runCatching { api.activePolls(offset = cards.size, limit = ACTIVE_PAGE_SIZE, sort = sort) }.getOrNull()
            // 待っている間に読み直し・作成・並び替えで中身が入れ替わっていたら付け足さない。
            if (activeCards !== cards || sort != activeSort) {
                _uiState.value = _uiState.value.copy(isLoadingMore = false)
                return@launch
            }
            val stillCurrent = { _uiState.value.showActive }
            if (polls == null) {
                if (stillCurrent()) _uiState.value = _uiState.value.copy(isLoadingMore = false, loadError = "通信エラー")
                return@launch
            }
            // 読んでいる間に締切や新規作成で並びがずれると同じお題が重なるので、ID で重複を除く。
            val known = cards.mapTo(HashSet()) { it.poll.id }
            val newCards = cards + polls.filter { it.id !in known }.map { buildCard(it) }
            activeCards = newCards
            activeHasMore = polls.size >= ACTIVE_PAGE_SIZE
            if (stillCurrent()) {
                _uiState.value = _uiState.value.copy(
                    cards = newCards,
                    hasMoreActive = activeHasMore,
                    isLoadingMore = false,
                    loadError = null
                )
            }
        }
    }

    private fun loadPast(resetPaging: Boolean = false) {
        viewModelScope.launch {
            val sort = pastSort
            val stillCurrent = { !_uiState.value.showActive }
            val months = runCatching { api.pollMonths() }.getOrNull()
            if (months == null) {
                if (stillCurrent()) _uiState.value = _uiState.value.copy(isLoading = false, loadError = "通信エラー")
                return@launch
            }
            // 既に読んだ月数 (最低 1) ぶんを読み直す (詳細から戻ったときにさかのぼった月を畳まないため)。
            // 並びを変えたときは新しい月だけ。
            val keepCount = (if (resetPaging) 1 else maxOf(1, pastSections?.size ?: 0)).coerceAtMost(months.size)
            val sections = mutableListOf<PollMonthSection>()
            for (month in months.take(keepCount)) {
                val polls = runCatching { api.pastPolls(month.month, sort) }.getOrNull()
                if (polls == null) {
                    if (stillCurrent()) _uiState.value = _uiState.value.copy(isLoading = false, loadError = "通信エラー")
                    return@launch
                }
                sections.add(PollMonthSection(month, polls.map { buildCard(it) }))
            }
            if (sort != pastSort) return@launch
            pastMonths = months
            pastSections = sections
            if (stillCurrent()) {
                _uiState.value = _uiState.value.copy(
                    pastSections = sections,
                    hasMorePast = hasMorePast(months, sections),
                    isLoading = false,
                    loadError = null,
                    totalCount = pastTotal(months)
                )
            }
        }
    }

    /** 終了タブの次の (1 か月古い) 月を読む。末尾の行が見えたときに呼ぶ。 */
    fun loadMorePast() {
        val months = pastMonths ?: return
        val sections = pastSections ?: return
        if (sections.size >= months.size) return
        if (_uiState.value.isLoadingMore || _uiState.value.isLoading) return
        val month = months[sections.size]
        val sort = pastSort
        _uiState.value = _uiState.value.copy(isLoadingMore = true)
        viewModelScope.launch {
            val polls = runCatching { api.pastPolls(month.month, sort) }.getOrNull()
            // 待っている間に読み直し・並び替えで中身が入れ替わっていたら付け足さない。
            if (pastMonths !== months || pastSections !== sections || sort != pastSort) {
                _uiState.value = _uiState.value.copy(isLoadingMore = false)
                return@launch
            }
            val stillCurrent = { !_uiState.value.showActive }
            if (polls == null) {
                if (stillCurrent()) _uiState.value = _uiState.value.copy(isLoadingMore = false, loadError = "通信エラー")
                return@launch
            }
            val newSections = sections + PollMonthSection(month, polls.map { buildCard(it) })
            pastSections = newSections
            if (stillCurrent()) {
                _uiState.value = _uiState.value.copy(
                    pastSections = newSections,
                    hasMorePast = hasMorePast(months, newSections),
                    isLoadingMore = false,
                    loadError = null
                )
            }
        }
    }

    /**
     * 作成直後のお題を一覧の先頭へ差し込む (開催中セグメントのみ)。iOS insertCreated の移植。
     * どの並びでも先頭に出す (作った直後に自分のお題が見えることを優先する。次の読み直しで並びの位置に戻る)。
     */
    fun insertCreated(poll: CommunityApi.PollSummary) {
        if (!poll.isActive) return
        viewModelScope.launch {
            val card = buildCard(poll)
            activeCards = listOf(card) + activeCards.orEmpty()
            activeTotal = activeTotal?.plus(1)
            if (_uiState.value.showActive) {
                _uiState.value = _uiState.value.copy(cards = activeCards.orEmpty(), isLoading = false, totalCount = activeTotal)
            }
        }
    }

    private suspend fun buildCard(poll: CommunityApi.PollSummary) =
        PollCard(poll, poll.topEntityId?.let { entityName(poll.targetType, it) })

    private companion object {
        /** 開催中タブの 1 ページの件数 (サーバの既定と同じ)。 */
        const val ACTIVE_PAGE_SIZE = 20
        /** 読み直しで一度に取れる上限 (サーバの limit の上限)。 */
        const val ACTIVE_MAX_LIMIT = 100

        fun hasMorePast(months: List<CommunityApi.PollMonth>?, sections: List<PollMonthSection>?): Boolean =
            months != null && (sections?.size ?: 0) < months.size

        /** 終了したお題の総数 (月ごとの件数の合計)。月がまだ取れていなければ null。 */
        fun pastTotal(months: List<CommunityApi.PollMonth>?): Int? = months?.sumOf { it.count }

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
