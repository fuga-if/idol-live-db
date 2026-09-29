package com.fugaif.imaslivedb.ui.navigation

import androidx.navigation.NavGraph
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.compose.ComposeNavigator
import androidx.navigation.createGraph
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * タブごとの NavHost に、詳細画面から押せる行き先が全部登録されていること。
 *
 * タブの NavHost は独立していて、登録の無い行き先へ navigate すると
 * IllegalArgumentException で落ちる。詳細画面はどのタブにも積めるので、
 * 詳細画面が押せる行き先 (お題・タグの詳細を含む) はどのタブにも要る。
 */
@RunWith(RobolectricTestRunner::class)
class AppNavigationGraphTest {

    private fun graph(startDestination: String, build: NavGraphBuilder.(NavHostController) -> Unit): NavGraph {
        val navController = NavHostController(RuntimeEnvironment.getApplication())
        navController.navigatorProvider.addNavigator(ComposeNavigator())
        return navController.createGraph(startDestination) { build(navController) }
    }

    @Test
    fun everyTabRegistersEveryDetailDestination() {
        val tabs = mapOf(
            TopLevelTab.Schedule to graph(NavRoutes.Schedule.route) { scheduleNavGraph(it) },
            TopLevelTab.Events to graph(NavRoutes.EventList.route) { eventsNavGraph(it) },
            TopLevelTab.Songs to graph(NavRoutes.SongList.route) { songsNavGraph(it) },
            TopLevelTab.Idols to graph(NavRoutes.IdolList.route) { idolsNavGraph(it) },
            TopLevelTab.Produce to graph(NavRoutes.Produce.route) { produceNavGraph(it) },
        )
        val missing = tabs.flatMap { (tab, graph) ->
            DETAIL_DESTINATIONS.filter { graph.findNode(it) == null }.map { "${tab.label}: $it" }
        }
        assertTrue("登録されていない行き先:\n" + missing.joinToString("\n"), missing.isEmpty())
    }

    private companion object {
        /** 詳細画面 (公演・曲・アイドル・ユニット・イベント) と、そこから押せる行き先。 */
        val DETAIL_DESTINATIONS = listOf(
            NavRoutes.EventDetail.ROUTE,
            NavRoutes.Setlist.ROUTE,
            NavRoutes.SongDetail.ROUTE,
            NavRoutes.IdolDetail.ROUTE,
            NavRoutes.UnitDetail.ROUTE,
            NavRoutes.PollDetail.ROUTE,
            NavRoutes.IdolTagDetail.ROUTE,
            NavRoutes.UnitTagDetail.ROUTE,
            NavRoutes.IdolsByBirthMonth.ROUTE,
            NavRoutes.IdolSongHistory.ROUTE,
            NavRoutes.FilteredSongs.ROUTE,
            NavRoutes.FilteredEvents.ROUTE,
            NavRoutes.FilteredShows.ROUTE,
            NavRoutes.FilteredIdols.ROUTE,
        )
    }
}
