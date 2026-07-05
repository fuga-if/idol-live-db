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

    data object Favorites : NavRoutes("favorites")
    data object AttendedEvents : NavRoutes("attended_events")
    data object MyContributions : NavRoutes("my_contributions")
    data object MyVotes : NavRoutes("my_votes")
    data object EditHistory : NavRoutes("edit_history")
    data object TagList : NavRoutes("tag_list")
    data class TagDetail(val tagId: String) : NavRoutes("tag_detail/{tagId}") {
        companion object {
            const val ROUTE = "tag_detail/{tagId}"
            fun createRoute(tagId: String) = "tag_detail/$tagId"
        }
    }
    data object GamesHub : NavRoutes("games_hub")
    data object IntroDonHome : NavRoutes("introdon_home")
    data object IntroDonSetup : NavRoutes("introdon_setup")
    data class IntroDonGame(
        val mode: String,
        val brandIds: String,
        val questionCount: Int,
        val introDurationMs: Long,
        val rushTimeLimitSec: Int
    ) : NavRoutes("introdon_game/{mode}/{brandIds}/{questionCount}/{introDurationMs}/{rushTimeLimitSec}") {
        companion object {
            const val ROUTE = "introdon_game/{mode}/{brandIds}/{questionCount}/{introDurationMs}/{rushTimeLimitSec}"
            fun createRoute(mode: String, brandIds: String, questionCount: Int, introDurationMs: Long, rushTimeLimitSec: Int) =
                "introdon_game/$mode/$brandIds/$questionCount/$introDurationMs/$rushTimeLimitSec"
        }
    }
    data class IntroDonParty(
        val brandIds: String,
        val questionCount: Int,
        val introDurationMs: Long
    ) : NavRoutes("introdon_party/{brandIds}/{questionCount}/{introDurationMs}") {
        companion object {
            const val ROUTE = "introdon_party/{brandIds}/{questionCount}/{introDurationMs}"
            fun createRoute(brandIds: String, questionCount: Int, introDurationMs: Long) =
                "introdon_party/$brandIds/$questionCount/$introDurationMs"
        }
    }
    data object GamesColorMatch : NavRoutes("games_colormatch")
    data object GamesIdolQuizSetup : NavRoutes("games_idolquiz_setup")
    data class GamesIdolQuiz(val brandIds: String) : NavRoutes("games_idolquiz/{brandIds}") {
        companion object {
            const val ROUTE = "games_idolquiz/{brandIds}"
            fun createRoute(brandIds: Set<String>) =
                "games_idolquiz/" + (if (brandIds.isEmpty()) "all" else brandIds.sorted().joinToString(","))
        }
    }
    data object GamesSongQuizSetup : NavRoutes("games_songquiz_setup")
    data class GamesSongQuiz(val brandIds: String) : NavRoutes("games_songquiz/{brandIds}") {
        companion object {
            const val ROUTE = "games_songquiz/{brandIds}"
            fun createRoute(brandIds: Set<String>) =
                "games_songquiz/" + (if (brandIds.isEmpty()) "all" else brandIds.sorted().joinToString(","))
        }
    }
}

/** ゲームのブランド絞り込みをルート引数の1文字列にエンコード/デコードする ("all" = 未選択=全ブランド)。 */
fun decodeGameBrandIds(raw: String?): Set<String> =
    if (raw.isNullOrEmpty() || raw == "all") emptySet() else raw.split(",").filter { it.isNotEmpty() }.toSet()

// Top-level tab routes (iOS の確定 IA に合わせる: スケジュール/ライブ/楽曲/アイドル/プロデュース)
enum class TopLevelTab(val route: String) {
    Schedule("tab_schedule"),
    Events("tab_events"),
    Songs("tab_songs"),
    Idols("tab_idols"),
    Produce("tab_produce")
}
