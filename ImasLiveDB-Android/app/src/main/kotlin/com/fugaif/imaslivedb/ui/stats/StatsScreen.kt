package com.fugaif.imaslivedb.ui.stats

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.BrandFilterItem
import com.fugaif.imaslivedb.ui.designsystem.ImasArtwork
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeSpec
import com.fugaif.imaslivedb.ui.designsystem.ImasBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasBoard
import com.fugaif.imaslivedb.ui.designsystem.ImasBoardCell
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasChip
import com.fugaif.imaslivedb.ui.designsystem.ImasChipStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasMetric
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasProgressRing
import com.fugaif.imaslivedb.ui.designsystem.ImasRankingRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasShowRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSongRow
import com.fugaif.imaslivedb.ui.designsystem.ImasStatBar
import com.fugaif.imaslivedb.ui.designsystem.ImasStatGrid
import com.fugaif.imaslivedb.ui.designsystem.ImasStatTile
import com.fugaif.imaslivedb.ui.designsystem.ImasTicket
import com.fugaif.imaslivedb.ui.designsystem.ImasTicketCountdown
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.events.SetlistScreen
import com.fugaif.imaslivedb.ui.share.CollectionShareSheet
import com.fugaif.imaslivedb.ui.songs.SongDetailScreen
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import uniffi.imas_core.CatchChanceRecord
import uniffi.imas_core.PlayFrequency
import uniffi.imas_core.UncollectedSongRecord

