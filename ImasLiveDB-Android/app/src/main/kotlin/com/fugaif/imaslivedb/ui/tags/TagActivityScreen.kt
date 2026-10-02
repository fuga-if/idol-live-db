package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.ui.designsystem.ImasArtwork
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasCardListStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasLazyPage
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasRankBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasRecordRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowChevron
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.designsystem.ImasSwatch
import com.fugaif.imaslivedb.ui.designsystem.ImasSwatchSize
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import uniffi.imas_core.relativeTimes

private enum class ActivityTab(val label: String) {
    SONG("曲"), IDOL("アイドル")
}

/** タグ付けの盛り上がり。「伸びてるタグ」「タグが急増中」「最近つけられたタグ」を
 * 曲/アイドルのドメインタブで横断表示する。iOS TagActivityView の移植。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagActivityScreen(
    onBack: (() -> Unit)?,
    onSongTagClick: (String) -> Unit,
    onIdolTagClick: (String) -> Unit,
    onSongClick: (String) -> Unit,
    onIdolClick: (String) -> Unit,
    viewModel: TagActivityViewModel = viewModel()
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var tabIndex by rememberSaveable { mutableIntStateOf(0) }
    val tabs = remember { ActivityTab.entries }
    val selectedDomain = if (tabs[tabIndex] == ActivityTab.SONG) {
        CommunityApi.TagActivityDomain.SONG
    } else {
        CommunityApi.TagActivityDomain.IDOL
    }

    LaunchedEffect(Unit) { viewModel.load(context) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("タグの動き") },
                navigationIcon = {
                    // サイドバーの根として開いたときは戻る先が無いので出さない。
                    onBack?.let { back ->
                        IconButton(onClick = back) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                        }
                    }
                }
            )
        }
    ) { padding ->
        val activity = uiState.activity
        if (uiState.isLoading && activity == null) {
            Box(Modifier.fillMaxSize().padding(padding)) { ImasLoadingState() }
        } else if (activity == null || (activity.trendingTags.isEmpty() && activity.risingEntities.isEmpty() && activity.recent.isEmpty())) {
            Box(Modifier.fillMaxSize().padding(padding)) {
                ImasEmptyState(
                    icon = Icons.Filled.LocalFireDepartment,
                    title = "まだ動きがありません",
                    modifier = Modifier.align(Alignment.Center)
                )
            }
        } else {
            val trends = activity.trendingTags.filter { it.domain == selectedDomain }
            val rises = activity.risingEntities.filter { it.domain == selectedDomain }
            val events = activity.recent.filter { it.domain == selectedDomain }
            // 相対時刻の言い回しはコア。一覧ぶんを 1 回で引き、一覧が変わるまで使い回す。
            val times = remember(events) { relativeTimes(events.map { it.createdAtMs }, System.currentTimeMillis()) }

            ImasLazyPage(modifier = Modifier.fillMaxSize().padding(padding)) {
                item {
                    ImasSegmented(
                        labels = tabs.map { it.label },
                        selection = tabIndex,
                        onSelect = { tabIndex = it }
                    )
                }

                if (trends.isEmpty() && rises.isEmpty() && events.isEmpty()) {
                    item {
                        ImasEmptyState(
                            icon = Icons.Filled.LocalFireDepartment,
                            title = "まだ動きがありません",
                            message = if (selectedDomain == CommunityApi.TagActivityDomain.SONG) {
                                "曲にタグを付けると、ここに反映されます。"
                            } else {
                                "アイドルにタグを付けると、ここに反映されます。"
                            }
                        )
                    }
                } else {
                    if (trends.isNotEmpty()) {
                        item {
                            ImasSection(title = "伸びてるタグ", style = ImasSectionHeaderStyle.SMALL) {
                                ImasCardList(style = ImasCardListStyle.PANEL) {
                                    trends.forEachIndexed { idx, trend ->
                                        if (idx > 0) ImasRowDivider(inset = DS.sp4)
                                        TrendRow(trend, rank = idx + 1) {
                                            if (selectedDomain == CommunityApi.TagActivityDomain.SONG) {
                                                onSongTagClick(trend.tagId)
                                            } else {
                                                onIdolTagClick(trend.tagId)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if (rises.isNotEmpty()) {
                        item {
                            ImasSection(title = "タグが急増中", style = ImasSectionHeaderStyle.SMALL) {
                                ImasCardList(style = ImasCardListStyle.PANEL) {
                                    rises.forEachIndexed { idx, rise ->
                                        if (idx > 0) ImasRowDivider(inset = DS.sp4)
                                        RiseRow(
                                            rise = rise,
                                            song = uiState.songs[rise.entityId],
                                            idol = uiState.idols[rise.entityId],
                                            onClick = {
                                                if (rise.domain == CommunityApi.TagActivityDomain.SONG) onSongClick(rise.entityId)
                                                else onIdolClick(rise.entityId)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    if (events.isNotEmpty()) {
                        item {
                            ImasSection(title = "最近つけられたタグ", style = ImasSectionHeaderStyle.SMALL) {
                                ImasCardList(style = ImasCardListStyle.PANEL) {
                                    events.forEachIndexed { index, event ->
                                        if (index > 0) ImasRowDivider(inset = DS.sp4)
                                        RecentRow(
                                            event = event,
                                            timeText = times.getOrElse(index) { "" },
                                            song = uiState.songs[event.entityId],
                                            idol = uiState.idols[event.entityId],
                                            onClick = {
                                                if (event.domain == CommunityApi.TagActivityDomain.SONG) onSongClick(event.entityId)
                                                else onIdolClick(event.entityId)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TrendRow(trend: CommunityApi.TagActivityTrend, rank: Int, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        ImasRankBadge(rank)
        ImasRecordRow(
            title = trend.tagName,
            modifier = Modifier.weight(1f).imasRowPress(onClick = onClick),
            leading = trend.tagColor?.let { hex ->
                ImasRowLeading.Custom(width = ImasSwatchSize.DOT.diameter) { ImasSwatch(hex, size = ImasSwatchSize.DOT) }
            },
            trailing = ImasRowTrailing.Custom {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                        Text("直近${trend.recentCount}件", style = ImasTextRole.ROW_SUBTITLE.style, color = DS.ink)
                        Text("累計${trend.totalCount}", style = ImasTextRole.META.style, color = ImasTextRole.META.color)
                    }
                    ImasRowChevron()
                }
            }
        )
    }
}

@Composable
private fun RiseRow(
    rise: CommunityApi.TagActivityRise,
    song: Song?,
    idol: Idol?,
    onClick: () -> Unit
) {
    val resolved = if (rise.domain == CommunityApi.TagActivityDomain.SONG) song != null else idol != null
    ImasRecordRow(
        title = entityName(rise.domain, song, idol),
        modifier = Modifier
            .fillMaxWidth()
            .imasRowPress(enabled = resolved, onClick = onClick)
            .alpha(if (resolved) 1f else 0.45f),
        leading = ImasRowLeading.Custom(width = 40.dp) { EntityLead(domain = rise.domain, song = song, idol = idol) },
        subtitle = "「${rise.tagName}」",
        trailing = ImasRowTrailing.Custom {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Filled.ArrowUpward,
                        contentDescription = null,
                        tint = DS.favorite,
                        modifier = Modifier.size(with(LocalDensity.current) { 11.sp.toDp() })
                    )
                    Text("${rise.recentCount}件", style = ImasTextRole.BADGE.style, color = DS.favorite)
                }
                ImasRowChevron()
            }
        }
    )
}

@Composable
private fun RecentRow(
    event: CommunityApi.TagActivityEvent,
    timeText: String,
    song: Song?,
    idol: Idol?,
    onClick: () -> Unit
) {
    val resolved = if (event.domain == CommunityApi.TagActivityDomain.SONG) song != null else idol != null
    ImasRecordRow(
        title = entityName(event.domain, song, idol),
        modifier = Modifier
            .fillMaxWidth()
            .imasRowPress(enabled = resolved, onClick = onClick)
            .alpha(if (resolved) 1f else 0.45f),
        leading = ImasRowLeading.Custom(width = 40.dp) { EntityLead(domain = event.domain, song = song, idol = idol) },
        subtitle = "「${event.tagName}」タグが付きました",
        trailing = ImasRowTrailing.Value(timeText)
    )
}

@Composable
private fun EntityLead(domain: CommunityApi.TagActivityDomain, song: Song?, idol: Idol?) {
    when (domain) {
        CommunityApi.TagActivityDomain.SONG ->
            ImasArtwork(title = song?.title ?: "?", size = 40.dp, imageUrl = song?.artworkUrl)
        CommunityApi.TagActivityDomain.IDOL ->
            ImasAvatar(label = idol?.shortName ?: "?", seed = idol?.color, brand = idol?.brandId, size = 40.dp)
    }
}

private fun entityName(domain: CommunityApi.TagActivityDomain, song: Song?, idol: Idol?): String = when (domain) {
    CommunityApi.TagActivityDomain.SONG -> song?.title ?: "曲を読み込み中"
    CommunityApi.TagActivityDomain.IDOL -> idol?.name ?: "アイドルを読み込み中"
}
