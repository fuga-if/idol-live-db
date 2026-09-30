package com.fugaif.imaslivedb.ui.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import uniffi.imas_core.AppDestination
import uniffi.imas_core.appNavigationSections
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavType
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.fugaif.imaslivedb.ui.components.NowPlayingBar
import com.fugaif.imaslivedb.ui.edit.RecentEditsScreen
import com.fugaif.imaslivedb.ui.events.CostumeShowsScreen
import com.fugaif.imaslivedb.ui.events.EventDetailScreen
import com.fugaif.imaslivedb.ui.events.EventListScreen
import com.fugaif.imaslivedb.ui.events.SetlistScreen
import com.fugaif.imaslivedb.data.games.GameKind
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.games.ColorMatchGameScreen
import com.fugaif.imaslivedb.ui.games.GamesHubScreen
import com.fugaif.imaslivedb.ui.games.IdolQuizScreen
import com.fugaif.imaslivedb.ui.games.IdolQuizSetupScreen
import com.fugaif.imaslivedb.ui.games.SetlistQuizScreen
import com.fugaif.imaslivedb.ui.games.SetlistQuizSetupScreen
import com.fugaif.imaslivedb.ui.games.SongSingerQuizScreen
import com.fugaif.imaslivedb.ui.games.SongSingerQuizSetupScreen
import com.fugaif.imaslivedb.data.games.SortMakerSubject
import com.fugaif.imaslivedb.ui.sortmaker.SortMakerPlayScreen
import com.fugaif.imaslivedb.ui.sortmaker.SortMakerSetupScreen
import com.fugaif.imaslivedb.ui.sortmaker.TierListScreen
import com.fugaif.imaslivedb.data.games.SortMakerPurpose
import com.fugaif.imaslivedb.ui.idols.IdolDetailScreen
import com.fugaif.imaslivedb.ui.idols.IdolListScreen
import com.fugaif.imaslivedb.ui.idols.IdolSongHistoryScreen
import com.fugaif.imaslivedb.ui.idols.IdolsByBirthMonthScreen
import com.fugaif.imaslivedb.ui.filtered.FilteredEventsScreen
import com.fugaif.imaslivedb.ui.filtered.FilteredIdolsScreen
import com.fugaif.imaslivedb.ui.filtered.FilteredShowsScreen
import com.fugaif.imaslivedb.ui.filtered.FilteredSongsScreen
import com.fugaif.imaslivedb.ui.introdon.IntroDonHomeScreen
import com.fugaif.imaslivedb.ui.introdon.IntroDonGameScreen
import com.fugaif.imaslivedb.ui.introdon.IntroDonMode
import com.fugaif.imaslivedb.ui.introdon.IntroDonPartyScreen
import com.fugaif.imaslivedb.ui.introdon.IntroDonSettings
import com.fugaif.imaslivedb.ui.introdon.IntroDonSetupScreen
import com.fugaif.imaslivedb.ui.introdon.decodeIntroDonBrandIds
import com.fugaif.imaslivedb.ui.introdon.encodeIntroDonBrandIds
import com.fugaif.imaslivedb.ui.mypage.AttendedEventsScreen
import com.fugaif.imaslivedb.ui.mypage.FavoritesScreen
import com.fugaif.imaslivedb.ui.mypage.MyContributionsScreen
import com.fugaif.imaslivedb.ui.polls.MyVotesScreen
import com.fugaif.imaslivedb.ui.polls.PollDetailScreen
import com.fugaif.imaslivedb.ui.polls.PollHallOfFameScreen
import com.fugaif.imaslivedb.ui.polls.PollsScreen
import com.fugaif.imaslivedb.ui.ledger.LedgerScreen
import com.fugaif.imaslivedb.ui.mastery.MasteryScreen
import com.fugaif.imaslivedb.ui.produce.CollectedSongsScreen
import com.fugaif.imaslivedb.ui.produce.ProduceScreen
import com.fugaif.imaslivedb.ui.produce.RecentsStore
import com.fugaif.imaslivedb.ui.timeline.BrandTimelineScreen
import com.fugaif.imaslivedb.ui.schedule.CalendarScreen
import com.fugaif.imaslivedb.data.repository.SearchScope
import com.fugaif.imaslivedb.ui.settings.SettingsScreen
import com.fugaif.imaslivedb.ui.songs.SongDetailScreen
import com.fugaif.imaslivedb.ui.songs.SongListScreen
import com.fugaif.imaslivedb.ui.stats.StatsScreen
import com.fugaif.imaslivedb.ui.tags.IdolTagDetailScreen
import com.fugaif.imaslivedb.ui.tags.TagActivityScreen
import com.fugaif.imaslivedb.ui.tags.TagDetailScreen
import com.fugaif.imaslivedb.ui.tags.TagListScreen
import com.fugaif.imaslivedb.ui.tags.UnitTagDetailScreen
import com.fugaif.imaslivedb.ui.units.UnitDetailScreen
import com.fugaif.imaslivedb.ui.search.CrossTabSearch

