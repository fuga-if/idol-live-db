package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.UserMark
import java.time.Instant

/** 担当/お気に入り等のユーザーマークを管理 (端末ローカル)。 */
class UserMarkRepository(private val db: AppDatabase) {

    private val dao get() = db.userMarkDao()

    suspend fun isOn(type: String, id: String, kind: String): Boolean = dao.isOn(type, id, kind)

    /** ON/OFF をトグルして新しい状態を返す。 */
    suspend fun toggle(type: String, id: String, kind: String): Boolean {
        val now = !dao.isOn(type, id, kind)
        if (now) {
            dao.upsert(UserMark(type, id, kind, true, null, Instant.now().toString()))
        } else {
            dao.delete(type, id, kind)
        }
        return now
    }

    /** 担当アイドル一覧。 */
    suspend fun pickedIdols(): List<Idol> =
        db.songDao().let { _ -> fetchIdols(dao.idsFor(UserMark.IDOL, UserMark.PICK)) }

    /** お気に入りアイドル一覧。 */
    suspend fun favoriteIdols(): List<Idol> =
        fetchIdols(dao.idsFor(UserMark.IDOL, UserMark.FAVORITE))

    /** お気に入り曲一覧。 */
    suspend fun favoriteSongs(): List<Song> =
        db.songDao().let { sdao ->
            val ids = dao.idsFor(UserMark.SONG, UserMark.FAVORITE)
            ids.mapNotNull { sdao.fetchSong(it) }
        }

    /** お気に入りライブ(イベント)一覧。開催日降順。 */
    suspend fun favoriteEvents(): List<EventWithDateRange> {
        val ids = dao.idsFor(UserMark.EVENT, UserMark.FAVORITE)
        if (ids.isEmpty()) return emptyList()
        return db.eventDao().fetchEventsWithDateRangeByIds(ids).map { it.toEventWithDateRange() }
    }

    /**
     * 参加したライブ(イベント)を重複なしで開催日降順に返す。
     * イベント単位/公演単位どちらの参加マークも拾う (UNION は EventDao 側)。
     */
    suspend fun attendedEvents(): List<EventWithDateRange> =
        db.eventDao().fetchAttendedEventsWithDateRange().map { it.toEventWithDateRange() }

    /**
     * 参加したイベントを「現地参加を含む」「配信参加を含む」「LV参加を含む」の集合に分類して返す。
     * 1イベント内で現地公演と配信公演が混在する場合は両方に入る。種別なし(旧データ)は現地扱い。
     */
    suspend fun attendedEventTypeSets(): AttendedEventTypeSets {
        val live = mutableSetOf<String>()
        val stream = mutableSetOf<String>()
        val liveViewing = mutableSetOf<String>()
        db.eventDao().fetchAttendedEventTypeRows().forEach { row ->
            when (row.atype) {
                "stream" -> stream.add(row.eventId)
                "live_viewing" -> liveViewing.add(row.eventId)
                else -> live.add(row.eventId)
            }
        }
        return AttendedEventTypeSets(live, stream, liveViewing)
    }

    private suspend fun fetchIdols(ids: List<String>): List<Idol> {
        val idao = db.idolDao()
        return ids.mapNotNull { idao.fetchIdol(it) }
    }
}

data class AttendedEventTypeSets(
    val live: Set<String>,
    val stream: Set<String>,
    val liveViewing: Set<String>
)
