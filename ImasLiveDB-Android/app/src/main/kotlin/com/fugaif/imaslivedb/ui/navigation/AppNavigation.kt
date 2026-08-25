package com.fugaif.imaslivedb.ui.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavType
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.fugaif.imaslivedb.ui.edit.RecentEditsScreen
import com.fugaif.imaslivedb.ui.events.EventDetailScreen
import com.fugaif.imaslivedb.ui.events.EventListScreen
import com.fugaif.imaslivedb.ui.events.SetlistScreen
import com.fugaif.imaslivedb.ui.games.ColorMatchGameScreen
import com.fugaif.imaslivedb.ui.games.GamesHubScreen
import com.fugaif.imaslivedb.ui.games.IdolQuizScreen
import com.fugaif.imaslivedb.ui.games.IdolQuizSetupScreen
import com.fugaif.imaslivedb.ui.games.SongSingerQuizScreen
import com.fugaif.imaslivedb.ui.games.SongSingerQuizSetupScreen
import com.fugaif.imaslivedb.ui.idols.IdolDetailScreen
import com.fugaif.imaslivedb.ui.idols.IdolListScreen
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
import com.fugaif.imaslivedb.ui.polls.PollsScreen
import com.fugaif.imaslivedb.ui.produce.ProduceScreen
import com.fugaif.imaslivedb.ui.schedule.CalendarScreen
import com.fugaif.imaslivedb.data.repository.SearchScope
import com.fugaif.imaslivedb.ui.search.SearchScreen
import com.fugaif.imaslivedb.ui.settings.SettingsScreen
import com.fugaif.imaslivedb.ui.songs.SongDetailScreen
import com.fugaif.imaslivedb.ui.songs.SongListScreen
import com.fugaif.imaslivedb.ui.stats.StatsScreen
import com.fugaif.imaslivedb.ui.tags.IdolTagDetailScreen
import com.fugaif.imaslivedb.ui.tags.TagActivityScreen
import com.fugaif.imaslivedb.ui.tags.TagDetailScreen
import com.fugaif.imaslivedb.ui.tags.TagListScreen
import com.fugaif.imaslivedb.ui.units.UnitDetailScreen

@Composable
fun AppNavigation() {
    var currentTab by rememberSaveable { mutableStateOf(TopLevelTab.Schedule) }

    // One NavController per tab to maintain independent back stacks
    val scheduleNavController = rememberNavController()
    val eventsNavController = rememberNavController()
    val songsNavController = rememberNavController()
    val idolsNavController = rememberNavController()
    val produceNavController = rememberNavController()

    Scaffold(
        bottomBar = {
            BottomNavBar(
                currentTab = currentTab,
                onTabSelected = { currentTab = it }
            )
        }
    ) { innerPadding ->
        Box(modifier = Modifier.padding(innerPadding)) {
            // Each tab gets its own NavHost so back stacks are independent.
            // Only the active tab is visible; others remain in composition.
            if (currentTab == TopLevelTab.Schedule) {
                TabNavHost(
                    navController = scheduleNavController,
                    startDestination = NavRoutes.Schedule.route,
                    graphBuilder = { scheduleNavGraph(scheduleNavController) }
                )
            }
            if (currentTab == TopLevelTab.Events) {
                TabNavHost(
                    navController = eventsNavController,
                    startDestination = NavRoutes.EventList.route,
                    graphBuilder = { eventsNavGraph(eventsNavController) }
                )
            }
            if (currentTab == TopLevelTab.Songs) {
                TabNavHost(
                    navController = songsNavController,
                    startDestination = NavRoutes.SongList.route,
                    graphBuilder = { songsNavGraph(songsNavController) }
                )
            }
            if (currentTab == TopLevelTab.Idols) {
                TabNavHost(
                    navController = idolsNavController,
                    startDestination = NavRoutes.IdolList.route,
                    graphBuilder = { idolsNavGraph(idolsNavController) }
                )
            }
            if (currentTab == TopLevelTab.Produce) {
                TabNavHost(
                    navController = produceNavController,
                    startDestination = NavRoutes.Produce.route,
                    graphBuilder = { produceNavGraph(produceNavController) }
                )
            }
        }
    }
}

