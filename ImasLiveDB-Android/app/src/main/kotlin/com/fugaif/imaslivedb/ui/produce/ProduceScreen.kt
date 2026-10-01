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
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.HowToVote
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.Timeline
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.games.GameKind
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeader
import com.fugaif.imaslivedb.ui.components.ImasStatTile
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.hexToColor
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand

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
    onNavigateToMastery: () -> Unit,
    onNavigateToLedger: () -> Unit,
    onNavigateToTimeline: (String?) -> Unit,
    onNavigateToMyContributions: () -> Unit,
    onNavigateToMyVotes: () -> Unit,
    onNavigateToEditHistory: () -> Unit,
    onNavigateToTagList: () -> Unit,
    onNavigateToTagActivity: () -> Unit,
    onNavigateToGamesHub: () -> Unit,
    onNavigateToIntroDon: () -> Unit,
    onNavigateToSetlistQuizSetup: () -> Unit,
    onResumeQuiz: (GameKind) -> Unit,
    /** 「次のライブ」→ その公演のセトリ画面を予想タブで。 */
    onPredictSetlist: (String) -> Unit,
    viewModel: ProduceViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    // 他タブで見た曲・付けたマークがそのまま数字に効くので、前面に来るたび読み直す。
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { viewModel.refresh() }
    val context = LocalContext.current
    val authState by AppModule.from(context).authService.state.collectAsState()
    val uriHandler = LocalUriHandler.current
    val suspended by AppModule.from(context).quizResumeStore.sessions.collectAsStateWithLifecycle()
    // いちばん最近中断したクイズ (ゲーム一覧の「つづきから」と同じもの)。
    val resume = suspended.values.maxByOrNull { it.savedAt }
    // 発行できた Discord 認可 URL はブラウザへ渡して消す (1 回限りなので開き直さない)。
    LaunchedEffect(state.discordLinkUrl) {
        val url = state.discordLinkUrl ?: return@LaunchedEffect
        viewModel.consumeDiscordLinkUrl()
        runCatching { uriHandler.openUri(url) }
    }

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
            if (state.pickedIdols.isEmpty()) {
                Text(
                    "アイドル詳細の「担当」マークを付けると、ここに並びます",
                    modifier = Modifier.fillMaxWidth().padding(24.dp),
                    color = DS.ink3,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            IdolSection("担当", state.pickedIdols, DS.pick, onNavigateToIdol)

            state.nextLive?.let { next ->
                ImasSectionHeader("次のライブ", tight = true)
                NextLiveCard(next, seed = state.pickSeed, onPredict = { onPredictSetlist(next.show.id) })
            }

            state.featuredPoll?.let { poll ->
                // 投票一覧 (ほかのお題) へはこの見出しから。
                ImasSectionHeader("投票受付中", tight = true, onSeeAll = onNavigateToPolls, seeAllTitle = "ほかのお題")
                FeaturedPollCard(poll = poll, onClick = { onNavigateToPollDetail(poll.id) })
            }

            ShortcutGroup(
                "あそぶ",
                accessory = {
                    resume?.let { s ->
                        val title = gameTitle(s.kind)
                        Row(
                            Modifier.clickable { onResumeQuiz(s.kind) },
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                "つづきから: $title " + "Q.%02d".format(s.currentNumber),
                                fontSize = 13.sp, fontWeight = FontWeight.Medium, color = DS.ink2, maxLines = 1
                            )
                            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = DS.ink2, modifier = Modifier.size(14.dp))
                        }
                    }
                },
                items = listOf(
                    Shortcut(Icons.AutoMirrored.Filled.QueueMusic, "イントロ", onNavigateToIntroDon),
                    Shortcut(Icons.Filled.FormatListNumbered, "セトリ当て", onNavigateToSetlistQuizSetup),
                    Shortcut(Icons.Filled.SportsEsports, "すべて", onNavigateToGamesHub)
                ),
                seed = state.pickSeed
            )
            ShortcutGroup(
                "みんな",
                items = buildList {
                    add(Shortcut(Icons.Filled.History, "動き", onNavigateToEditHistory))
                    add(Shortcut(Icons.Filled.LocalFireDepartment, "タグ", onNavigateToTagActivity))
                    // iOS のコールガイドの位置。Android には歌詞が無いので、ここからしか行けないタグ一覧を置く。
                    add(Shortcut(Icons.Filled.Sell, "タグ一覧", onNavigateToTagList))
                    // 開催中のお題が無いと上の「ほかのお題」が出ないので、そのときだけここに置く。
                    if (state.featuredPoll == null) add(Shortcut(Icons.Filled.HowToVote, "お題", onNavigateToPolls))
                    // 編集の協力者に Discord のロールを渡す入口。セッションで本人を確かめるので
                    // ログイン中だけ出す (未ログインで押しても 401 になるだけ)。
                    if (authState.isSignedIn) {
                        add(Shortcut(Icons.Filled.WorkspacePremium, "Discord", viewModel::requestDiscordLink, state.isLinkingDiscord))
                    }
                },
                seed = state.pickSeed
            )
            ShortcutGroup(
                "しらべる",
                items = listOf(
                    Shortcut(Icons.Filled.BarChart, "統計", onNavigateToStats),
                    // 年表は担当アイドルのブランドから開く (見たい歴史はたいてい担当の歴史)。
                    Shortcut(Icons.Filled.Timeline, "年表", { onNavigateToTimeline(state.pickedIdols.firstOrNull()?.brandId) })
                ),
                seed = state.pickSeed
            )

            ActivitySection(state = state,
                onAttendedClick = onNavigateToAttendedEvents,
                onFavoritesClick = onNavigateToFavorites,
                onContributionsClick = onNavigateToMyContributions,
                onVotesClick = onNavigateToMyVotes,
                onCollectedClick = onNavigateToCollectedSongs,
                onMasteryClick = onNavigateToMastery,
                onLedgerClick = onNavigateToLedger
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
            Spacer(Modifier.height(24.dp))
        }
    }

    state.discordErrorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { viewModel.clearDiscordError() },
            confirmButton = { TextButton(onClick = { viewModel.clearDiscordError() }) { Text("OK") } },
            title = { Text("エラー") },
            text = { Text(message) }
        )
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
                "お題", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White,
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
 * 「あなたの記録」。件数タイルを 3 列で並べ、押すとそれぞれの一覧へ。
 *
 * iOS はここに「予想」タイルも置くが、Android にはまだ「マイ予想」の一覧 (/me/predictions) が無い
 * (セトリ予想そのものは公演のセトリ画面にある)。常に 0 で行き先も無いタイルを出すと
 * 「壊れている」と読まれるので、一覧が入るまで出さない。
 */