/**
 * 回収した楽曲一覧のルート。件数が端末ローカルのマークから毎回導出されるので、
 * 条件を経路に載せる [NavRoutes.FilteredSongs] には相乗りできない。
 */
private const val ROUTE_COLLECTED_SONGS = "collected_songs"

/** 年表を「ブランド指定なし」で開くための番人役の値 ([NavRoutes.BrandTimeline] の引数は必須)。 */
private const val ALL_BRANDS = "all"

/** 年表をサイドバーから開くときの根。ブランド未指定 = 先頭ブランド (ルート引数の要らない入口)。 */
private const val ROUTE_TIMELINE_ROOT = "brand_timeline_root"

/** 広い画面とみなす幅。iOS の regular size class (iPad 全幅・Mac) に当たる。 */
private const val WIDE_SCREEN_MIN_DP = 600

@Composable
fun AppNavigation() {
    var current by rememberSaveable { mutableStateOf(AppDestination.SCHEDULE) }
    // 行き先の一覧 (並び・見出し・タブバーに載るか) はコアが決める。
    // Android には歌詞 (コールガイド) が無いので lyricsAvailable = false。
    val sections = remember { appNavigationSections(lyricsAvailable = false) }
    val tabItems = remember(sections) { sections.flatMap { it.items }.filter { it.inTabBar } }
    val wide = LocalConfiguration.current.screenWidthDp >= WIDE_SCREEN_MIN_DP
    // 狭くなったら (画面分割など) サイドバーだけの行き先から、同じ画面の入口がある
    // プロデュースへ戻す。iOS の AdaptiveRootTabs と同じ規則。
    LaunchedEffect(wide) {
        if (!wide && tabItems.none { it.destination == current }) current = AppDestination.PRODUCE
    }
    // 「他のタブに N 件」を押されたら、そのタブへ移る。語の受け渡しは移った先の
    // 一覧が `CrossTabSearch.take()` で拾う。generation を鍵にするのは、同じタブへ
    // 続けて渡したときも気づけるようにするため。
    LaunchedEffect(CrossTabSearch.generation) {
        CrossTabSearch.target?.let { current = it.destination }
    }

    // One NavController per destination to maintain independent back stacks
    val navControllers = AppDestination.entries.associateWith { rememberNavController() }

    Row {
        if (wide) {
            AppSidebar(sections = sections, current = current, onSelect = { current = it })
        }
        Scaffold(
            bottomBar = {
                // 再生中バーはナビゲーションバーの真上。鳴っている間だけ出る。
                // タップした曲は「楽曲」タブの詳細で開く (どのタブから鳴らしても行き先は同じ)。
                Column {
                    NowPlayingBar(onSongClick = { songId ->
                        current = AppDestination.SONGS
                        navControllers.getValue(AppDestination.SONGS)
                            .navigate(NavRoutes.SongDetail.createRoute(songId))
                    })
                    if (!wide && !BottomBarVisibility.isHidden) {
                        BottomNavBar(items = tabItems, current = current, onSelect = { current = it })
                    }
                }
            }
        ) { innerPadding ->
            Box(modifier = Modifier.padding(innerPadding)) {
                // 行き先ごとに NavHost を持つので戻る履歴は独立。表示中の 1 つだけ組む。
                DestinationNavHost(current, navControllers.getValue(current))
            }
        }
    }
}

/** 戻る先があるときだけ「戻る」を返す。サイドバーの根として開いた画面には矢印を出さない。 */
private fun NavHostController.backOrNull(): (() -> Unit)? =
    if (previousBackStackEntry != null) ({ popBackStack() }) else null

@Composable
private fun DestinationNavHost(destination: AppDestination, navController: NavHostController) {
    when (destination) {
        AppDestination.SCHEDULE -> TabNavHost(navController, NavRoutes.Schedule.route) { scheduleNavGraph(navController) }
        AppDestination.EVENTS -> TabNavHost(navController, NavRoutes.EventList.route) { eventsNavGraph(navController) }
        AppDestination.SONGS -> TabNavHost(navController, NavRoutes.SongList.route) { songsNavGraph(navController) }
        AppDestination.IDOLS -> TabNavHost(navController, NavRoutes.IdolList.route) { idolsNavGraph(navController) }
        AppDestination.PRODUCE -> TabNavHost(navController, NavRoutes.Produce.route) { produceNavGraph(navController) }
        // サイドバーだけの行き先。中身はプロデュースから push するのと同じ画面 (同じグラフ) を根から開く。
        AppDestination.STATS -> TabNavHost(navController, NavRoutes.Stats.route) { produceNavGraph(navController) }
        AppDestination.TIMELINE -> TabNavHost(navController, ROUTE_TIMELINE_ROOT) { produceNavGraph(navController) }
        AppDestination.POLLS -> TabNavHost(navController, NavRoutes.Polls.route) { produceNavGraph(navController) }
        AppDestination.COMMUNITY_ACTIVITY -> TabNavHost(navController, NavRoutes.EditHistory.route) { produceNavGraph(navController) }
        AppDestination.TAG_ACTIVITY -> TabNavHost(navController, NavRoutes.TagActivity.route) { produceNavGraph(navController) }
        AppDestination.GAMES -> TabNavHost(navController, NavRoutes.GamesHub.route) { produceNavGraph(navController) }
        // Android には歌詞が無いのでコアがこの行き先を返さない。
        AppDestination.CALL_GUIDE -> Unit
    }
}

