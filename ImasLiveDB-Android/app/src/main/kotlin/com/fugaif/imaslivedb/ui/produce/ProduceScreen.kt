package com.fugaif.imaslivedb.ui.produce

import androidx.compose.runtime.remember
import com.fugaif.imaslivedb.ui.navigation.icon
import com.fugaif.imaslivedb.ui.navigation.LocalOpenDestination
import uniffi.imas_core.appNavigationSectionsWithTabs
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.HowToVote
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.Timeline
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.games.GameKind
import com.fugaif.imaslivedb.data.games.QuizSuspended
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCarousel
import com.fugaif.imaslivedb.ui.designsystem.ImasChip
import com.fugaif.imaslivedb.ui.designsystem.ImasChipFlow
import com.fugaif.imaslivedb.ui.designsystem.ImasChipStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasFeatureAction
import com.fugaif.imaslivedb.ui.designsystem.ImasFeatureCard
import com.fugaif.imaslivedb.ui.designsystem.ImasPass
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasShortcutGroup
import com.fugaif.imaslivedb.ui.designsystem.ImasShortcutTile
import com.fugaif.imaslivedb.ui.designsystem.ImasStatGrid
import com.fugaif.imaslivedb.ui.designsystem.ImasStatTile
import com.fugaif.imaslivedb.ui.designsystem.ImasTicket
import com.fugaif.imaslivedb.ui.designsystem.ImasTicketRow
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.DS

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
    /** 自分の P名刺 (担当の入場証の下)。 */
    onNavigateToProducerCard: () -> Unit,
    /** 名刺入れ (記録のタイル)。 */
    onNavigateToCardCase: () -> Unit,
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
    onNavigateToPlaylists: () -> Unit,
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
        ImasPage(modifier = Modifier.padding(padding)) {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                OshiSection(idols = state.pickedIdols, onClick = onNavigateToIdol)
                // 担当の入場証を 1 枚に広げた P名刺へ (会場での名刺交換)。
                ImasTicketRow(
                    title = "P名刺",
                    icon = Icons.Filled.Badge,
                    subtitle = "担当と参加の記録を 1 枚にして、会場で交換する",
                    onClick = onNavigateToProducerCard
                )
            }

            state.nextLive?.let { next ->
                ImasSection("次のライブ", style = ImasSectionHeaderStyle.SMALL) {
                    NextLiveCard(next = next, seed = state.pickSeed, onPredict = { onPredictSetlist(next.show.id) })
                }
            }

            state.featuredPoll?.let { poll ->
                // 投票一覧 (ほかのお題) はこの見出しから。カードの中には iOS と同じ「投票する」行を置く。
                ImasSection(
                    "投票受付中",
                    style = ImasSectionHeaderStyle.SMALL,
                    seeAll = onNavigateToPolls,
                    seeAllTitle = "ほかのお題"
                ) {
                    ImasFeatureCard(
                        title = poll.title,
                        eyebrow = "お題",
                        subtitle = "${poll.totalVotes}票 · ${poll.entryCount}候補 · ${poll.remainingLabel}",
                        // カード全体で詳細へ (前の Android と同じ)。
                        onOpen = { onNavigateToPollDetail(poll.id) },
                        primary = ImasFeatureAction(title = "投票する", icon = Icons.Filled.ThumbUp) {
                            onNavigateToPollDetail(poll.id)
                        }
                    )
                }
            }

            ShortcutsSection(
                pickSeed = state.pickSeed,
                resume = resume,
                onResumeQuiz = onResumeQuiz,
                onNavigateToIntroDon = onNavigateToIntroDon,
                onNavigateToSetlistQuizSetup = onNavigateToSetlistQuizSetup,
                onNavigateToGamesHub = onNavigateToGamesHub,
                onNavigateToEditHistory = onNavigateToEditHistory,
                onNavigateToTagActivity = onNavigateToTagActivity,
                onNavigateToTagList = onNavigateToTagList,
                showsPollsShortcut = state.featuredPoll == null,
                onNavigateToPolls = onNavigateToPolls,
                isSignedIn = authState.isSignedIn,
                isLinkingDiscord = state.isLinkingDiscord,
                onRequestDiscordLink = viewModel::requestDiscordLink,
                onNavigateToStats = onNavigateToStats,
                timelineBrandId = state.pickedIdols.firstOrNull()?.brandId,
                onNavigateToTimeline = onNavigateToTimeline
            )

            ActivitySection(
                state = state,
                onAttendedClick = onNavigateToAttendedEvents,
                onFavoritesClick = onNavigateToFavorites,
                onContributionsClick = onNavigateToMyContributions,
                onVotesClick = onNavigateToMyVotes,
                onCollectedClick = onNavigateToCollectedSongs,
                onMasteryClick = onNavigateToMastery,
                onLedgerClick = onNavigateToLedger,
                onCardCaseClick = onNavigateToCardCase,
                onPlaylistsClick = onNavigateToPlaylists
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
        }
    }

    ImasErrorAlert(
        message = state.discordErrorMessage,
        onDismiss = viewModel::clearDiscordError,
        title = "エラー"
    )
}

