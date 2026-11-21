package com.fugaif.imaslivedb.data.chatgpt

import com.fugaif.imaslivedb.data.community.SetlistLikeService
import com.fugaif.imaslivedb.data.community.SetlistPredictionService
import android.content.Context
import android.graphics.Bitmap
import com.fugaif.imaslivedb.data.model.AttendanceType
import com.fugaif.imaslivedb.data.model.CalShowRow
import com.fugaif.imaslivedb.data.notification.NotificationCategory
import com.fugaif.imaslivedb.data.notification.NotificationPrefs
import com.fugaif.imaslivedb.data.notification.NotificationScheduler
import com.fugaif.imaslivedb.data.repository.CalendarShowDetail
import com.fugaif.imaslivedb.data.repository.EventRepository
import com.fugaif.imaslivedb.ui.schedule.DeviceCalendar
import com.fugaif.imaslivedb.ui.navigation.TopLevelTab
import com.fugaif.imaslivedb.ui.search.CrossTabSearch
import com.fugaif.imaslivedb.data.model.Expense
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.data.repository.ExpenseRepository
import com.fugaif.imaslivedb.data.repository.PersonalTagRepository
import com.fugaif.imaslivedb.data.repository.PlaylistRepository
import com.fugaif.imaslivedb.data.repository.SongRepository
import com.fugaif.imaslivedb.data.repository.UserMarkRepository
import com.fugaif.imaslivedb.player.LyricsPlayback
import com.fugaif.imaslivedb.player.PlaylistPlayback
import com.fugaif.imaslivedb.ui.chatgpt.NaturalSearchKind
import com.fugaif.imaslivedb.ui.chatgpt.NaturalSearchTarget
import uniffi.imas_core.AiAction

/**
 * コアが検査した操作 1 件を、既存の書き込み口 1 回に写す。iOS `AssistantExecutor`。
 *
 * 規則 (どの操作があるか・id が実在するか・どこまで届くか) はコア (`domain::ai_actions`)。
 * ここは OS の持ち物 (端末の DB・再生・サーバへの送信) を呼ぶだけで、判断を足さない。
 */