@Composable
private fun TabNavHost(
    navController: NavHostController,
    startDestination: String,
    graphBuilder: NavGraphBuilder.() -> Unit
) {
    // 「最近見た」の記録はここ 1 箇所に置く。詳細画面はどのタブからも積めるので、
    // 遷移のコールバック側 (20 箇所以上) に記録を撒くと必ずどこかで漏れる。
    // どのルートが記録対象かは RecentsStore が決める (画面側は行き先を渡すだけ)。
    val context = LocalContext.current
    LaunchedEffect(navController) {
        navController.currentBackStackEntryFlow.collect { entry ->
            RecentsStore.recordRoute(context, entry.destination.route) { entry.arguments?.getString(it) }
        }
    }
    NavHost(
        navController = navController,
        startDestination = startDestination,
        modifier = Modifier.fillMaxSize(),
        builder = graphBuilder
    )
}

// --- Per-tab nav graphs ---

internal fun NavGraphBuilder.eventsNavGraph(navController: NavHostController) {
    composable(NavRoutes.EventList.route) {
        EventListScreen(
            onEventClick = { eventId ->
                navController.navigate(NavRoutes.EventDetail.createRoute(eventId))
            },
        )
    }
    detailRoutes(navController)
}

internal fun NavGraphBuilder.songsNavGraph(navController: NavHostController) {
    composable(NavRoutes.SongList.route) {
        SongListScreen(
            onSongClick = { songId ->
                navController.navigate(NavRoutes.SongDetail.createRoute(songId))
            },
        )
    }
    detailRoutes(navController)
}

internal fun NavGraphBuilder.idolsNavGraph(navController: NavHostController) {
    composable(NavRoutes.IdolList.route) {
        IdolListScreen(
            onNavigateToIdolDetail = { idolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(idolId))
            },
            onNavigateToUnitDetail = { unitId ->
                navController.navigate(NavRoutes.UnitDetail.createRoute(unitId))
            },
        )
    }
    detailRoutes(navController)
}

internal fun NavGraphBuilder.scheduleNavGraph(navController: NavHostController) {
    composable(NavRoutes.Schedule.route) {
        CalendarScreen(
            onNavigateToShow = { navController.navigate(NavRoutes.Setlist.createRoute(it)) },
            onNavigateToSong = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onNavigateToIdol = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onNavigateToEvent = { navController.navigate(NavRoutes.EventDetail.createRoute(it)) },
            onNavigateToSettings = { navController.navigate(NavRoutes.Settings.route) }
        )
    }
    composable(NavRoutes.Settings.route) { SettingsScreen() }
    detailRoutes(navController)
}