/**
 * 担当アイドル (ヒーロー横スクロール。iOS `oshiSection`)。
 * 無ければ、ブランド/アイドルに紐づかない一般の空状態として [ImasCard] に包む (iOS と同じ)。
 */
@Composable
private fun OshiSection(idols: List<Idol>, onClick: (String) -> Unit) {
    if (idols.isEmpty()) {
        ImasCard {
            ImasEmptyState(
                icon = Icons.Filled.Favorite,
                title = "担当アイドルがいません",
                message = "アイドル詳細の「担当」マークを付けると、ここに並びます"
            )
        }
        return
    }
    ImasSection("担当", style = ImasSectionHeaderStyle.SMALL) {
        ImasCarousel(items = idols, key = { it.id }) { idol ->
            ImasPass(
                leftImprint = "PRODUCER PASS",
                rightImprint = "担当",
                title = idol.name,
                // ブランド名はこの画面の状態にブランド辞書が無く組めない (CV だけ)。
                subtitle = idol.currentVoiceActor?.let { "CV $it" },
                seed = idol.color,
                brand = idol.brandId,
                onOpen = { onClick(idol.id) },
                media = {
                    // アイコンは写真か判子で必ず出す (担当なので二重の輪)。
                    ImasAvatar(
                        label = idol.shortName,
                        seed = idol.color,
                        brand = idol.brandId,
                        size = 60.dp,
                        isPick = true,
                        entityId = idol.id
                    )
                }
            )
        }
    }
}

/** 次のライブ。チケット + 「セトリを予想」(iOS の「コールを見る」は歌詞が無いので出さない)。 */
@Composable
private fun NextLiveCard(next: NextLive, seed: String?, onPredict: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        ImasTicket(
            // `statusLabel` は「参加予定・あと2日」/「お気に入り」まで ViewModel 側で組んである
            // (日数だけを分けて `ImasTicketCountdown` に渡す形をこの状態は持っていない)。
            label = next.statusLabel,
            imprint = null,
            title = AppPreferences.eventDisplayName(next.event.name),
            metaImprint = next.show.date.take(10),
            meta = next.show.name.takeIf { it.isNotEmpty() && it != next.event.name },
            seed = seed,
            brand = next.event.brandId,
            onOpen = onPredict
        )
        ImasButton(
            title = "セトリを予想",
            onClick = onPredict,
            role = ImasButtonRole.PRIMARY,
            size = ImasButtonSize.MEDIUM,
            fillsWidth = true
        )
    }
}

/**
 * 入口 (あそぶ / みんな / しらべる。iOS `shortcutSection`)。
 * 「つづきから」は見出し添え物ではなく iOS と同じ先頭の行にする (アイコン付きの行なら
 * 文言を削らずに済む)。
 */
@Composable
private fun ShortcutsSection(
    pickSeed: String?,
    resume: QuizSuspended?,
    onResumeQuiz: (GameKind) -> Unit,
    onNavigateToIntroDon: () -> Unit,
    onNavigateToSetlistQuizSetup: () -> Unit,
    onNavigateToGamesHub: () -> Unit,
    onNavigateToEditHistory: () -> Unit,
    onNavigateToTagActivity: () -> Unit,
    onNavigateToTagList: () -> Unit,
    showsPollsShortcut: Boolean,
    onNavigateToPolls: () -> Unit,
    isSignedIn: Boolean,
    isLinkingDiscord: Boolean,
    onRequestDiscordLink: () -> Unit,
    onNavigateToStats: () -> Unit,
    timelineBrandId: String?,
    onNavigateToTimeline: (String?) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.section)) {
        // タブバーから外した主な画面 (並べ方はコア)。
        val tabKeys = AppPreferences.tabBarKeys
        val others = remember(tabKeys) {
            appNavigationSectionsWithTabs(lyricsAvailable = false, assistantAvailable = false, tabKeys = tabKeys)
                .firstOrNull { it.title == "そのほか" }?.items.orEmpty()
        }
        if (others.isNotEmpty()) {
            val open = LocalOpenDestination.current
            ImasShortcutGroup("そのほか") {
                others.forEach { item ->
                    ImasShortcutTile(icon = item.destination.icon, label = item.label, onClick = { open(item.destination) })
                }
            }
        }
        ImasShortcutGroup("あそぶ") {
            if (resume != null) {
                ImasShortcutTile(
                    icon = Icons.Filled.PlayArrow,
                    label = "つづきから",
                    detail = "${gameTitle(resume.kind)} " + "Q.%02d".format(resume.currentNumber),
                    seed = pickSeed,
                    onClick = { onResumeQuiz(resume.kind) }
                )
            }
            ImasShortcutTile(Icons.AutoMirrored.Filled.QueueMusic, "イントロ", seed = pickSeed, onClick = onNavigateToIntroDon)
            ImasShortcutTile(Icons.Filled.FormatListNumbered, "セトリ当て", seed = pickSeed, onClick = onNavigateToSetlistQuizSetup)
            ImasShortcutTile(Icons.Filled.SportsEsports, "すべて", seed = pickSeed, onClick = onNavigateToGamesHub)
        }
        ImasShortcutGroup("みんな") {
            ImasShortcutTile(Icons.Filled.History, "動き", seed = pickSeed, onClick = onNavigateToEditHistory)
            ImasShortcutTile(Icons.Filled.LocalFireDepartment, "タグ", seed = pickSeed, onClick = onNavigateToTagActivity)
            // iOS のコールガイドの位置。Android には歌詞が無いので、ここからしか行けないタグ一覧を置く。
            ImasShortcutTile(Icons.Filled.Sell, "タグ一覧", seed = pickSeed, onClick = onNavigateToTagList)
            // 開催中のお題が無いと上の「ほかのお題」が出ないので、そのときだけここに置く。
            if (showsPollsShortcut) {
                ImasShortcutTile(Icons.Filled.HowToVote, "お題", seed = pickSeed, onClick = onNavigateToPolls)
            }
            // 編集の協力者に Discord のロールを渡す入口。セッションで本人を確かめるので
            // ログイン中だけ出す (未ログインで押しても 401 になるだけ)。
            if (isSignedIn) {
                ImasShortcutTile(
                    Icons.Filled.WorkspacePremium, "Discord",
                    seed = pickSeed, isLoading = isLinkingDiscord, onClick = onRequestDiscordLink
                )
            }
        }
        ImasShortcutGroup("しらべる") {
            ImasShortcutTile(Icons.Filled.BarChart, "統計", seed = pickSeed, onClick = onNavigateToStats)
            // 年表は担当アイドルのブランドから開く (見たい歴史はたいてい担当の歴史)。
            ImasShortcutTile(Icons.Filled.Timeline, "年表", seed = pickSeed, onClick = { onNavigateToTimeline(timelineBrandId) })
        }
    }
}

