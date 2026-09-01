package com.fugaif.imaslivedb.ui.produce

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.HowToVote
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.Timeline
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.ui.components.ImasLeadBar
import com.fugaif.imaslivedb.ui.components.ImasSectionHeader
import com.fugaif.imaslivedb.ui.components.ImasStatTile
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.brandColor
import com.fugaif.imaslivedb.ui.theme.hexToColor

/** インラインに並べる「参加したライブ」の件数。超えたぶんは一覧へ送る。 */
private const val ATTENDED_INLINE_LIMIT = 5

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProduceScreen(
    onNavigateToStats: () -> Unit,
    onNavigateToSettings: () -> Unit,
    onNavigateToPolls: () -> Unit,
    onNavigateToPollDetail: (String) -> Unit,
    onNavigateToIdol: (String) -> Unit,
    onNavigateToSong: (String) -> Unit,
    onNavigateToEvent: (String) -> Unit,
    onNavigateToFavorites: () -> Unit,
    onNavigateToAttendedEvents: () -> Unit,
    onNavigateToCollectedSongs: () -> Unit,
    onNavigateToTimeline: (String?) -> Unit,
    onNavigateToMyContributions: () -> Unit,
    onNavigateToMyVotes: () -> Unit,
    onNavigateToEditHistory: () -> Unit,
    onNavigateToTagList: () -> Unit,
    onNavigateToTagActivity: () -> Unit,
    onNavigateToGamesHub: () -> Unit,
    viewModel: ProduceViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    // 他タブで見た曲・付けたマークがそのまま数字に効くので、前面に来るたび読み直す。
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { viewModel.refresh() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("プロデュース", fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = onNavigateToSettings) { Icon(Icons.Filled.Settings, "設定・マイ") }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())
        ) {
            if (state.pickedIdols.isEmpty() && state.favoriteIdols.isEmpty() && state.favoriteSongs.isEmpty()) {
                Text(
                    "アイドルや楽曲の詳細画面で ♥ を押すと、担当・お気に入りがここに並びます",
                    modifier = Modifier.fillMaxWidth().padding(24.dp),
                    color = DS.ink3,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            IdolSection("担当", state.pickedIdols, DS.pick, onNavigateToIdol)

            state.featuredPoll?.let { poll ->
                FeaturedPollCard(poll = poll, onClick = { onNavigateToPollDetail(poll.id) })
            }

            ActivitySection(state = state,
                onAttendedClick = onNavigateToAttendedEvents,
                onFavoritesClick = onNavigateToFavorites,
                onContributionsClick = onNavigateToMyContributions,
                onVotesClick = onNavigateToMyVotes,
                onCollectedClick = onNavigateToCollectedSongs
            )

            RecentsSection(
                recents = state.recents,
                onClick = { chip ->
                    when (chip.kind) {
                        RecentKind.EVENT -> onNavigateToEvent(chip.entityId)
                        RecentKind.SONG -> onNavigateToSong(chip.entityId)
                        RecentKind.IDOL -> onNavigateToIdol(chip.entityId)
                    }
                }
            )

            AttendedSection(
                events = state.attendedEvents,
                onEventClick = onNavigateToEvent,
                onSeeAll = onNavigateToAttendedEvents
            )

            IdolSection("お気に入りアイドル", state.favoriteIdols, DS.favorite, onNavigateToIdol)
            if (state.favoriteSongs.isNotEmpty()) {
                SectionTitle("お気に入り曲")
                state.favoriteSongs.forEach { song ->
                    SongLine(song) { onNavigateToSong(song.id) }
                }
            }

            HorizontalDivider(color = DS.sep, modifier = Modifier.padding(top = 8.dp))
            HubRow(Icons.Filled.Favorite, "お気に入り一覧", "曲・アイドル・ライブ", DS.ink2, state.favoriteCount, onNavigateToFavorites)
            HorizontalDivider(color = DS.sep)
            HubRow(Icons.Filled.EventAvailable, "参加したライブ", "", DS.ink2, state.attendedCount, onNavigateToAttendedEvents)
            HorizontalDivider(color = DS.sep)
            HubRow(Icons.Filled.MusicNote, "回収した楽曲", "現地で聴けた曲だけの一覧", DS.ink2, state.collectedCount, onNavigateToCollectedSongs)
            HorizontalDivider(color = DS.sep)
            // 年表は担当アイドルのブランドから開く (見たい歴史はたいてい担当の歴史)。
            // 担当がいなければブランド指定なしで開き、年表側が先頭ブランドを選ぶ。
            HubRow(Icons.Filled.Timeline, "年表", "ライブ・楽曲シリーズ・節目を1枚で俯瞰する", DS.ink2, null) {
                onNavigateToTimeline(state.pickedIdols.firstOrNull()?.brandId)
            }
            HorizontalDivider(color = DS.sep)
            HubRow(Icons.Filled.HowToVote, "投票・予想", "タグ・ペンライト・ポール", DS.ink2, null, onNavigateToPolls)
            HorizontalDivider(color = DS.sep)
            HubRow(Icons.Filled.Sell, "みんなのタグ", "楽曲タグの作成・閲覧", DS.ink2, null, onNavigateToTagList)
            HorizontalDivider(color = DS.sep)
            HubRow(Icons.Filled.LocalFireDepartment, "タグの動き", "伸びてるタグ・急上昇の曲やアイドルをチェック", DS.ink2, null, onNavigateToTagActivity)
            HorizontalDivider(color = DS.sep)
            HubRow(Icons.AutoMirrored.Filled.ListAlt, "マイ投稿・編集履歴", "", DS.ink2, state.contributionCount, onNavigateToMyContributions)
            HorizontalDivider(color = DS.sep)
            HubRow(Icons.Filled.HowToVote, "投票履歴", "", DS.ink2, state.voteCount, onNavigateToMyVotes)
            HorizontalDivider(color = DS.sep)
            HubRow(Icons.Filled.History, "みんなの編集履歴", "", DS.ink2, null, onNavigateToEditHistory)
            HorizontalDivider(color = DS.sep)
            HubRow(Icons.Filled.SportsEsports, "ゲーム", "クイズ・イントロ当てクイズ", DS.ink2, null, onNavigateToGamesHub)
            HorizontalDivider(color = DS.sep)
            HubRow(Icons.Filled.BarChart, "統計", "ブランド別・年別・ランキング", DS.ink2, null, onNavigateToStats)
            HorizontalDivider(color = DS.sep)
            HubRow(Icons.Filled.Settings, "設定・マイ", "", DS.ink2, null, onNavigateToSettings)
            Spacer(Modifier.height(24.dp))
        }
    }
}