class AssistantExecutor(
    private val marks: UserMarkRepository,
    private val personalTags: PersonalTagRepository,
    private val playlists: PlaylistRepository,
    private val expenses: ExpenseRepository,
    private val songs: SongRepository,
    private val events: EventRepository,
    private val context: Context,
    private val playback: LyricsPlayback,
    private val predictions: SetlistPredictionService,
    private val likes: SetlistLikeService,
    private val cardEditor: AssistantCardEditor,
) {
    /** 画面に出す失敗の文言を持つ。 */
    class Failure(message: String) : Exception(message)

    /** 実行のあと、画面の側でやること。 */
    sealed interface Opened {
        /** シートの中 (本体のナビ) で詳細を開く。 */
        data class Detail(val target: NaturalSearchTarget) : Opened
        /** 一覧のタブへ移った (シートを閉じる)。 */
        data object List : Opened
        /** 利用者の持ち物の画面 (プロデュースのナビの中で開く)。 */
        data class Screen(val screen: AssistantScreen) : Opened
    }

    /**
     * @param images その番の発言に添えた画像 (P名刺の写真・素材に使う)。
     * @return 開くもの (`Open` / `OpenList` / 名刺を直したとき)。
     */
    suspend fun perform(action: AiAction, images: List<Bitmap> = emptyList()): Opened? {
        when (action) {
            is AiAction.SetAttendance -> {
                val type = AttendanceType.from(action.attendance) ?: throw Failure("参加の種類が分かりません")
                marks.setAttendance(UserMark.SHOW, action.showId, type, action.on)
            }
            is AiAction.SetFavoriteSong -> setOnOff(UserMark.SONG, action.songId, UserMark.FAVORITE, action.on)
            is AiAction.SetMyPick -> setOnOff(UserMark.IDOL, action.idolId, UserMark.PICK, action.on)
            is AiAction.SetNote -> {
                if (action.entity !in NOTE_ENTITIES) throw Failure("メモを書けない対象です")
                marks.setNote(action.entity, action.id, action.text.ifEmpty { null })
            }
            is AiAction.SetSeat -> marks.setSeat(UserMark.SHOW, action.showId, action.text.ifEmpty { null })
            is AiAction.AddPersonalTag -> {
                // 端末は同名のタグを黙って置き換える (iOS は「付けられませんでした」を返す)。
                personalTags.addTag(action.entity, action.id, action.name)
            }
            is AiAction.RemovePersonalTag -> personalTags.removeTag(action.entity, action.id, action.name)
            is AiAction.CreatePlaylist -> {
                val playlist = playlists.create(action.name)
                try {
                    playlists.setSongIds(playlist.id, action.songIds)
                } catch (e: Exception) {
                    // 曲を入れられなかったら、空のプレイリストを残さない。
                    runCatching { playlists.delete(playlist.id) }
                    throw e
                }
            }
            is AiAction.AddToPlaylist -> playlists.append(action.playlistId, action.songIds)
            is AiAction.AddExpense -> expenses.save(
                Expense.make(action.date, action.category, action.amount, action.showId, action.eventId, action.note)
            )
            is AiAction.Open -> return Opened.Detail(destination(action.entity, action.id))
            is AiAction.PlaySongs -> {
                if (!PlaylistPlayback.play(playback, orderedSongs(action.songIds))) {
                    throw Failure("続けて流すには Apple Music の契約か Spotify の連携が要ります")
                }
            }
            is AiAction.SetOwnedRelease -> setOnOff(UserMark.RELEASE, action.releaseId, UserMark.OWNED, action.on)
            is AiAction.SetTicketApplication -> marks.setTicketApplication(action.saleId, action.application)
            is AiAction.SetMastery -> marks.setMastery(action.songIds, action.level.coerceAtMost(255u).toUByte())
            is AiAction.AddToCalendar -> addToCalendar(action.showId)
            is AiAction.SetNotification -> setNotification(action.kind, action.on)
            is AiAction.OpenList -> {
                val tab = when (action.list) {
                    "events" -> TopLevelTab.Events
                    "songs" -> TopLevelTab.Songs
                    "idols" -> TopLevelTab.Idols
                    else -> throw Failure("開く先が見つかりませんでした")
                }
                CrossTabSearch.hand(action.query, tab)
                return Opened.List
            }
            is AiAction.SetProducerCard -> {
                cardEditor.apply(action.edit, images)
                // 直した結果をその場で見せる。
                return Opened.Screen(AssistantScreen.ProducerCard)
            }
            is AiAction.OpenScreen -> {
                val screen = AssistantScreen.fromKey(action.screen) ?: throw Failure("開く先が見つかりませんでした")
                return Opened.Screen(screen)
            }
            is AiAction.PredictSong ->
                if (action.on) predictions.vote(action.showId, action.songId) else predictions.unvote(action.showId, action.songId)
            is AiAction.LikeSetlistSong ->
                if (action.on) likes.like(action.showId, action.songId) else likes.unlike(action.showId, action.songId)
        }
        return null
    }

    /** カレンダーアプリの「予定を追加」画面を開く (権限は要らない。保存は利用者がそちらで押す)。 */
    private suspend fun addToCalendar(showId: String) {
        val show = events.fetchShowInfo(showId)?.show ?: throw Failure("公演が見つかりませんでした")
        val event = events.fetchEvent(show.eventId) ?: throw Failure("公演が見つかりませんでした")
        val row = CalShowRow(show.id, show.date, show.name, event.id, event.name, event.brandId)
        val detail = CalendarShowDetail(show.startTime, show.venue, null)
        if (!DeviceCalendar.addShow(context, row, detail)) throw Failure("カレンダーアプリが見つかりませんでした")
    }

    /** 保存先と組み直しは設定画面のトグルと同じ。オフにしたときの理由も同じ。 */
    private suspend fun setNotification(kind: String, on: Boolean) {
        val category = NotificationCategory.entries.firstOrNull { it.prefKey == "notif_$kind" }
            ?: throw Failure("この通知は設定できません")
        NotificationPrefs(context).setEnabled(category, on)
        val reason = if (on) NotificationScheduler.RescheduleReason.REFRESH
        else NotificationScheduler.RescheduleReason.SETTING_TURNED_OFF
        NotificationScheduler.rescheduleAll(context, reason)
    }

    /** 札の付け外し。今の状態と違うときだけ反転する (トグルの口しか無いため)。 */
    private suspend fun setOnOff(type: String, id: String, kind: String, on: Boolean) {
        if (marks.isOn(type, id, kind) != on) marks.toggle(type, id, kind)
    }

    private suspend fun orderedSongs(ids: List<String>): List<Song> {
        val byId = songs.fetchSongsByIds(ids).associateBy { it.id }
        return ids.mapNotNull { byId[it] }
    }

    private fun destination(entity: String, id: String): NaturalSearchTarget {
        val kind = when (entity) {
            "song" -> NaturalSearchKind.SONG
            "idol" -> NaturalSearchKind.IDOL
            "event" -> NaturalSearchKind.EVENT
            "show" -> NaturalSearchKind.SHOW
            "unit" -> NaturalSearchKind.UNIT
            else -> throw Failure("開く先が見つかりませんでした")
        }
        return NaturalSearchTarget(kind, id)
    }

    private companion object {
        val NOTE_ENTITIES = setOf(UserMark.SONG, UserMark.IDOL, UserMark.EVENT, UserMark.SHOW)
    }
}

/**
 * `open_screen` で開ける画面。key はコアのキー (`ai_actions::SCREENS`)。iOS `AssistantExecutor.Screen`。
 *
 * Android には「自分のセトリ予想」の画面が無いので、`my_predictions` は含めない (開く先が見つからない失敗になる)。
 */
enum class AssistantScreen(val key: String) {
    ProducerCard("producer_card"),
    CardCase("card_case"),
    Ledger("ledger"),
    Playlists("playlists"),
    Mastery("mastery"),
    Favorites("favorites"),
    MyVotes("my_votes"),
    MyContributions("my_contributions");

    companion object {
        fun fromKey(key: String): AssistantScreen? = entries.firstOrNull { it.key == key }
    }
}