internal fun NavGraphBuilder.produceNavGraph(navController: NavHostController) {
    composable(NavRoutes.Produce.route) {
        ProduceScreen(
            onNavigateToStats = { navController.navigate(NavRoutes.Stats.route) },
            onNavigateToSettings = { navController.navigate(NavRoutes.Settings.route) },
            onNavigateToPolls = { navController.navigate(NavRoutes.Polls.route) },
            onNavigateToPollDetail = { navController.navigate(NavRoutes.PollDetail.createRoute(it)) },
            onNavigateToIdol = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onNavigateToSong = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onNavigateToEvent = { navController.navigate(NavRoutes.EventDetail.createRoute(it)) },
            onNavigateToFavorites = { navController.navigate(NavRoutes.Favorites.route) },
            onNavigateToAttendedEvents = { navController.navigate(NavRoutes.AttendedEvents.route) },
            onNavigateToCollectedSongs = { navController.navigate(ROUTE_COLLECTED_SONGS) },
            onNavigateToMastery = { navController.navigate(NavRoutes.Mastery.route) },
            onNavigateToLedger = { navController.navigate(NavRoutes.Ledger.route) },
            // ブランド未指定は "all"。年表側が先頭ブランドを選ぶ (ルート引数は必須なので番人役の値)。
            onNavigateToTimeline = {
                navController.navigate(NavRoutes.BrandTimeline.createRoute(it ?: ALL_BRANDS))
            },
            onNavigateToMyContributions = { navController.navigate(NavRoutes.MyContributions.route) },
            onNavigateToMyVotes = { navController.navigate(NavRoutes.MyVotes.route) },
            onNavigateToEditHistory = { navController.navigate(NavRoutes.EditHistory.route) },
            onNavigateToTagList = { navController.navigate(NavRoutes.TagList.route) },
            onNavigateToTagActivity = { navController.navigate(NavRoutes.TagActivity.route) },
            onNavigateToGamesHub = { navController.navigate(NavRoutes.GamesHub.route) },
            onNavigateToIntroDon = { navController.navigate(NavRoutes.IntroDonHome.route) },
            onNavigateToSetlistQuizSetup = { navController.navigate(NavRoutes.GamesSetlistQuizSetup.route) },
            onResumeQuiz = { navController.navigate(NavRoutes.GamesResume.createRoute(it)) },
            onPredictSetlist = { navController.navigate(NavRoutes.Setlist.createRoute(it, predict = true)) }
        )
    }
    composable(ROUTE_COLLECTED_SONGS) {
        CollectedSongsScreen(
            onBack = { navController.popBackStack() },
            onSongClick = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) }
        )
    }
    composable(ROUTE_TIMELINE_ROOT) {
        BrandTimelineScreen(
            initialBrandId = null,
            onBack = navController.backOrNull(),
            onEventClick = { navController.navigate(NavRoutes.EventDetail.createRoute(it)) },
            onFilteredSongsClick = { kind, value ->
                navController.navigate(NavRoutes.FilteredSongs.createRoute(kind, value))
            }
        )
    }
    composable(NavRoutes.BrandTimeline.ROUTE) { backStackEntry ->
        val raw = backStackEntry.arguments?.getString("brandId")
        BrandTimelineScreen(
            initialBrandId = raw?.takeIf { it != ALL_BRANDS },
            onBack = { navController.popBackStack() },
            onEventClick = { navController.navigate(NavRoutes.EventDetail.createRoute(it)) },
            onFilteredSongsClick = { kind, value ->
                navController.navigate(NavRoutes.FilteredSongs.createRoute(kind, value))
            }
        )
    }
    composable(NavRoutes.Mastery.route) {
        MasteryScreen(onOpenSong = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) })
    }
    composable(NavRoutes.Ledger.route) { LedgerScreen() }
    composable(NavRoutes.Stats.route) { StatsScreen() }
    composable(NavRoutes.Settings.route) { SettingsScreen() }
    composable(NavRoutes.Polls.route) {
        PollsScreen(
            onBack = navController.backOrNull(),
            onPollClick = { navController.navigate(NavRoutes.PollDetail.createRoute(it)) },
            onHallOfFameClick = { navController.navigate(NavRoutes.PollHallOfFame.route) }
        )
    }
    composable(NavRoutes.PollHallOfFame.route) {
        PollHallOfFameScreen(
            onBack = { navController.popBackStack() },
            onSongClick = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onIdolClick = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onUnitClick = { navController.navigate(NavRoutes.UnitDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.Favorites.route) {
        FavoritesScreen(
            onBack = { navController.popBackStack() },
            onNavigateToSong = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onNavigateToIdol = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.AttendedEvents.route) {
        AttendedEventsScreen(
            onBack = { navController.popBackStack() },
            onEventClick = { navController.navigate(NavRoutes.EventDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.MyContributions.route) {
        MyContributionsScreen(onBack = { navController.popBackStack() })
    }
    composable(NavRoutes.MyVotes.route) {
        MyVotesScreen(onBack = { navController.popBackStack() })
    }
    composable(NavRoutes.EditHistory.route) {
        RecentEditsScreen(onBack = navController.backOrNull())
    }
    composable(NavRoutes.TagList.route) {
        TagListScreen(
            onBack = { navController.popBackStack() },
            onTagClick = { navController.navigate(NavRoutes.TagDetail.createRoute(it)) },
            onSongClick = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.TagDetail.ROUTE) { backStackEntry ->
        val tagId = backStackEntry.arguments?.getString("tagId") ?: return@composable
        TagDetailScreen(
            tagId = tagId,
            onBack = { navController.popBackStack() },
            onSongClick = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.TagActivity.route) {
        TagActivityScreen(
            onBack = navController.backOrNull(),
            onSongTagClick = { navController.navigate(NavRoutes.TagDetail.createRoute(it)) },
            onIdolTagClick = { navController.navigate(NavRoutes.IdolTagDetail.createRoute(it)) },
            onSongClick = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onIdolClick = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.GamesHub.route) {
        GamesHubScreen(
            onBack = navController.backOrNull(),
            onNavigateToIntroDon = { navController.navigate(NavRoutes.IntroDonHome.route) },
            onNavigateToColorMatch = { navController.navigate(NavRoutes.GamesColorMatch.route) },
            onNavigateToIdolQuizSetup = { navController.navigate(NavRoutes.GamesIdolQuizSetup.route) },
            onNavigateToSongQuizSetup = { navController.navigate(NavRoutes.GamesSongQuizSetup.route) },
            onNavigateToSetlistQuizSetup = { navController.navigate(NavRoutes.GamesSetlistQuizSetup.route) },
            onNavigateToSortMakerSetup = { navController.navigate(NavRoutes.GamesSortMakerSetup.createRoute(it.key)) },
            onNavigateToTierListSetup = { navController.navigate(NavRoutes.GamesTierListSetup.createRoute(it.key)) },
            onResume = { navController.navigate(NavRoutes.GamesResume.createRoute(it)) }
        )
    }
    composable(NavRoutes.GamesResume.ROUTE) { backStackEntry ->
        // 途中経過は開いた時点のものを 1 回だけ読む (遊ぶと上書きされるので、読み直さない)。
        val context = LocalContext.current
        val kindName = backStackEntry.arguments?.getString("kind")
        val suspended = remember(kindName) {
            GameKind.entries.firstOrNull { it.name == kindName }
                ?.let { AppModule.from(context).quizResumeStore.suspended(it) }
        }
        val onBack: () -> Unit = { navController.popBackStack() }
        when (suspended?.kind) {
            GameKind.idolQuiz -> IdolQuizScreen(selectedBrandIds = suspended.brandIds.toSet(), onBack = onBack, resume = suspended)
            GameKind.songSingerQuiz -> SongSingerQuizScreen(selectedBrandIds = suspended.brandIds.toSet(), onBack = onBack, resume = suspended)
            GameKind.setlistQuiz -> SetlistQuizScreen(selectedBrandIds = suspended.brandIds.toSet(), onBack = onBack, resume = suspended)
            GameKind.colorMatch -> ColorMatchGameScreen(onBack = onBack, resume = suspended)
            // 消えていた (別の画面で遊び終えた等) ときは一覧へ戻す。
            else -> LaunchedEffect(Unit) { navController.popBackStack() }
        }
    }
    composable(NavRoutes.IntroDonHome.route) {
        IntroDonHomeScreen(
            onBack = { navController.popBackStack() },
            onNavigateToSetup = { navController.navigate(NavRoutes.IntroDonSetup.route) }
        )
    }
    composable(NavRoutes.IntroDonSetup.route) {
        IntroDonSetupScreen(
            onBack = { navController.popBackStack() },
            onStartGame = { settings ->
                navController.navigate(
                    NavRoutes.IntroDonGame.createRoute(
                        mode = settings.mode.name,
                        brandIds = encodeIntroDonBrandIds(settings.selectedBrandIds),
                        questionCount = settings.questionCount,
                        introDurationMs = settings.introDurationMs,
                        rushTimeLimitSec = settings.rushTimeLimitSec
                    )
                )
            },
            onStartParty = { settings ->
                navController.navigate(
                    NavRoutes.IntroDonParty.createRoute(
                        brandIds = encodeIntroDonBrandIds(settings.selectedBrandIds),
                        questionCount = settings.questionCount,
                        introDurationMs = settings.introDurationMs
                    )
                )
            }
        )
    }
    composable(NavRoutes.IntroDonGame.ROUTE) { backStackEntry ->
        val args = backStackEntry.arguments
        val settings = IntroDonSettings(
            mode = IntroDonMode.valueOf(args?.getString("mode") ?: IntroDonMode.NORMAL.name),
            questionCount = args?.getString("questionCount")?.toIntOrNull() ?: 10,
            introDurationMs = args?.getString("introDurationMs")?.toLongOrNull() ?: 5_000L,
            rushTimeLimitSec = args?.getString("rushTimeLimitSec")?.toIntOrNull() ?: 60,
            selectedBrandIds = decodeIntroDonBrandIds(args?.getString("brandIds"))
        )
        IntroDonGameScreen(settings = settings, onExit = { navController.popBackStack(NavRoutes.IntroDonHome.route, false) })
    }
    composable(NavRoutes.IntroDonParty.ROUTE) { backStackEntry ->
        val args = backStackEntry.arguments
        val settings = IntroDonSettings(
            mode = IntroDonMode.PARTY,
            questionCount = args?.getString("questionCount")?.toIntOrNull() ?: 10,
            introDurationMs = args?.getString("introDurationMs")?.toLongOrNull() ?: 5_000L,
            selectedBrandIds = decodeIntroDonBrandIds(args?.getString("brandIds"))
        )
        IntroDonPartyScreen(settings = settings, onExit = { navController.popBackStack(NavRoutes.IntroDonHome.route, false) })
    }
    composable(NavRoutes.GamesColorMatch.route) {
        ColorMatchGameScreen(onBack = { navController.popBackStack() })
    }
    composable(NavRoutes.GamesIdolQuizSetup.route) {
        IdolQuizSetupScreen(
            onBack = { navController.popBackStack() },
            onStart = { brandIds -> navController.navigate(NavRoutes.GamesIdolQuiz.createRoute(brandIds)) }
        )
    }
    composable(NavRoutes.GamesIdolQuiz.ROUTE) { backStackEntry ->
        val brandIds = decodeGameBrandIds(backStackEntry.arguments?.getString("brandIds"))
        IdolQuizScreen(selectedBrandIds = brandIds, onBack = { navController.popBackStack() })
    }
    composable(NavRoutes.GamesSongQuizSetup.route) {
        SongSingerQuizSetupScreen(
            onBack = { navController.popBackStack() },
            onStart = { brandIds -> navController.navigate(NavRoutes.GamesSongQuiz.createRoute(brandIds)) }
        )
    }
    composable(NavRoutes.GamesSongQuiz.ROUTE) { backStackEntry ->
        val brandIds = decodeGameBrandIds(backStackEntry.arguments?.getString("brandIds"))
        SongSingerQuizScreen(selectedBrandIds = brandIds, onBack = { navController.popBackStack() })
    }
    composable(NavRoutes.GamesSetlistQuizSetup.route) {
        SetlistQuizSetupScreen(
            onBack = { navController.popBackStack() },
            onStart = { brandIds -> navController.navigate(NavRoutes.GamesSetlistQuiz.createRoute(brandIds)) }
        )
    }
    composable(NavRoutes.GamesSetlistQuiz.ROUTE) { backStackEntry ->
        val brandIds = decodeGameBrandIds(backStackEntry.arguments?.getString("brandIds"))
        SetlistQuizScreen(selectedBrandIds = brandIds, onBack = { navController.popBackStack() })
    }
    composable(NavRoutes.GamesSortMakerSetup.ROUTE) { backStackEntry ->
        val subject = SortMakerSubject.fromKey(backStackEntry.arguments?.getString("subject")) ?: SortMakerSubject.SONG
        SortMakerSetupScreen(
            subject = subject,
            purpose = SortMakerPurpose.SORT,
            onBack = { navController.popBackStack() },
            onPlay = { navController.navigate(NavRoutes.GamesSortMakerPlay.createRoute(subject.key)) }
        )
    }
    composable(NavRoutes.GamesSortMakerPlay.ROUTE) { backStackEntry ->
        val subject = SortMakerSubject.fromKey(backStackEntry.arguments?.getString("subject")) ?: SortMakerSubject.SONG
        val context = LocalContext.current
        val session = remember(subject) { AppModule.from(context).sortMakerStore.session(subject) }
        if (session == null) {
            LaunchedEffect(Unit) { navController.popBackStack() }
        } else {
            SortMakerPlayScreen(
                session = session,
                onBack = { navController.popBackStack() },
                onItemClick = { item ->
                    when (item) {
                        is com.fugaif.imaslivedb.ui.sortmaker.SortMakerItem.SongItem ->
                            navController.navigate(NavRoutes.SongDetail.createRoute(item.song.id))
                        is com.fugaif.imaslivedb.ui.sortmaker.SortMakerItem.IdolItem ->
                            navController.navigate(NavRoutes.IdolDetail.createRoute(item.idol.id))
                    }
                },
                onPlayAgain = {
                    navController.popBackStack(NavRoutes.GamesSortMakerSetup.createRoute(subject.key), false)
                },
                onOpenTierList = { navController.navigate(NavRoutes.GamesTierListEdit.createRoute(subject.key)) }
            )
        }
    }
    composable(NavRoutes.GamesTierListSetup.ROUTE) { backStackEntry ->
        val subject = SortMakerSubject.fromKey(backStackEntry.arguments?.getString("subject")) ?: SortMakerSubject.SONG
        SortMakerSetupScreen(
            subject = subject,
            purpose = SortMakerPurpose.TIER,
            onBack = { navController.popBackStack() },
            onPlay = {},
            onOpenTier = { navController.navigate(NavRoutes.GamesTierListEdit.createRoute(subject.key)) }
        )
    }
    composable(NavRoutes.GamesTierListEdit.ROUTE) { backStackEntry ->
        val subject = SortMakerSubject.fromKey(backStackEntry.arguments?.getString("subject")) ?: SortMakerSubject.SONG
        val context = LocalContext.current
        val board = remember(subject) { AppModule.from(context).tierListStore.board(subject) }
        if (board == null) {
            LaunchedEffect(Unit) { navController.popBackStack() }
        } else {
            TierListScreen(
                board = board,
                onBack = { navController.popBackStack() },
                onItemClick = { item ->
                    when (item) {
                        is com.fugaif.imaslivedb.ui.sortmaker.SortMakerItem.SongItem ->
                            navController.navigate(NavRoutes.SongDetail.createRoute(item.song.id))
                        is com.fugaif.imaslivedb.ui.sortmaker.SortMakerItem.IdolItem ->
                            navController.navigate(NavRoutes.IdolDetail.createRoute(item.idol.id))
                    }
                }
            )
        }
    }
    detailRoutes(navController)
}

/**
 * 誕生月で絞ったアイドル一覧への行き先。
 *
 * タブごとに NavHost が独立しているので、アイドル詳細を積める全グラフに同じ行き先を
 * 登録する。登録が漏れたタブでは詳細のプロフィール行を押しても遷移できない
 * (どの行が押せるかはコアが決めており、画面側で握りつぶすと OS 間で挙動がズレる)。
 */
private fun NavGraphBuilder.idolsByBirthMonthRoute(navController: NavHostController) {
    composable(NavRoutes.IdolsByBirthMonth.ROUTE) { backStackEntry ->
        val month = backStackEntry.arguments?.getString("month")?.toIntOrNull() ?: return@composable
        IdolsByBirthMonthScreen(
            month = month,
            onBack = { navController.popBackStack() },
            onIdolClick = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) }
        )
    }
}

/**
 * 絞り込み一覧 4 種 + アイドル×曲の披露履歴。
 *
 * [idolsByBirthMonthRoute] と同じ理由でタブごとの全グラフに登録する — 詳細画面はどのタブにも
 * 積めるので、登録が漏れたタブでは行を押しても遷移できない (押せる見た目だけ残る) 。
 *
 * ルート引数の value は `createRoute` 側で `Uri.encode` 済み。Navigation の
 * `NavDeepLink.getMatchingPathArguments` が取り出す時点で `Uri.decode` するので、
 * ここで復号し直さないこと (`%` を含む値が二重復号で壊れる)。
 */
private fun NavGraphBuilder.filteredListRoutes(navController: NavHostController) {
    composable(NavRoutes.FilteredSongs.ROUTE) { backStackEntry ->
        val kind = backStackEntry.arguments?.getString("kind") ?: return@composable
        val value = backStackEntry.arguments?.getString("value") ?: return@composable
        FilteredSongsScreen(
            kind = kind,
            value = value,
            onBack = { navController.popBackStack() },
            onSongClick = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.FilteredEvents.ROUTE) { backStackEntry ->
        val kind = backStackEntry.arguments?.getString("kind") ?: return@composable
        val value = backStackEntry.arguments?.getString("value") ?: return@composable
        FilteredEventsScreen(
            kind = kind,
            value = value,
            onBack = { navController.popBackStack() },
            onEventClick = { navController.navigate(NavRoutes.EventDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.FilteredShows.ROUTE) { backStackEntry ->
        val kind = backStackEntry.arguments?.getString("kind") ?: return@composable
        val value = backStackEntry.arguments?.getString("value") ?: return@composable
        FilteredShowsScreen(
            kind = kind,
            value = value,
            onBack = { navController.popBackStack() },
            onShowClick = { navController.navigate(NavRoutes.Setlist.createRoute(it)) }
        )
    }
    composable(NavRoutes.FilteredIdols.ROUTE) { backStackEntry ->
        val kind = backStackEntry.arguments?.getString("kind") ?: return@composable
        val value = backStackEntry.arguments?.getString("value") ?: return@composable
        FilteredIdolsScreen(
            kind = kind,
            value = value,
            onBack = { navController.popBackStack() },
            onIdolClick = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.IdolSongHistory.ROUTE) { backStackEntry ->
        val idolId = backStackEntry.arguments?.getString("idolId") ?: return@composable
        val songId = backStackEntry.arguments?.getString("songId") ?: return@composable
        IdolSongHistoryScreen(
            idolId = idolId,
            songId = songId,
            onBack = { navController.popBackStack() },
            onShowClick = { navController.navigate(NavRoutes.Setlist.createRoute(it)) }
        )
    }
}

/**
 * どのタブにも積める詳細画面と、そこから押せる行き先 (公演/曲/アイドル/ユニット/イベント/
 * お題/タグ/絞り込み一覧)。
 *
 * タブごとに NavHost が独立しているので、詳細画面から押せる行き先は全タブのグラフに
 * 要る。登録の無い行き先へ navigate すると IllegalArgumentException で落ちる。
 * タブ側で詳細を個別に書き写すと、コールバックの渡し漏れ (ユニットのタグが押せない) や
 * 行き先の登録漏れが起きるので、全タブがこれ 1 つを呼ぶ。
 */
private fun NavGraphBuilder.detailRoutes(navController: NavHostController) {
    composable(NavRoutes.EventDetail.ROUTE) { backStackEntry ->
        val eventId = backStackEntry.arguments?.getString("eventId") ?: return@composable
        EventDetailScreen(
            eventId = eventId,
            onBack = { navController.popBackStack() },
            onShowClick = { navController.navigate(NavRoutes.Setlist.createRoute(it)) },
            onIdolClick = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onFilteredEventsClick = { kind, value ->
                navController.navigate(NavRoutes.FilteredEvents.createRoute(kind, value))
            },
            onCostumeClick = { navController.navigate(NavRoutes.CostumeShows.createRoute(it)) }
        )
    }
    composable(NavRoutes.CostumeShows.ROUTE) { backStackEntry ->
        val costumeId = backStackEntry.arguments?.getString("costumeId") ?: return@composable
        CostumeShowsScreen(
            costumeId = costumeId,
            onBack = { navController.popBackStack() },
            onShowClick = { navController.navigate(NavRoutes.Setlist.createRoute(it)) }
        )
    }
    composable(
        NavRoutes.Setlist.ROUTE,
        arguments = listOf(navArgument("predict") { type = NavType.BoolType; defaultValue = false })
    ) { backStackEntry ->
        val showId = backStackEntry.arguments?.getString("showId") ?: return@composable
        SetlistScreen(
            showId = showId,
            opensPrediction = backStackEntry.arguments?.getBoolean("predict") ?: false,
            onBack = { navController.popBackStack() },
            onSongClick = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onIdolClick = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onFilteredShowsClick = { kind, value ->
                navController.navigate(NavRoutes.FilteredShows.createRoute(kind, value))
            },
            onEventClick = { eventId ->
                navController.navigate(NavRoutes.EventDetail.createRoute(eventId))
            },
            onFilteredEventsClick = { kind, value ->
                navController.navigate(NavRoutes.FilteredEvents.createRoute(kind, value))
            }
        )
    }
    composable(NavRoutes.SongDetail.ROUTE) { backStackEntry ->
        val songId = backStackEntry.arguments?.getString("songId") ?: return@composable
        SongDetailScreen(
            songId = songId,
            onBack = { navController.popBackStack() },
            onUnitClick = { navController.navigate(NavRoutes.UnitDetail.createRoute(it)) },
            onIdolClick = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onShowClick = { navController.navigate(NavRoutes.Setlist.createRoute(it)) },
            onPollClick = { navController.navigate(NavRoutes.PollDetail.createRoute(it)) },
            onFilteredSongsClick = { kind, value ->
                navController.navigate(NavRoutes.FilteredSongs.createRoute(kind, value))
            }
        )
    }
    composable(NavRoutes.IdolDetail.ROUTE) { backStackEntry ->
        val idolId = backStackEntry.arguments?.getString("idolId") ?: return@composable
        IdolDetailScreen(
            idolId = idolId,
            onNavigateBack = { navController.popBackStack() },
            onNavigateToUnitDetail = { navController.navigate(NavRoutes.UnitDetail.createRoute(it)) },
            onNavigateToSongDetail = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onNavigateToShowDetail = { navController.navigate(NavRoutes.Setlist.createRoute(it)) },
            onNavigateToIdolDetail = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onPollClick = { navController.navigate(NavRoutes.PollDetail.createRoute(it)) },
            onIdolTagClick = { navController.navigate(NavRoutes.IdolTagDetail.createRoute(it)) },
            onNavigateToBirthMonth = { navController.navigate(NavRoutes.IdolsByBirthMonth.createRoute(it)) },
            onNavigateToSongHistory = { id, songId ->
                navController.navigate(NavRoutes.IdolSongHistory.createRoute(id, songId))
            },
            onFilteredIdolsClick = { kind, value ->
                navController.navigate(NavRoutes.FilteredIdols.createRoute(kind, value))
            }
        )
    }
    composable(NavRoutes.UnitDetail.ROUTE) { backStackEntry ->
        val unitId = backStackEntry.arguments?.getString("unitId") ?: return@composable
        UnitDetailScreen(
            unitId = unitId,
            onNavigateBack = { navController.popBackStack() },
            onNavigateToIdolDetail = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onNavigateToSongDetail = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onNavigateToUnitDetail = { navController.navigate(NavRoutes.UnitDetail.createRoute(it)) },
            onPollClick = { navController.navigate(NavRoutes.PollDetail.createRoute(it)) },
            onUnitTagClick = { navController.navigate(NavRoutes.UnitTagDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.PollDetail.ROUTE) { backStackEntry ->
        val pollId = backStackEntry.arguments?.getString("pollId") ?: return@composable
        PollDetailScreen(pollId = pollId, onBack = { navController.popBackStack() })
    }
    composable(NavRoutes.IdolTagDetail.ROUTE) { backStackEntry ->
        val tagId = backStackEntry.arguments?.getString("tagId") ?: return@composable
        IdolTagDetailScreen(
            tagId = tagId,
            onBack = { navController.popBackStack() },
            onIdolClick = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.UnitTagDetail.ROUTE) { backStackEntry ->
        val tagId = backStackEntry.arguments?.getString("tagId") ?: return@composable
        UnitTagDetailScreen(
            tagId = tagId,
            onBack = { navController.popBackStack() },
            onUnitClick = { navController.navigate(NavRoutes.UnitDetail.createRoute(it)) }
        )
    }
    idolsByBirthMonthRoute(navController)
    filteredListRoutes(navController)
}
