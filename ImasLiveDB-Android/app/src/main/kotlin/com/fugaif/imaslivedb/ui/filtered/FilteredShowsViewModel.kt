package com.fugaif.imaslivedb.ui.filtered

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.VenueDirectory
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.songs.eventDisplayName
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import com.fugaif.imaslivedb.ui.theme.AppPreferences

/** 一覧に出す公演 1 行ぶんの表示値。整形はすべて ViewModel 側で済ませる。 */
data class FilteredShowRowUi(
    val showId: String,
    val title: String,
    val subtitle: String,
    val brandId: String?,
    /** 合同ライブ (複数ブランド) の行。1 ブランドの色を出すと嘘になるのでリードバーを虹色にする。 */
    val rainbow: Boolean
)

/** 年見出しと、その年の公演。 */
data class FilteredShowYearGroup(val year: String, val rows: List<FilteredShowRowUi>)

data class FilteredShowsUiState(
    val title: String = "",
    val groups: List<FilteredShowYearGroup> = emptyList(),
    val showCount: Int = 0,
    val isLoading: Boolean = true
)

/**
 * 「この会場での公演」「この日の公演」(iOS `FilteredShowsView`)。
 *
 * 会場での一覧は 20〜30 公演が数年にまたがるので、ライブ一覧と同じく**年で束ねる**。
 * 会場名・ライブ名の解決を行ごとにやると公演数ぶん問い合わせが増えるので、
 * イベントと会場マスタは 1 回ずつまとめて読んでメモリ上で突き合わせる。
 */
class FilteredShowsViewModel(
    app: Application,
    private val kind: String,
    private val value: String
) : AndroidViewModel(app) {

    private val events = AppModule.from(app).eventRepository

    private val _uiState = MutableStateFlow(FilteredShowsUiState(title = value))
    val uiState: StateFlow<FilteredShowsUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch { load() }
    }

    private suspend fun load() {
        val shows = when (kind) {
            ShowFilterKind.VENUE -> events.fetchShowsAtVenue(value)
            ShowFilterKind.DATE -> events.fetchShowsOnDate(value)
            else -> emptyList()
        }
        if (shows.isEmpty()) {
            _uiState.value = FilteredShowsUiState(title = resolveTitle(VenueDirectory.EMPTY), isLoading = false)
            return
        }

        val directory = events.fetchVenueDirectory()
        // 行ごとに fetchEvent を撃つと公演数に比例して境界を跨ぐ。イベントは全件でも小さいので
        // 1 回で読んで id で引く。
        val eventsById = events.fetchEvents().associateBy { it.id }

        // 同じ会場での一覧は全行が同じ会場なので、行に会場名を出すのは冗長。
        // 日付での一覧は行ごとに会場が違うので出す。
        val showsVenueInRow = kind != ShowFilterKind.VENUE

        val groups = shows.groupBy { it.date.take(4) }
            .toSortedMap(compareByDescending { it })
            .map { (year, yearShows) ->
                FilteredShowYearGroup(
                    year = year,
                    rows = yearShows.map { show ->
                        val event = eventsById[show.eventId]
                        FilteredShowRowUi(
                            showId = show.id,
                            title = event?.name?.let { AppPreferences.eventDisplayName(it) } ?: show.name,
                            subtitle = subtitle(show, directory, showsVenueInRow),
                            brandId = event?.brandId,
                            rainbow = event?.jointBrandIdList?.isNotEmpty() == true
                        )
                    }
                )
            }

        _uiState.value = FilteredShowsUiState(
            title = resolveTitle(directory),
            groups = groups,
            showCount = shows.size,
            isLoading = false
        )
    }

    /**
     * 会場一覧のタイトルは会場 ID ではなく名前で出す
     * (解決前だと "venue_京王アリーナtokyo での公演" のような ID がそのまま見えてしまう)。
     * 一覧の代表には現在名を使う — 行ごとの「当時の名前」は各行が別に解決する。
     */
    private fun resolveTitle(directory: VenueDirectory): String = when (kind) {
        ShowFilterKind.VENUE -> "${directory.venue(value)?.name ?: value}での公演"
        ShowFilterKind.DATE -> "${value}の公演"
        else -> value
    }

    /** 「07/25 ・ DAY2 ・ メインアリーナ」。年は見出しにあるので月日だけ出す。 */
    private fun subtitle(show: Show, directory: VenueDirectory, showsVenueInRow: Boolean): String {
        val parts = mutableListOf<String>()
        val ymd = show.date.split("-")
        parts.add(if (ymd.size >= 3) "${ymd[1]}/${ymd[2]}" else show.date)
        if (show.name.isNotEmpty()) parts.add(show.name)
        val venue = directory.displayName(show) ?: show.venue
        if (showsVenueInRow && !venue.isNullOrEmpty()) {
            parts.add(venue)
        } else {
            // 同じ会場でもホールが違えば別物なので、会場名を省く代わりにホールは出す。
            show.hall?.takeIf { it.isNotEmpty() }?.let { parts.add(it) }
        }
        return parts.joinToString(" ・ ")
    }

    class Factory(
        private val app: Application,
        private val kind: String,
        private val value: String
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            FilteredShowsViewModel(app, kind, value) as T
    }
}
