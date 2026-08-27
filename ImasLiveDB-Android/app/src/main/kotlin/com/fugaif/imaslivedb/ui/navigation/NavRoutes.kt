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
    data class PollDetail(val pollId: String) : NavRoutes("poll_detail/{pollId}") {
        companion object {
            const val ROUTE = "poll_detail/{pollId}"
            fun createRoute(pollId: String) = "poll_detail/$pollId"
        }
    }
    data object IdolList : NavRoutes("idol_list")
    data class IdolDetail(val idolId: String) : NavRoutes("idol_detail/{idolId}") {
        companion object {
            const val ROUTE = "idol_detail/{idolId}"
            fun createRoute(idolId: String) = "idol_detail/$idolId"
        }
    }
    /**
     * 誕生月 (1..12) で絞ったアイドル一覧。アイドル詳細の誕生日行から開く
     * (iOS の `DetailDestination.filteredIdols(.birthMonth)` に対応)。
     */
    data class IdolsByBirthMonth(val month: Int) : NavRoutes("idols_by_birth_month/{month}") {
        companion object {
            const val ROUTE = "idols_by_birth_month/{month}"
            fun createRoute(month: Int) = "idols_by_birth_month/$month"
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
    /**
     * 検索。呼び出し元タブのスコープを引き継ぐ (`SearchScope` の name)。
     * 省略時は ALL。
     */
    data object Search : NavRoutes("search?scope={scope}") {
        const val ROUTE = "search?scope={scope}"
        fun createRoute(scope: String = "ALL") = "search?scope=$scope"
    }

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
    data class IdolTagDetail(val tagId: String) : NavRoutes("idol_tag_detail/{tagId}") {
        companion object {
            const val ROUTE = "idol_tag_detail/{tagId}"
            fun createRoute(tagId: String) = "idol_tag_detail/$tagId"
        }
    }
    data object TagActivity : NavRoutes("tag_activity")
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
    // --- 絞り込み一覧 (iOS Views/Filtered/) ---
    //
    // 「このブランドのライブ」「この会場での公演」のように、詳細画面の 1 行から
    // 同じ条件の一覧へ抜ける導線。条件は種類ごとに違うので、1 本のルートに
    // 詰め込まず種類ごとに分ける (引数の意味がルート名から読める方を採る)。
    // 値は URL 経路に載るので、呼び出し側で必ず Uri.encode すること。
    data class FilteredSongs(val kind: String, val value: String) :
        NavRoutes("filtered_songs/{kind}/{value}") {
        companion object {
            const val ROUTE = "filtered_songs/{kind}/{value}"
            /** kind: cd_series / series_group / release_year / brand / creator / song_type */
            fun createRoute(kind: String, value: String) =
                "filtered_songs/$kind/${android.net.Uri.encode(value)}"
        }
    }
    data class FilteredEvents(val kind: String, val value: String) :
        NavRoutes("filtered_events/{kind}/{value}") {
        companion object {
            const val ROUTE = "filtered_events/{kind}/{value}"
            /** kind: brand / year */
            fun createRoute(kind: String, value: String) =
                "filtered_events/$kind/${android.net.Uri.encode(value)}"
        }
    }
    data class FilteredShows(val kind: String, val value: String) :
        NavRoutes("filtered_shows/{kind}/{value}") {
        companion object {
            const val ROUTE = "filtered_shows/{kind}/{value}"
            /** kind: venue / date */
            fun createRoute(kind: String, value: String) =
                "filtered_shows/$kind/${android.net.Uri.encode(value)}"
        }
    }
    data class FilteredIdols(val kind: String, val value: String) :
        NavRoutes("filtered_idols/{kind}/{value}") {
        companion object {
            const val ROUTE = "filtered_idols/{kind}/{value}"
            /** kind: brand / constellation / birth_place / blood_type */
            fun createRoute(kind: String, value: String) =
                "filtered_idols/$kind/${android.net.Uri.encode(value)}"
        }
    }

    /** 終了したお題の優勝者一覧 (iOS PollHallOfFameView)。 */
    data object PollHallOfFame : NavRoutes("poll_hall_of_fame")

    /** ユニットタグの詳細 (曲/アイドルのタグ詳細と同型)。 */
    data class UnitTagDetail(val tagId: String) : NavRoutes("unit_tag_detail/{tagId}") {
        companion object {
            const val ROUTE = "unit_tag_detail/{tagId}"
            fun createRoute(tagId: String) = "unit_tag_detail/$tagId"
        }
    }

    /** ブランドの年表 (iOS BrandTimelineView)。 */
    data class BrandTimeline(val brandId: String) : NavRoutes("brand_timeline/{brandId}") {
        companion object {
            const val ROUTE = "brand_timeline/{brandId}"
            fun createRoute(brandId: String) = "brand_timeline/$brandId"
        }
    }

    /** アイドル × 曲 の披露履歴 (iOS IdolSongHistoryView)。 */
    data class IdolSongHistory(val idolId: String, val songId: String) :
        NavRoutes("idol_song_history/{idolId}/{songId}") {
        companion object {
            const val ROUTE = "idol_song_history/{idolId}/{songId}"
            fun createRoute(idolId: String, songId: String) = "idol_song_history/$idolId/$songId"
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
