package com.fugaif.imaslivedb.ui.navigation

sealed class NavRoutes(val route: String) {
    data object EventList : NavRoutes("event_list")
    data class EventDetail(val eventId: String) : NavRoutes("event_detail/{eventId}") {
        companion object {
            const val ROUTE = "event_detail/{eventId}"
            fun createRoute(eventId: String) = "event_detail/$eventId"
        }
    }
    data class Setlist(val showId: String) : NavRoutes("setlist/{showId}") {
        companion object {
            const val ROUTE = "setlist/{showId}"
            fun createRoute(showId: String) = "setlist/$showId"
        }
    }
    data object SongList : NavRoutes("song_list")
    data class SongDetail(val songId: String) : NavRoutes("song_detail/{songId}") {
        companion object {
            const val ROUTE = "song_detail/{songId}"
            fun createRoute(songId: String) = "song_detail/$songId"
        }
    }
    data object Schedule : NavRoutes("schedule")
    data object Produce : NavRoutes("produce")
    data object Polls : NavRoutes("polls")
    data object IdolList : NavRoutes("idol_list")
    data class IdolDetail(val idolId: String) : NavRoutes("idol_detail/{idolId}") {
        companion object {
            const val ROUTE = "idol_detail/{idolId}"
            fun createRoute(idolId: String) = "idol_detail/$idolId"
        }
    }
    data class UnitDetail(val unitId: String) : NavRoutes("unit_detail/{unitId}") {
        companion object {
            const val ROUTE = "unit_detail/{unitId}"
            fun createRoute(unitId: String) = "unit_detail/$unitId"
        }
    }
    data object Stats : NavRoutes("stats")
    data object Settings : NavRoutes("settings")
    data object Search : NavRoutes("search")
}

// Top-level tab routes (iOS の確定 IA に合わせる: スケジュール/ライブ/楽曲/アイドル/プロデュース)
enum class TopLevelTab(val route: String) {
    Schedule("tab_schedule"),
    Events("tab_events"),
    Songs("tab_songs"),
    Idols("tab_idols"),
    Produce("tab_produce")
}