/**
 * 「あなたの記録」。件数タイルを格子で並べ、押すとそれぞれの一覧へ。
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
    onLedgerClick: () -> Unit,
    onCardCaseClick: () -> Unit,
    onPlaylistsClick: () -> Unit
) {
    val tiles = listOf(
        ActivityTile(Icons.Filled.Mic, "${state.attendedCount}", "参加ライブ", onAttendedClick),
        ActivityTile(Icons.Filled.Star, "${state.favoriteCount}", "お気に入り", onFavoritesClick),
        ActivityTile(Icons.AutoMirrored.Filled.ListAlt, "${state.contributionCount}", "投稿", onContributionsClick),
        ActivityTile(Icons.Filled.HowToVote, "${state.voteCount}", "投票", onVotesClick),
        ActivityTile(Icons.Filled.MusicNote, "${state.collectedCount}", "回収", onCollectedClick),
        ActivityTile(Icons.Filled.BarChart, "${state.masteryCount}", "習熟度", onMasteryClick),
        // 件数ではなく金額を出す — 「いくら使ったか」は件数では読めない。
        ActivityTile(Icons.Filled.AttachMoney, state.ledgerTotalLabel, "収支", onLedgerClick),
        ActivityTile(Icons.Filled.Inbox, "${state.cardCaseCount}", "名刺入れ", onCardCaseClick)
    )
    ImasSection("あなたの記録", style = ImasSectionHeaderStyle.SMALL) {
        ImasStatGrid(columns = 4) {
            tiles.forEach { tile ->
                ImasStatTile(
                    icon = tile.icon,
                    value = tile.value,
                    label = tile.label,
                    seed = state.pickSeed,
                    tappable = true,
                    onClick = tile.onClick
                )
            }
        }
        ImasNavRow(
            title = "プレイリスト",
            subtitle = "曲を並べて Apple Music で続けて聴く",
            icon = Icons.Filled.MusicNote,
            seed = state.pickSeed,
            onClick = onPlaylistsClick
        )
    }
}

private data class ActivityTile(
    val icon: ImageVector,
    val value: String,
    val label: String,
    val onClick: () -> Unit
)

/** 直近に開いたイベント/曲/アイドルへ戻るチップ列 (iOS と同じ折り返しの並び)。 */
@Composable
private fun RecentsSection(recents: List<RecentChip>, onClick: (RecentChip) -> Unit) {
    if (recents.isEmpty()) return
    ImasSection("最近見た", style = ImasSectionHeaderStyle.SMALL) {
        ImasChipFlow {
            recents.forEach { chip ->
                ImasChip(
                    text = chip.name,
                    icon = when (chip.kind) {
                        RecentKind.EVENT -> Icons.Filled.Mic
                        RecentKind.SONG -> Icons.Filled.MusicNote
                        RecentKind.IDOL -> Icons.Filled.Person
                    },
                    style = ImasChipStyle.OUTLINED,
                    onClick = { onClick(chip) }
                )
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