@Composable
private fun ActivitySection(
    state: ProduceUiState,
    onAttendedClick: () -> Unit,
    onFavoritesClick: () -> Unit,
    onContributionsClick: () -> Unit,
    onVotesClick: () -> Unit,
    onCollectedClick: () -> Unit,
    onMasteryClick: () -> Unit,
    onLedgerClick: () -> Unit
) {
    val tiles = listOf(
        ActivityTile(Icons.Filled.Mic, "${state.attendedCount}", "参加ライブ", onAttendedClick),
        ActivityTile(Icons.Filled.Star, "${state.favoriteCount}", "お気に入り", onFavoritesClick),
        ActivityTile(Icons.AutoMirrored.Filled.ListAlt, "${state.contributionCount}", "投稿", onContributionsClick),
        ActivityTile(Icons.Filled.HowToVote, "${state.voteCount}", "投票", onVotesClick),
        ActivityTile(Icons.Filled.MusicNote, "${state.collectedCount}", "回収", onCollectedClick),
        ActivityTile(Icons.Filled.BarChart, "${state.masteryCount}", "習熟度", onMasteryClick),
        // 件数ではなく金額を出す — 「いくら使ったか」は件数では読めない。
        ActivityTile(Icons.Filled.AttachMoney, state.ledgerTotalLabel, "収支", onLedgerClick)
    )
    Column {
        ImasSectionHeader("あなたの記録", tight = true)
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
                        value = tile.value,
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
    val value: String,
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
private fun SectionTitle(title: String) {
    Text(
        title,
        modifier = Modifier.fillMaxWidth().padding(start = 16.dp, top = 16.dp, bottom = 6.dp),
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.Bold,
        color = DS.ink2
    )
}

/** 次のライブ。札 + ライブ名 + 公演日 と「セトリを予想」。iOS の「コールを見る」は歌詞が無いので出さない。 */
@Composable
private fun NextLiveCard(next: NextLive, seed: String?, onPredict: () -> Unit) {
    val t = imasThemeForBrand(seed, next.event.brandId)
    val sub = buildList {
        add(next.show.date)
        if (next.show.name.isNotEmpty() && next.show.name != next.event.name) add(next.show.name)
    }.joinToString(" ・ ")
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(DS.surface)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(next.statusLabel, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = t.chipText)
            Text(
                AppPreferences.eventDisplayName(next.event.name), fontSize = 17.sp, fontWeight = FontWeight.Bold,
                color = DS.ink, maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            Text(sub, fontSize = 13.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .background(t.accent)
                .clickable(onClick = onPredict)
                .padding(vertical = 9.dp),
            contentAlignment = Alignment.Center
        ) {
            Text("セトリを予想", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = t.onAccent)
        }
    }
}

/** 入口 1 つ。[loading] の間はアイコンをくるくるに替えて押せなくする。 */
private data class Shortcut(
    val icon: ImageVector,
    val label: String,
    val onClick: () -> Unit,
    val loading: Boolean = false
)

/**
 * 入口のまとまり (あそぶ / みんな / しらべる)。見出し 1 行 + アイコン 4 つずつの並び。
 * 入口を同じ大きさの行で縦に積まず、種類ごとに 1 枚にまとめる。
 */
@Composable
private fun ShortcutGroup(
    title: String,
    items: List<Shortcut>,
    seed: String?,
    accessory: @Composable () -> Unit = {}
) {
    val t = imasThemeForBrand(seed, null)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(DS.surface)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            Spacer(Modifier.weight(1f))
            accessory()
        }
        items.chunked(4).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                row.forEach { item ->
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(10.dp))
                            .clickable(enabled = !item.loading, onClick = item.onClick)
                            .padding(vertical = 4.dp)
                    ) {
                        Box(
                            modifier = Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)).background(t.chipBg),
                            contentAlignment = Alignment.Center
                        ) {
                            if (item.loading) {
                                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp, color = t.chipText)
                            } else {
                                Icon(item.icon, null, tint = t.chipText, modifier = Modifier.size(22.dp))
                            }
                        }
                        Text(item.label, fontSize = 12.sp, color = DS.ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/** つづきからに出すゲーム名 (ゲーム一覧と同じ呼び方)。 */
private fun gameTitle(kind: GameKind): String = when (kind) {
    GameKind.idolQuiz -> "アイドル当て"
    GameKind.songSingerQuiz -> "ソロ曲クイズ"
    GameKind.setlistQuiz -> "セトリ当て"
    GameKind.introDon -> "イントロドン"
    GameKind.colorMatch -> "メンバーカラー合わせ"
}
