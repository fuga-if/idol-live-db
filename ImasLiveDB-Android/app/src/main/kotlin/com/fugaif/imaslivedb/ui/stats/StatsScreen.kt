package com.fugaif.imaslivedb.ui.stats

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.UncollectedSong
import com.fugaif.imaslivedb.data.model.UpcomingCatchChance
import com.fugaif.imaslivedb.ui.components.BrandFilterChips
import com.fugaif.imaslivedb.ui.components.BrandFilterItem
import com.fugaif.imaslivedb.ui.components.ImasArtwork
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.components.ImasListContainer
import com.fugaif.imaslivedb.ui.components.ImasMetricBadge
import com.fugaif.imaslivedb.ui.components.ImasRankingRow
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.components.ImasStatBar
import com.fugaif.imaslivedb.ui.components.ImasStatTile
import com.fugaif.imaslivedb.ui.events.SetlistScreen
import com.fugaif.imaslivedb.ui.songs.SongDetailScreen
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme

/**
 * 統計 = 回収ダッシュボード。iOS Views/Stats/StatsView.swift の 1:1 移植。
 * 回収サマリー(リング) → ブランド別回収率 → この公演で聴けるかも → 未回収曲(担当/全体切替)
 * → 最新の動き → コミュニティの熱量(お気に入りランキング) → 活動量/マスタ規模(既存)。
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

    Scaffold(topBar = { TopAppBar(title = { Text("回収ダッシュボード", fontWeight = FontWeight.Bold) }) }) { padding ->
        if (state.isLoading) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        } else {
            Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
                CollectionSummarySection(state.overallCollected, state.overallTotal)

                if (state.brandProgress.any { it.total > 0 }) {
                    ImasSectionHeader("ブランド別の回収率", tight = true)
                    ImasListContainer {
                        state.brandProgress.filter { it.total > 0 }.forEach { item ->
                            ImasStatBar(item.shortName, "${item.collected}/${item.total}", item.fraction * 100, seed = item.color)
                        }
                    }
                    Spacer(Modifier.height(20.dp))
                }

                if (state.catchChances.isNotEmpty()) {
                    ImasSectionHeader("この公演で聴けるかも", tight = true)
                    Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        state.catchChances.forEach { chance ->
                            CatchChanceCard(chance, onClick = { selectedShowId = chance.show.id })
                        }
                    }
                    Spacer(Modifier.height(20.dp))
                }

                UncollectedSection(
                    scope = state.uncollectedScope,
                    onScopeChange = viewModel::setUncollectedScope,
                    songs = state.uncollectedSongs,
                    isLoading = state.isLoadingDashboard,
                    myPickCollected = state.myPickCollected,
                    myPickTotal = state.myPickTotal,
                    onSongClick = { selectedSongId = it }
                )

                state.latestShow?.let { show ->
                    ImasSectionHeader("最新の動き", tight = true)
                    Box(Modifier.padding(horizontal = 16.dp)) {
                        LatestShowCard(
                            show = show,
                            songCount = state.latestShowSongCount,
                            brandColor = state.latestShowBrandColor,
                            onClick = { selectedShowId = show.id }
                        )
                    }
                    Spacer(Modifier.height(20.dp))
                }

                HeatSection(
                    brands = state.brands,
                    selectedBrandId = state.favoriteBrandId,
                    onBrandSelected = viewModel::selectFavoriteBrand,
                    ranking = state.favoritesRanking,
                    isLoading = state.isLoadingFavorites,
                    onSongClick = { selectedSongId = it }
                )

                state.databaseStats?.let { db ->
                    Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ImasStatTile(Icons.Filled.LibraryMusic, "${db.songCount}", "楽曲", modifier = Modifier.weight(1f))
                        ImasStatTile(Icons.Filled.Groups, "${db.idolCount}", "アイドル", modifier = Modifier.weight(1f))
                    }
                    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ImasStatTile(Icons.Filled.CalendarMonth, "${db.eventCount}", "イベント", modifier = Modifier.weight(1f))
                        ImasStatTile(Icons.Filled.Mic, "${db.showCount}", "公演", modifier = Modifier.weight(1f))
                    }
                }

                if (state.songPlayCounts.isNotEmpty()) {
                    ImasSectionHeader("活動量 ・ 披露回数", tight = true)
                    ImasListContainer {
                        state.songPlayCounts.forEachIndexed { i, s ->
                            ImasRankingRow(rank = i + 1, title = s.title, metric = "${s.playCount}", brand = s.brandId,
                                onClick = { selectedSongId = s.id }) {
                                ImasArtwork(title = s.title, brand = s.brandId, size = 44.dp)
                            }
                            if (i < state.songPlayCounts.size - 1) Divider(color = DS.sep)
                        }
                    }
                    Spacer(Modifier.height(20.dp))
                }

                if (state.castShowCounts.isNotEmpty()) {
                    ImasSectionHeader("活動量 ・ 出演回数", tight = true)
                    ImasListContainer {
                        state.castShowCounts.forEachIndexed { i, c ->
                            ImasRankingRow(rank = i + 1, title = c.name, metric = "${c.showCount}", unit = "人") {
                                ImasAvatar(label = c.name, size = 44.dp)
                            }
                            if (i < state.castShowCounts.size - 1) Divider(color = DS.sep)
                        }
                    }
                    Spacer(Modifier.height(20.dp))
                }

                if (state.brandSongCounts.isNotEmpty()) {
                    val max = state.brandSongCounts.maxOf { it.songCount }.coerceAtLeast(1)
                    ImasSectionHeader("マスタ規模 ・ ブランド別楽曲数", tight = true)
                    ImasListContainer {
                        state.brandSongCounts.forEach { b ->
                            ImasStatBar(b.shortName, "${b.songCount}", b.songCount * 100.0 / max, seed = b.color, brand = b.id)
                        }
                    }
                    Spacer(Modifier.height(20.dp))
                }

                if (state.yearlyShowCounts.isNotEmpty()) {
                    val max = state.yearlyShowCounts.maxOf { it.showCount }.coerceAtLeast(1)
                    ImasSectionHeader("年別 公演数")
                    state.yearlyShowCounts.forEach { y ->
                        ImasStatBar(y.year, "${y.showCount}", y.showCount * 100.0 / max)
                    }
                }
                Box(Modifier.size(24.dp).background(DS.bg))
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

// MARK: - 回収サマリー (全体リング)

@Composable
private fun CollectionSummarySection(collected: Int, total: Int) {
    ImasSectionHeader("あなたの回収率", tight = true)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(DS.surface)
            .padding(20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        CollectionRing(fraction = if (total > 0) collected.toDouble() / total else 0.0, modifier = Modifier.size(92.dp))
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("$collected", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                Text("/ ${total}曲", fontSize = 15.sp, color = DS.ink2)
            }
            Text("現地ライブで聴けた曲", fontSize = 13.sp, color = DS.ink2)
        }
    }
    Spacer(Modifier.height(20.dp))
}

@Composable
private fun CollectionRing(fraction: Double, modifier: Modifier = Modifier) {
    val t = ImasTheme.derive(null, null, dark = true)
    val clamped = fraction.coerceIn(0.0, 1.0)
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val stroke = Stroke(width = 10.dp.toPx(), cap = StrokeCap.Round)
            drawArc(DS.fill, startAngle = 0f, sweepAngle = 360f, useCenter = false, style = stroke, size = Size(size.width, size.height))
            drawArc(t.accent, startAngle = -90f, sweepAngle = (360 * clamped).toFloat(), useCenter = false, style = stroke, size = Size(size.width, size.height))
        }
        Text("${(clamped * 100).toInt()}%", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DS.ink)
    }
}

// MARK: - この公演で聴けるかも

@Composable
private fun CatchChanceCard(chance: UpcomingCatchChance, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(DS.surface)
            .clickable(onClick = onClick)
            .padding(20.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        ImasLeadBar(brandId = chance.brandId, height = 56.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("${displayDate(chance.show.date)} ・ ${chance.eventName}", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3, maxLines = 1)
            Text(chance.show.name, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink, maxLines = 2)
            chance.show.venue?.takeIf { it.isNotEmpty() }?.let { venue ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    androidx.compose.material3.Icon(Icons.Filled.LocationOn, null, tint = DS.ink2, modifier = Modifier.size(12.dp))
                    Text(venue, fontSize = 13.sp, color = DS.ink2, maxLines = 1)
                }
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            ImasMetricBadge(value = "${chance.likelyCount}", unit = "曲", seed = chance.brandId)
            Text("過去に披露", fontSize = 10.sp, color = DS.ink3)
        }
    }
}

// MARK: - 未回収曲

@Composable
private fun UncollectedSection(
    scope: UncollectedScope,
    onScopeChange: (UncollectedScope) -> Unit,
    songs: List<UncollectedSong>,
    isLoading: Boolean,
    myPickCollected: Int,
    myPickTotal: Int,
    onSongClick: (String) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("まだ生で聴けていない曲", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
        Box(Modifier.weight(1f))
        if (scope == UncollectedScope.MY_PICK && myPickTotal > 0) {
            Text("担当 $myPickCollected/$myPickTotal", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3)
        }
    }
    Spacer(Modifier.height(8.dp))
    Box(Modifier.padding(horizontal = 16.dp)) {
        ImasSegmented(
            labels = listOf("担当のオリ曲", "全体"),
            selection = scope.ordinal,
            onSelect = { onScopeChange(if (it == 0) UncollectedScope.MY_PICK else UncollectedScope.ALL) }
        )
    }
    Spacer(Modifier.height(8.dp))

    when {
        isLoading -> Box(Modifier.fillMaxWidth().padding(vertical = 30.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        songs.isEmpty() -> ImasEmptyState(
            icon = Icons.Filled.CheckCircle,
            title = if (scope == UncollectedScope.MY_PICK) "担当曲はコンプリート！" else "未回収曲はありません",
            message = if (scope == UncollectedScope.MY_PICK) "参加ライブを記録すると、担当のオリ曲の回収状況がここに出ます。"
                else "参加ライブを記録すると、未回収曲がここに並びます。"
        )
        else -> ImasListContainer {
            val shown = songs.take(30)
            shown.forEachIndexed { index, item ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onSongClick(item.song.id) }
                        .background(DS.surface)
                        .padding(horizontal = 14.dp, vertical = 9.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    ImasArtwork(title = item.song.title, brand = item.song.brandId, size = 44.dp, imageUrl = item.song.artworkUrl)
                    Column(Modifier.weight(1f)) {
                        Text(item.song.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 1)
                    }
                    FrequencyBadge(item)
                }
                if (index < shown.size - 1) Divider(color = DS.sep, modifier = Modifier.padding(start = 70.dp))
            }
        }
    }
    Spacer(Modifier.height(20.dp))
}

@Composable
private fun FrequencyBadge(item: UncollectedSong) {
    val fg = when {
        item.playCount >= 10 -> DS.warning
        item.playCount >= 3 -> DS.ink2
        else -> DS.ink3
    }
    val bg = if (item.playCount >= 10) DS.warning.copy(alpha = 0.14f) else DS.fill
    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Box(Modifier.clip(RoundedCornerShape(50)).background(bg).padding(horizontal = 8.dp, vertical = 2.dp)) {
            Text(item.frequencyLabel, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = fg)
        }
        if (item.playCount > 0) Text("${item.playCount}回披露", fontSize = 10.sp, color = DS.ink3)
    }
}

// MARK: - 最新の動き

@Composable
private fun LatestShowCard(show: com.fugaif.imaslivedb.data.model.Show, songCount: Int, brandColor: String?, onClick: () -> Unit) {
    val venueLine = buildList {
        show.venue?.takeIf { it.isNotEmpty() }?.let { add(it) }
        if (songCount > 0) add("セトリ ${songCount}曲")
    }.joinToString(" ・ ")

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(DS.surface)
            .clickable(onClick = onClick)
            .padding(20.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        ImasLeadBar(seedHex = brandColor, height = 64.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("最新公演 ・ ${displayDate(show.date)}", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3)
            Text(show.name, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink, maxLines = 2)
            if (venueLine.isNotEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    androidx.compose.material3.Icon(Icons.Filled.LocationOn, null, tint = DS.ink2, modifier = Modifier.size(12.dp))
                    Text(venueLine, fontSize = 13.sp, color = DS.ink2, maxLines = 1)
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                androidx.compose.material3.Icon(Icons.Filled.MusicNote, null, tint = DS.ink2, modifier = Modifier.size(13.dp))
                Text("セトリを見る", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
            }
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
    ImasSectionHeader("コミュニティの熱量", tight = true)
    BrandFilterChips(
        brands = brands.map { BrandFilterItem(it.id, it.shortName) },
        selectedBrandId = selectedBrandId,
        onBrandSelected = onBrandSelected
    )
    when {
        isLoading -> Box(Modifier.fillMaxWidth().padding(vertical = 30.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        ranking.isEmpty() -> ImasEmptyState(
            icon = Icons.Filled.Favorite,
            title = "まだデータがありません",
            message = "お気に入り登録が増えるとここにランキングが表示されます。"
        )
        else -> ImasListContainer {
            ranking.forEachIndexed { index, entry ->
                ImasRankingRow(
                    rank = index + 1, title = entry.title, metric = heatMetric(entry.count), unit = "♥",
                    brand = entry.brandId, onClick = { onSongClick(entry.songId) }
                ) {
                    ImasArtwork(title = entry.title, brand = entry.brandId, size = 44.dp, imageUrl = entry.artworkUrl)
                }
                if (index < ranking.size - 1) Divider(color = DS.sep, modifier = Modifier.padding(start = 52.dp))
            }
        }
    }
    Spacer(Modifier.height(20.dp))
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