/**
 * 開催中のお題の大きなカード。プロデュースの先頭近くに置いて投票へ誘導する。
 *
 * ここだけ固定のグラデーションで塗るのは意図的 — 「いま参加できる催し」であって
 * 特定のブランド/アイドルの持ち物ではないので、エンティティ色から導出すると
 * 中身と関係ない色をまとってしまう (iOS も同じ 2 色のグラデーション)。
 */
@Composable
private fun FeaturedPollCard(poll: FeaturedPoll, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(
                Brush.linearGradient(
                    listOf(Color(0xFFFF4D8C), Color(0xFF8C59F2))
                )
            )
            .clickable(onClick = onClick)
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.HowToVote, null, tint = Color.White, modifier = Modifier.size(15.dp))
            Text(
                "投票受付中", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White,
                modifier = Modifier.padding(start = 6.dp)
            )
            Spacer(Modifier.weight(1f))
            Text(poll.remainingLabel, fontSize = 12.sp, color = Color.White.copy(alpha = 0.95f))
        }
        Text(
            poll.title, fontSize = 19.sp, fontWeight = FontWeight.Bold, color = Color.White,
            maxLines = 2, overflow = TextOverflow.Ellipsis
        )
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            PollMeta(Icons.Filled.ThumbUp, "${poll.totalVotes}票")
            PollMeta(Icons.Filled.FormatListNumbered, "${poll.entryCount}候補")
            Spacer(Modifier.weight(1f))
            Text("投票する", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White)
            Icon(
                Icons.AutoMirrored.Filled.ArrowForward, null, tint = Color.White,
                modifier = Modifier.size(15.dp).padding(start = 4.dp)
            )
        }
    }
}

@Composable
private fun PollMeta(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(13.dp))
        Text(text, fontSize = 12.sp, color = Color.White, modifier = Modifier.padding(start = 4.dp))
    }
}

/**
 * 「あなたの活動」。件数タイルを 3 列で並べ、押すとそれぞれの一覧へ。
 *
 * iOS はここに「予想」タイルも置くが、Android にはセトリ予想の画面もサーバ呼び出しも無い。
 * 常に 0 で行き先も無いタイルを出すと「壊れている」と読まれるので、機能が入るまで出さない。
 */