@Composable
private fun TabNavHost(
    navController: NavHostController,
    startDestination: String,
    graphBuilder: NavGraphBuilder.() -> Unit
) {
    NavHost(
        navController = navController,
        startDestination = startDestination,
        modifier = Modifier.fillMaxSize(),
        builder = graphBuilder
    )
}

// --- Per-tab nav graphs ---

private fun NavGraphBuilder.eventsNavGraph(navController: NavHostController) {
    composable(NavRoutes.EventList.route) {
        EventListScreen(
            onEventClick = { eventId ->
                navController.navigate(NavRoutes.EventDetail.createRoute(eventId))
            },
            onNavigateToSearch = {
                navController.navigate(NavRoutes.Search.createRoute(SearchScope.EVENTS.name))
            }
        )
    }
    composable(NavRoutes.EventDetail.ROUTE) { backStackEntry ->
        val eventId = backStackEntry.arguments?.getString("eventId") ?: return@composable
        EventDetailScreen(
            eventId = eventId,
            onBack = { navController.popBackStack() },
            onShowClick = { showId ->
                navController.navigate(NavRoutes.Setlist.createRoute(showId))
            },
            onIdolClick = { idolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(idolId))
            }
        )
    }
    composable(NavRoutes.Setlist.ROUTE) { backStackEntry ->
        val showId = backStackEntry.arguments?.getString("showId") ?: return@composable
        SetlistScreen(
            showId = showId,
            onBack = { navController.popBackStack() },
            onSongClick = { songId ->
                navController.navigate(NavRoutes.SongDetail.createRoute(songId))
            },
            onIdolClick = { idolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(idolId))
            }
        )
    }
    composable(NavRoutes.IdolDetail.ROUTE) { backStackEntry ->
        val idolId = backStackEntry.arguments?.getString("idolId") ?: return@composable
        IdolDetailScreen(
            idolId = idolId,
            onNavigateBack = { navController.popBackStack() },
            onNavigateToUnitDetail = { unitId ->
                navController.navigate(NavRoutes.UnitDetail.createRoute(unitId))
            },
            onNavigateToSongDetail = { songId ->
                navController.navigate(NavRoutes.SongDetail.createRoute(songId))
            },
            onNavigateToShowDetail = { showId ->
                navController.navigate(NavRoutes.Setlist.createRoute(showId))
            },
            onNavigateToIdolDetail = { otherIdolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(otherIdolId))
            },
            onPollClick = { pollId ->
                navController.navigate(NavRoutes.PollDetail.createRoute(pollId))
            },
            onIdolTagClick = { tagId ->
                navController.navigate(NavRoutes.IdolTagDetail.createRoute(tagId))
            }
        )
    }
    composable(NavRoutes.SongDetail.ROUTE) { backStackEntry ->
        val songId = backStackEntry.arguments?.getString("songId") ?: return@composable
        SongDetailScreen(
            songId = songId,
            onBack = { navController.popBackStack() },
            onUnitClick = { unitId ->
                navController.navigate(NavRoutes.UnitDetail.createRoute(unitId))
            },
            onIdolClick = { idolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(idolId))
            },
            onShowClick = { showId ->
                navController.navigate(NavRoutes.Setlist.createRoute(showId))
            },
            onPollClick = { pollId ->
                navController.navigate(NavRoutes.PollDetail.createRoute(pollId))
            }
        )
    }
    composable(NavRoutes.UnitDetail.ROUTE) { backStackEntry ->
        val unitId = backStackEntry.arguments?.getString("unitId") ?: return@composable
        UnitDetailScreen(
            unitId = unitId,
            onNavigateBack = { navController.popBackStack() },
            onNavigateToIdolDetail = { idolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(idolId))
            },
            onNavigateToSongDetail = { songId ->
                navController.navigate(NavRoutes.SongDetail.createRoute(songId))
            },
            onNavigateToUnitDetail = { otherUnitId ->
                navController.navigate(NavRoutes.UnitDetail.createRoute(otherUnitId))
            },
            onPollClick = { pollId ->
                navController.navigate(NavRoutes.PollDetail.createRoute(pollId))
            }
        )
    }
    composable(
        route = NavRoutes.Search.ROUTE,
        arguments = listOf(navArgument("scope") {
            type = NavType.StringType
            defaultValue = SearchScope.ALL.name
        })
    ) { backStackEntry ->
        val scope = runCatching {
            SearchScope.valueOf(backStackEntry.arguments?.getString("scope") ?: SearchScope.ALL.name)
        }.getOrDefault(SearchScope.ALL)
        SearchScreen(
            initialScope = scope,
            onNavigateToIdolDetail = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onNavigateToSongDetail = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onNavigateToEventDetail = { navController.navigate(NavRoutes.EventDetail.createRoute(it)) }
        )
    }
}