/**
 * 統計 = 回収ダッシュボード。iOS Views/Stats/StatsView.swift の移植。
 * 回収サマリー(リング) → ブランド別回収率 → この公演で聴けるかも → 未回収曲(担当/全体切替)
 * → 最新の動き → コミュニティの熱量(お気に入りランキング) → データ規模(Android 独自) → 活動量/マスタ規模。
 *
 * 曲/公演タップは NavRoutes/AppNavigation を変更せず、画面内 Dialog で SongDetailScreen /
 * SetlistScreen をそのまま埋め込んで完結させる (iOS の .sheet(item:) と同等の挙動)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatsScreen(viewModel: StatsViewModel = viewModel()) {
    val state by viewModel.uiState.collectAsState()
    var selectedSongId by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedShowId by rememberSaveable { mutableStateOf<String?>(null) }

    Scaffold(topBar = { TopAppBar(title = { Text("回収ダッシュボード") }) }) { padding ->
        if (state.isLoading) {
            ImasLoadingState(modifier = Modifier.padding(padding))
        } else {
            ImasPage(modifier = Modifier.padding(padding)) {
                CollectionSummarySection(state.overallCollected, state.overallTotal)

                val brandProgress = state.brandProgress.filter { it.total > 0u }
                if (brandProgress.isNotEmpty()) {
                    ImasSection("ブランド別の回収率", style = ImasSectionHeaderStyle.SMALL) {
                        ImasCard {
                            Column {
                                brandProgress.forEach { item ->
                                    ImasStatBar(
                                        label = item.shortName,
                                        value = "${item.collected}/${item.total}",
                                        percent = item.collected.toDouble() / item.total.toDouble() * 100,
                                        seed = item.color,
                                        contentPadding = InCardStatBarPadding
                                    )
                                }
                            }
                        }
                    }
                }

                if (state.catchChances.isNotEmpty()) {
                    ImasSection("この公演で聴けるかも", style = ImasSectionHeaderStyle.SMALL) {
                        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                            state.catchChances.forEach { chance ->
                                CatchChanceTicket(chance, onClick = { selectedShowId = chance.show.id })
                            }
                        }
                    }
                }

                UncollectedSection(
                    scope = state.uncollectedScope,
                    onScopeChange = viewModel::setUncollectedScope,
                    songs = state.uncollectedSongs,
                    brands = state.brands,
                    isLoading = state.isLoadingDashboard,
                    myPickCollected = state.myPickCollected,
                    myPickTotal = state.myPickTotal,
                    onSongClick = { selectedSongId = it }
                )

                state.latestShow?.let { show ->
                    LatestSection(
                        show = show,
                        songCount = state.latestShowSongCount,
                        brandColor = state.latestShowBrandColor,
                        onClick = { selectedShowId = show.id }
                    )
                }

                HeatSection(
                    brands = state.brands,
                    selectedBrandId = state.favoriteBrandId,
                    onBrandSelected = viewModel::selectFavoriteBrand,
                    ranking = state.favoritesRanking,
                    isLoading = state.isLoadingFavorites,
                    onSongClick = { selectedSongId = it }
                )

                // iOS には無い Android 独自の区画 (マスタの規模を一目で)。
                state.databaseStats?.let { db ->
                    ImasStatGrid(columns = 2) {
                        ImasStatTile(Icons.Filled.LibraryMusic, "${db.songCount}", "楽曲")
                        ImasStatTile(Icons.Filled.Groups, "${db.idolCount}", "アイドル")
                        ImasStatTile(Icons.Filled.CalendarMonth, "${db.eventCount}", "イベント")
                        ImasStatTile(Icons.Filled.Mic, "${db.showCount}", "公演")
                    }
                }

                if (state.songPlayCounts.isNotEmpty()) {
                    ImasSection("活動量 ・ 披露回数", style = ImasSectionHeaderStyle.SMALL) {
                        ImasCardList(items = state.songPlayCounts.withIndex().toList(), key = { it.index }) { (index, s) ->
                            ImasRankingRow(
                                rank = index + 1,
                                title = s.title,
                                metric = "${s.playCount}",
                                brand = s.brandId,
                                onClick = { selectedSongId = s.id }
                            ) {
                                ImasArtwork(title = s.title, brand = s.brandId, size = 44.dp, imageUrl = s.artworkUrl)
                            }
                        }
                    }
                }

                if (state.castShowCounts.isNotEmpty()) {
                    ImasSection("活動量 ・ 出演回数", style = ImasSectionHeaderStyle.SMALL) {
                        ImasCardList(items = state.castShowCounts.withIndex().toList(), key = { it.index }) { (index, c) ->
                            ImasRankingRow(rank = index + 1, title = c.name, metric = "${c.showCount}", unit = "公演") {
                                ImasAvatar(label = c.name, size = 44.dp)
                            }
                        }
                    }
                }

                if (state.brandSongCounts.isNotEmpty()) {
                    val max = state.brandSongCounts.maxOf { it.songCount }.coerceAtLeast(1)
                    ImasSection("マスタ規模 ・ ブランド別楽曲数", style = ImasSectionHeaderStyle.SMALL) {
                        ImasCard {
                            Column {
                                state.brandSongCounts.forEach { b ->
                                    ImasStatBar(
                                        label = b.shortName,
                                        value = "${b.songCount}",
                                        percent = b.songCount * 100.0 / max,
                                        seed = b.color,
                                        brand = b.id,
                                        contentPadding = InCardStatBarPadding
                                    )
                                }
                            }
                        }
                    }
                }

                // iOS には無い Android 独自の区画。
                if (state.yearlyShowCounts.isNotEmpty()) {
                    val max = state.yearlyShowCounts.maxOf { it.showCount }.coerceAtLeast(1)
                    ImasSection("年別 公演数", style = ImasSectionHeaderStyle.SMALL) {
                        ImasCard {
                            Column {
                                state.yearlyShowCounts.forEach { y ->
                                    ImasStatBar(
                                        label = y.year,
                                        value = "${y.showCount}",
                                        percent = y.showCount * 100.0 / max,
                                        contentPadding = InCardStatBarPadding
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    selectedSongId?.let { id ->
        Dialog(onDismissRequest = { selectedSongId = null }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            SongDetailScreen(
                songId = id,
                onBack = { selectedSongId = null },
                onUnitClick = {},
                onIdolClick = {},
                onShowClick = { showId -> selectedSongId = null; selectedShowId = showId }
            )
        }
    }
    selectedShowId?.let { id ->
        Dialog(onDismissRequest = { selectedShowId = null }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            SetlistScreen(
                showId = id,
                onBack = { selectedShowId = null },
                onSongClick = { songId -> selectedShowId = null; selectedSongId = songId },
                onIdolClick = {}
            )
        }
    }
}

/** カードの中の [ImasStatBar] の余白 (左右は面の余白と二重になるので 0)。 */
private val InCardStatBarPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 0.dp, vertical = DS.Space.gap)