@Composable
private fun ActivitySection(
    state: ProduceUiState,
    onAttendedClick: () -> Unit,
    onFavoritesClick: () -> Unit,
    onContributionsClick: () -> Unit,
    onVotesClick: () -> Unit,
    onCollectedClick: () -> Unit
) {
    val tiles = listOf(
        ActivityTile(Icons.Filled.Mic, state.attendedCount, "参加ライブ", onAttendedClick),
        ActivityTile(Icons.Filled.Star, state.favoriteCount, "お気に入り", onFavoritesClick),
        ActivityTile(Icons.AutoMirrored.Filled.ListAlt, state.contributionCount, "投稿", onContributionsClick),
        ActivityTile(Icons.Filled.HowToVote, state.voteCount, "投票", onVotesClick),
        ActivityTile(Icons.Filled.MusicNote, state.collectedCount, "回収", onCollectedClick)
    )
    Column {
        ImasSectionHeader("あなたの活動", tight = true)
        // LazyVerticalGrid は縦スクロールの中に入れられない (高さが決まらない) ので、
        // 3 個ずつの Row に割って並べる。件数が固定なので行数も決まる。
        tiles.chunked(3).forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                row.forEach { tile ->
                    ImasStatTile(
                        icon = tile.icon,
                        value = tile.value.toString(),
                        label = tile.label,
                        seed = state.pickSeed,
                        tappable = true,
                        onClick = tile.onClick,
                        modifier = Modifier.weight(1f)
                    )
                }
                // 端数の行でタイルが横に伸びないよう、空きぶんの重みを埋める。
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

private data class ActivityTile(
    val icon: ImageVector,
    val value: Int,
    val label: String,
    val onClick: () -> Unit
)

/** 直近に開いたイベント/曲/アイドルへ戻るチップ列。 */
@Composable
private fun RecentsSection(recents: List<RecentChip>, onClick: (RecentChip) -> Unit) {
    if (recents.isEmpty()) return
    Column {
        ImasSectionHeader("最近見た", tight = true)
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(recents, key = { "${it.kind.raw}:${it.entityId}" }) { chip ->
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(DS.surface)
                        .clickable { onClick(chip) }
                        // 長いライブ名で 1 枚が画面いっぱいにならないよう上限だけ決める。
                        .widthIn(max = 200.dp)
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(
                        when (chip.kind) {
                            RecentKind.EVENT -> Icons.Filled.Mic
                            RecentKind.SONG -> Icons.Filled.MusicNote
                            RecentKind.IDOL -> Icons.Filled.Person
                        },
                        contentDescription = null, tint = DS.ink3, modifier = Modifier.size(13.dp)
                    )
                    Text(
                        chip.name, fontSize = 14.sp, color = DS.ink,
                        maxLines = 1, overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

/** 参加したライブを上位数件だけ直接並べる。超えたぶんは「全て見る」で一覧へ。 */
@Composable
private fun AttendedSection(
    events: List<EventWithDateRange>,
    onEventClick: (String) -> Unit,
    onSeeAll: () -> Unit
) {
    if (events.isEmpty()) return
    Column {
        ImasSectionHeader(
            "参加したライブ",
            count = "${events.size}",
            onSeeAll = if (events.size > ATTENDED_INLINE_LIMIT) onSeeAll else null
        )
        events.take(ATTENDED_INLINE_LIMIT).forEach { ew ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth()
                    .clickable { onEventClick(ew.event.id) }
                    .padding(horizontal = 16.dp, vertical = 10.dp)
            ) {
                ImasLeadBar(
                    brandId = ew.event.brandId, height = 38.dp,
                    rainbow = ew.event.jointBrandIdList.isNotEmpty()
                )
                Column(Modifier.weight(1f)) {
                    Text(
                        ew.event.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink,
                        maxLines = 2, overflow = TextOverflow.Ellipsis
                    )
                    ew.dateRange?.let { Text(it, fontSize = 12.sp, color = DS.ink2) }
                }
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = DS.ink3,
                    modifier = Modifier.size(16.dp)
                )
            }
        }
        if (events.size > ATTENDED_INLINE_LIMIT) {
            Text(
                "全て見る (${events.size}件)",
                fontSize = 14.sp, fontWeight = FontWeight.Medium, color = DS.sys,
                modifier = Modifier.clickable(onClick = onSeeAll).padding(horizontal = 16.dp, vertical = 8.dp)
            )
        }
    }
}

@Composable
private fun IdolSection(title: String, idols: List<Idol>, accent: Color, onClick: (String) -> Unit) {
    if (idols.isEmpty()) return
    SectionTitle(title)
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        items(idols) { idol ->
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.clickable { onClick(idol.id) }.size(width = 64.dp, height = 84.dp)
            ) {
                Box(
                    modifier = Modifier.size(48.dp).clip(CircleShape)
                        .background(idol.color?.let { hexToColor(it) } ?: accent)
                )
                Text(
                    idol.name,
                    style = MaterialTheme.typography.labelSmall,
                    color = DS.ink,
                    maxLines = 2,
                    modifier = Modifier.padding(top = 4.dp)
                )
            }
        }
    }
}

@Composable
private fun SongLine(song: Song, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier.size(width = 4.dp, height = 32.dp).clip(CircleShape).background(brandColor(song.brandId))
        )
        Text(
            song.title,
            style = MaterialTheme.typography.bodyMedium,
            color = DS.ink,
            modifier = Modifier.padding(start = 12.dp)
        )
    }
}

@Composable
private fun SectionTitle(title: String) {
    Text(
        title,
        modifier = Modifier.fillMaxWidth().padding(start = 16.dp, top = 16.dp, bottom = 6.dp),
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.Bold,
        color = DS.ink2
    )
}

/**
 * ハブ行。[count] を渡すと右端に件数を出す — 開く前に「中身があるか」が分かると、
 * 空の一覧を開いて戻るだけの往復が減る。件数の概念が無い行 (設定・ゲーム等) は null。
 */
@Composable
private fun HubRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    accent: Color,
    count: Int?,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, tint = accent, modifier = Modifier.size(22.dp))
        Column(modifier = Modifier.weight(1f).padding(start = 14.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = DS.ink)
            if (subtitle.isNotEmpty()) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = DS.ink3)
            }
        }
        if (count != null) {
            Text(
                "$count", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2,
                modifier = Modifier.padding(end = 6.dp)
            )
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = DS.ink3, modifier = Modifier.size(18.dp))
    }
}