private fun NavGraphBuilder.songsNavGraph(navController: NavHostController) {
    composable(NavRoutes.SongList.route) {
        SongListScreen(
            onSongClick = { songId ->
                navController.navigate(NavRoutes.SongDetail.createRoute(songId))
            },
            onNavigateToSearch = {
                navController.navigate(NavRoutes.Search.createRoute(SearchScope.SONGS.name))
            }
        )
    }
    composable(NavRoutes.SongDetail.ROUTE) { backStackEntry ->
        val songId = backStackEntry.arguments?.getString("songId") ?: return@composable
        SongDetailScreen(
            songId = songId,
            onBack = { navController.popBackStack() },
            onUnitClick = { unitId ->
                navController.navigate(NavRoutes.UnitDetail.createRoute(unitId))
            },
            onIdolClick = { idolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(idolId))
            },
            onShowClick = { showId ->
                navController.navigate(NavRoutes.Setlist.createRoute(showId))
            },
            onPollClick = { pollId ->
                navController.navigate(NavRoutes.PollDetail.createRoute(pollId))
            }
        )
    }
    composable(NavRoutes.IdolDetail.ROUTE) { backStackEntry ->
        val idolId = backStackEntry.arguments?.getString("idolId") ?: return@composable
        IdolDetailScreen(
            idolId = idolId,
            onNavigateBack = { navController.popBackStack() },
            onNavigateToUnitDetail = { unitId ->
                navController.navigate(NavRoutes.UnitDetail.createRoute(unitId))
            },
            onNavigateToSongDetail = { songId ->
                navController.navigate(NavRoutes.SongDetail.createRoute(songId))
            },
            onNavigateToShowDetail = { showId ->
                navController.navigate(NavRoutes.Setlist.createRoute(showId))
            },
            onNavigateToIdolDetail = { otherIdolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(otherIdolId))
            },
            onPollClick = { pollId ->
                navController.navigate(NavRoutes.PollDetail.createRoute(pollId))
            },
            onIdolTagClick = { tagId ->
                navController.navigate(NavRoutes.IdolTagDetail.createRoute(tagId))
            }
        )
    }
    composable(NavRoutes.UnitDetail.ROUTE) { backStackEntry ->
        val unitId = backStackEntry.arguments?.getString("unitId") ?: return@composable
        UnitDetailScreen(
            unitId = unitId,
            onNavigateBack = { navController.popBackStack() },
            onNavigateToIdolDetail = { idolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(idolId))
            },
            onNavigateToSongDetail = { songId ->
                navController.navigate(NavRoutes.SongDetail.createRoute(songId))
            },
            onNavigateToUnitDetail = { otherUnitId ->
                navController.navigate(NavRoutes.UnitDetail.createRoute(otherUnitId))
            },
            onPollClick = { pollId ->
                navController.navigate(NavRoutes.PollDetail.createRoute(pollId))
            }
        )
    }
    composable(NavRoutes.Setlist.ROUTE) { backStackEntry ->
        val showId = backStackEntry.arguments?.getString("showId") ?: return@composable
        SetlistScreen(
            showId = showId,
            onBack = { navController.popBackStack() },
            onSongClick = { songId ->
                navController.navigate(NavRoutes.SongDetail.createRoute(songId))
            },
            onIdolClick = { idolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(idolId))
            }
        )
    }
}