// MARK: - 回収サマリー (全体リング + シェア導線)

@Composable
private fun CollectionSummarySection(collected: Int, total: Int) {
    var showShareCard by rememberSaveable { mutableStateOf(false) }

    ImasSection("あなたの回収率", style = ImasSectionHeaderStyle.SMALL) {
        ImasCard {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.card)) {
                androidx.compose.foundation.layout.Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(DS.Space.card)
                ) {
                    ImasProgressRing(fraction = if (total > 0) collected.toDouble() / total else 0.0, size = 92.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                        ImasBoard(cells = listOf(ImasBoardCell(value = "$collected / $total", unit = "曲", label = "現地ライブで聴けた曲")))
                        ImasChip(
                            text = "カードでシェア",
                            icon = Icons.Filled.Share,
                            style = ImasChipStyle.SELECTED,
                            onClick = { showShareCard = true }
                        )
                    }
                }
            }
        }
    }

    if (showShareCard) {
        CollectionShareSheet(collected = collected, total = total, onDismiss = { showShareCard = false })
    }
}

// MARK: - この公演で聴けるかも

@Composable
private fun CatchChanceTicket(chance: CatchChanceRecord, onClick: () -> Unit) {
    val eventLabel = if (AppPreferences.abbreviateEventNames) chance.eventShortName else chance.eventName
    ImasTicket(
        label = "${displayDate(chance.show.date)} ・ $eventLabel",
        title = chance.show.name,
        imprint = null,
        meta = chance.show.venue?.takeIf { it.isNotEmpty() },
        metaIcon = Icons.Filled.LocationOn,
        seed = chance.brandColor,
        countdown = ImasTicketCountdown(value = "${chance.likelyCount}", prefix = "過去に披露", unit = "曲"),
        onOpen = onClick
    )
}

// MARK: - 未回収曲

