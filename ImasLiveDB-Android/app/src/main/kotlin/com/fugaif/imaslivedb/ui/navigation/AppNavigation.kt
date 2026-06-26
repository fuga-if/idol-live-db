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
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.fugaif.imaslivedb.ui.events.EventDetailScreen
import com.fugaif.imaslivedb.ui.events.EventListScreen
import com.fugaif.imaslivedb.ui.events.SetlistScreen
import com.fugaif.imaslivedb.ui.idols.IdolDetailScreen
import com.fugaif.imaslivedb.ui.idols.IdolListScreen
import com.fugaif.imaslivedb.ui.polls.PollsScreen
import com.fugaif.imaslivedb.ui.produce.ProduceScreen
import com.fugaif.imaslivedb.ui.schedule.CalendarScreen
import com.fugaif.imaslivedb.ui.search.SearchScreen
import com.fugaif.imaslivedb.ui.settings.SettingsScreen
import com.fugaif.imaslivedb.ui.songs.SongDetailScreen
import com.fugaif.imaslivedb.ui.songs.SongListScreen
import com.fugaif.imaslivedb.ui.stats.StatsScreen
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
            }
        )
    }
    composable(NavRoutes.Search.route) {
        SearchScreen(
            onNavigateToIdolDetail = { idolId ->
                navController.navigate(NavRoutes.IdolDetail.createRoute(idolId))
            },
            onNavigateToSongDetail = { songId ->
                navController.navigate(NavRoutes.SongDetail.createRoute(songId))
            },
            onNavigateToEventDetail = { eventId ->
                navController.navigate(NavRoutes.EventDetail.createRoute(eventId))
            }
        )
    }
}

private fun NavGraphBuilder.songsNavGraph(navController: NavHostController) {
    composable(NavRoutes.SongList.route) {
        SongListScreen(
            onSongClick = { songId ->
                navController.navigate(NavRoutes.SongDetail.createRoute(songId))
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
            onNavigateToSearch = { navController.navigate(NavRoutes.Search.route) },
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
            onNavigateToSearch = { navController.navigate(NavRoutes.Search.route) },
            onNavigateToPolls = { navController.navigate(NavRoutes.Polls.route) },
            onNavigateToIdol = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onNavigateToSong = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.Stats.route) { StatsScreen() }
    composable(NavRoutes.Settings.route) { SettingsScreen() }
    composable(NavRoutes.Polls.route) { PollsScreen(onBack = { navController.popBackStack() }) }
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
            onShowClick = { navController.navigate(NavRoutes.Setlist.createRoute(it)) }
        )
    }
    composable(NavRoutes.IdolDetail.ROUTE) { backStackEntry ->
        val idolId = backStackEntry.arguments?.getString("idolId") ?: return@composable
        IdolDetailScreen(
            idolId = idolId,
            onNavigateBack = { navController.popBackStack() },
            onNavigateToUnitDetail = { navController.navigate(NavRoutes.UnitDetail.createRoute(it)) },
            onNavigateToSongDetail = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onNavigateToShowDetail = { navController.navigate(NavRoutes.Setlist.createRoute(it)) }
        )
    }
    composable(NavRoutes.UnitDetail.ROUTE) { backStackEntry ->
        val unitId = backStackEntry.arguments?.getString("unitId") ?: return@composable
        UnitDetailScreen(
            unitId = unitId,
            onNavigateBack = { navController.popBackStack() },
            onNavigateToIdolDetail = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onNavigateToSongDetail = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) }
        )
    }
    composable(NavRoutes.Search.route) {
        SearchScreen(
            onNavigateToIdolDetail = { navController.navigate(NavRoutes.IdolDetail.createRoute(it)) },
            onNavigateToSongDetail = { navController.navigate(NavRoutes.SongDetail.createRoute(it)) },
            onNavigateToEventDetail = { navController.navigate(NavRoutes.EventDetail.createRoute(it)) }
        )
    }
}