private fun NavGraphBuilder.idolsNavGraph(navController: NavHostController) {
    composable(NavRoutes.IdolList.route) {
        IdolListScreen(
            onNavigateToIdolDetail = { idolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(idolId))
            },
            onNavigateToUnitDetail = { unitId ->
                navController.navigate(NavRoutes.UnitDetail.createRoute(unitId))
            },
            onNavigateToSearch = {
                navController.navigate(NavRoutes.Search.createRoute(SearchScope.IDOLS.name))
            }
        )
    }
    composable(NavRoutes.IdolDetail.ROUTE) { backStackEntry ->
        val idolId = backStackEntry.arguments?.getString("idolId") ?: return@composable
        IdolDetailScreen(
            idolId = idolId,
            onNavigateBack = { navController.popBackStack() },
            onNavigateToUnitDetail = { unitId ->
                navController.navigate(NavRoutes.UnitDetail.createRoute(unitId))
            },
            onNavigateToSongDetail = { songId ->
                navController.navigate(NavRoutes.SongDetail.createRoute(songId))
            },
            onNavigateToShowDetail = { showId ->
                navController.navigate(NavRoutes.Setlist.createRoute(showId))
            },
            onNavigateToIdolDetail = { otherIdolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(otherIdolId))
            },
            onPollClick = { pollId ->
                navController.navigate(NavRoutes.PollDetail.createRoute(pollId))
            },
            onIdolTagClick = { tagId ->
                navController.navigate(NavRoutes.IdolTagDetail.createRoute(tagId))
            }
        )
    }
    composable(NavRoutes.UnitDetail.ROUTE) { backStackEntry ->
        val unitId = backStackEntry.arguments?.getString("unitId") ?: return@composable
        UnitDetailScreen(
            unitId = unitId,
            onNavigateBack = { navController.popBackStack() },
            onNavigateToIdolDetail = { idolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(idolId))
            },
            onNavigateToSongDetail = { songId ->
                navController.navigate(NavRoutes.SongDetail.createRoute(songId))
            },
            onNavigateToUnitDetail = { otherUnitId ->
                navController.navigate(NavRoutes.UnitDetail.createRoute(otherUnitId))
            },
            onPollClick = { pollId ->
                navController.navigate(NavRoutes.PollDetail.createRoute(pollId))
            }
        )
    }
    composable(NavRoutes.SongDetail.ROUTE) { backStackEntry ->
        val songId = backStackEntry.arguments?.getString("songId") ?: return@composable
        SongDetailScreen(
            songId = songId,
            onBack = { navController.popBackStack() },
            onUnitClick = { unitId ->
                navController.navigate(NavRoutes.UnitDetail.createRoute(unitId))
            },
            onIdolClick = { idolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(idolId))
            },
            onShowClick = { showId ->
                navController.navigate(NavRoutes.Setlist.createRoute(showId))
            },
            onPollClick = { pollId ->
                navController.navigate(NavRoutes.PollDetail.createRoute(pollId))
            }
        )
    }
    composable(NavRoutes.Setlist.ROUTE) { backStackEntry ->
        val showId = backStackEntry.arguments?.getString("showId") ?: return@composable
        SetlistScreen(
            showId = showId,
            onBack = { navController.popBackStack() },
            onSongClick = { songId ->
                navController.navigate(NavRoutes.SongDetail.createRoute(songId))
            },
            onIdolClick = { idolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(idolId))
            }
        )
    }
}

private fun NavGraphBuilder.scheduleNavGraph(navController: NavHostController) {
    composable(NavRoutes.Schedule.route) {
        CalendarScreen(
            onNavigateToShow = { navController.navigate(NavRoutes.Setlist.createRoute(it)) },
            onNavigateToSong = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onNavigateToIdol = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onNavigateToEvent = { navController.navigate(NavRoutes.EventDetail.createRoute(it)) },
            onNavigateToSearch = { navController.navigate(NavRoutes.Search.createRoute()) },
            onNavigateToSettings = { navController.navigate(NavRoutes.Settings.route) }
        )
    }
    composable(NavRoutes.Settings.route) { SettingsScreen() }
    detailRoutes(navController)
}