@Composable
private fun UncollectedSection(
    scope: UncollectedScope,
    onScopeChange: (UncollectedScope) -> Unit,
    songs: List<UncollectedSongRecord>,
    brands: List<com.fugaif.imaslivedb.data.model.Brand>,
    isLoading: Boolean,
    myPickCollected: Int,
    myPickTotal: Int,
    onSongClick: (String) -> Unit
) {
    ImasSection(
        "まだ生で聴けていない曲",
        count = if (scope == UncollectedScope.MY_PICK && myPickTotal > 0) "担当 $myPickCollected/$myPickTotal" else null,
        style = ImasSectionHeaderStyle.SMALL
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            ImasSegmented(
                labels = listOf("担当のオリ曲", "全体"),
                selection = scope.ordinal,
                onSelect = { onScopeChange(if (it == 0) UncollectedScope.MY_PICK else UncollectedScope.ALL) }
            )

            when {
                isLoading -> ImasInlineLoading()
                songs.isEmpty() -> ImasCard {
                    ImasEmptyState(
                        icon = Icons.Filled.CheckCircle,
                        title = if (scope == UncollectedScope.MY_PICK) "担当曲はコンプリート！" else "未回収曲はありません",
                        message = if (scope == UncollectedScope.MY_PICK) "参加ライブを記録すると、担当のオリ曲の回収状況がここに出ます。"
                            else "参加ライブを記録すると、未回収曲がここに並びます。"
                    )
                }
                else -> ImasCardList(items = songs.take(30)) { item ->
                    ImasSongRow(
                        title = item.song.title,
                        artworkUrl = item.song.artworkUrl,
                        brand = item.song.brandId,
                        trailing = ImasRowTrailing.Custom { FrequencyBadge(item) },
                        onClick = { onSongClick(item.song.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun FrequencyBadge(item: UncollectedSongRecord) {
    // 披露頻度の種類 (閾値はコア。画面で回数を比べない)。
    val kind = when (item.frequency) {
        PlayFrequency.STAPLE -> ImasBadgeKind.ATTENTION
        PlayFrequency.SOMETIMES -> ImasBadgeKind.NEUTRAL
        PlayFrequency.RARE, PlayFrequency.NEVER -> ImasBadgeKind.NEGATIVE
    }
    Column(horizontalAlignment = androidx.compose.ui.Alignment.End, verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        ImasBadge(item.frequencyLabel, kind = kind)
        if (item.playCount > 0u) ImasMetric("${item.playCount}", unit = "回披露", size = ImasNumeralSize.SMALL)
    }
}

// MARK: - 最新の動き

@Composable
private fun LatestSection(show: com.fugaif.imaslivedb.data.model.Show, songCount: Int, brandColor: String?, onClick: () -> Unit) {
    val venueLine = buildList {
        show.venue?.takeIf { it.isNotEmpty() }?.let { add(it) }
        if (songCount > 0) add("セトリ ${songCount}曲")
    }.joinToString(" ・ ")

    ImasSection("最新の動き", style = ImasSectionHeaderStyle.SMALL) {
        ImasShowRow(
            date = show.date,
            title = show.name,
            modifier = Modifier.imasRowPress(onClick = onClick),
            subtitle = venueLine.ifEmpty { null },
            subtitleIcon = Icons.Filled.LocationOn,
            seed = brandColor,
            badges = listOf(ImasBadgeSpec("最新公演", kind = ImasBadgeKind.NEUTRAL)),
            subtitleLineLimit = 2,
            detailAccessibilityLabel = "セトリを見る"
        ) {
            ImasChip(text = "セトリを見る", icon = Icons.Filled.MusicNote, style = ImasChipStyle.THEMED, seed = brandColor)
        }
    }
}

// MARK: - コミュニティの熱量

@Composable
private fun HeatSection(
    brands: List<com.fugaif.imaslivedb.data.model.Brand>,
    selectedBrandId: String?,
    onBrandSelected: (String?) -> Unit,
    ranking: List<com.fugaif.imaslivedb.data.model.FavoriteRankingEntry>,
    isLoading: Boolean,
    onSongClick: (String) -> Unit
) {
    ImasSection("コミュニティの熱量", style = ImasSectionHeaderStyle.SMALL) {
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            BrandFilterChips(
                brands = brands.map { BrandFilterItem(it.id, it.shortName) },
                selectedBrandId = selectedBrandId,
                onBrandSelected = onBrandSelected
            )
            when {
                isLoading -> ImasInlineLoading()
                ranking.isEmpty() -> ImasCard {
                    ImasEmptyState(
                        icon = Icons.Filled.Favorite,
                        title = "まだデータがありません",
                        message = "お気に入り登録が増えるとここにランキングが表示されます。"
                    )
                }
                else -> ImasCardList(items = ranking.withIndex().toList(), key = { it.index }) { (index, entry) ->
                    ImasRankingRow(
                        rank = index + 1,
                        title = entry.title,
                        metric = heatMetric(entry.count),
                        unit = "♥",
                        brand = entry.brandId,
                        onClick = { onSongClick(entry.songId) }
                    ) {
                        ImasArtwork(title = entry.title, brand = entry.brandId, size = 44.dp, imageUrl = entry.artworkUrl)
                    }
                }
            }
        }
    }
}

/** "1280" → "1,280" のような桁区切り。 */
private fun heatMetric(count: Int): String =
    "%,d".format(count)

/** "2026-06-04" → "6/4" 表示用。失敗時は元文字列。 */
private fun displayDate(raw: String): String {
    val comps = raw.split("-")
    if (comps.size < 3) return raw
    val m = comps[1].toIntOrNull() ?: return raw
    val d = comps[2].toIntOrNull() ?: return raw
    return "$m/$d"
}