private fun NavGraphBuilder.produceNavGraph(navController: NavHostController) {
    composable(NavRoutes.Produce.route) {
        ProduceScreen(
            onNavigateToStats = { navController.navigate(NavRoutes.Stats.route) },
            onNavigateToSettings = { navController.navigate(NavRoutes.Settings.route) },
            onNavigateToSearch = { navController.navigate(NavRoutes.Search.createRoute()) },
            onNavigateToPolls = { navController.navigate(NavRoutes.Polls.route) },
            onNavigateToIdol = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onNavigateToSong = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onNavigateToFavorites = { navController.navigate(NavRoutes.Favorites.route) },
            onNavigateToAttendedEvents = { navController.navigate(NavRoutes.AttendedEvents.route) },
            onNavigateToMyContributions = { navController.navigate(NavRoutes.MyContributions.route) },
            onNavigateToMyVotes = { navController.navigate(NavRoutes.MyVotes.route) },
            onNavigateToEditHistory = { navController.navigate(NavRoutes.EditHistory.route) },
            onNavigateToTagList = { navController.navigate(NavRoutes.TagList.route) },
            onNavigateToTagActivity = { navController.navigate(NavRoutes.TagActivity.route) },
            onNavigateToGamesHub = { navController.navigate(NavRoutes.GamesHub.route) }
        )
    }
    composable(NavRoutes.Stats.route) { StatsScreen() }
    composable(NavRoutes.Settings.route) { SettingsScreen() }
    composable(NavRoutes.Polls.route) {
        PollsScreen(
            onBack = { navController.popBackStack() },
            onPollClick = { navController.navigate(NavRoutes.PollDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.PollDetail.ROUTE) { backStackEntry ->
        val pollId = backStackEntry.arguments?.getString("pollId") ?: return@composable
        PollDetailScreen(pollId = pollId, onBack = { navController.popBackStack() })
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
        RecentEditsScreen(onBack = { navController.popBackStack() })
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
    composable(NavRoutes.IdolTagDetail.ROUTE) { backStackEntry ->
        val tagId = backStackEntry.arguments?.getString("tagId") ?: return@composable
        IdolTagDetailScreen(
            tagId = tagId,
            onBack = { navController.popBackStack() },
            onIdolClick = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.TagActivity.route) {
        TagActivityScreen(
            onBack = { navController.popBackStack() },
            onSongTagClick = { navController.navigate(NavRoutes.TagDetail.createRoute(it)) },
            onIdolTagClick = { navController.navigate(NavRoutes.IdolTagDetail.createRoute(it)) },
            onSongClick = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onIdolClick = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.GamesHub.route) {
        GamesHubScreen(
            onBack = { navController.popBackStack() },
            onNavigateToIntroDon = { navController.navigate(NavRoutes.IntroDonHome.route) },
            onNavigateToColorMatch = { navController.navigate(NavRoutes.GamesColorMatch.route) },
            onNavigateToIdolQuizSetup = { navController.navigate(NavRoutes.GamesIdolQuizSetup.route) },
            onNavigateToSongQuizSetup = { navController.navigate(NavRoutes.GamesSongQuizSetup.route) }
        )
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
    detailRoutes(navController)
}

/** 複数タブで共有する詳細・検索ルート群 (公演/曲/アイドル/ユニット/イベント/検索)。 */
private fun NavGraphBuilder.detailRoutes(navController: NavHostController) {
    composable(NavRoutes.EventDetail.ROUTE) { backStackEntry ->
        val eventId = backStackEntry.arguments?.getString("eventId") ?: return@composable
        EventDetailScreen(
            eventId = eventId,
            onBack = { navController.popBackStack() },
            onShowClick = { navController.navigate(NavRoutes.Setlist.createRoute(it)) },
            onIdolClick = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.Setlist.ROUTE) { backStackEntry ->
        val showId = backStackEntry.arguments?.getString("showId") ?: return@composable
        SetlistScreen(
            showId = showId,
            onBack = { navController.popBackStack() },
            onSongClick = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onIdolClick = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) }
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
            onPollClick = { navController.navigate(NavRoutes.PollDetail.createRoute(it)) }
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
            onIdolTagClick = { navController.navigate(NavRoutes.IdolTagDetail.createRoute(it)) }
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
            onPollClick = { navController.navigate(NavRoutes.PollDetail.createRoute(it)) }
        )
    }
    composable(
        route = NavRoutes.Search.ROUTE,
        arguments = listOf(navArgument("scope") {
            type = NavType.StringType
            defaultValue = SearchScope.ALL.name
        })
    ) { backStackEntry ->
        val scope = runCatching {
            SearchScope.valueOf(backStackEntry.arguments?.getString("scope") ?: SearchScope.ALL.name)
        }.getOrDefault(SearchScope.ALL)
        SearchScreen(
            initialScope = scope,
            onNavigateToIdolDetail = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onNavigateToSongDetail = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onNavigateToEventDetail = { navController.navigate(NavRoutes.EventDetail.createRoute(it)) }
        )
    }
}
