package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.AttendanceType
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.UserMark
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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

    /**
     * 参加形態を返す (未参加は null)。種別が入っていない旧データは現地扱い。
     * 参加は公演 (show) 単位で持つのが正で、イベント単位のマークは旧データの互換のみ。
     */
    suspend fun attendance(type: String, id: String): AttendanceType? {
        if (!dao.isOn(type, id, UserMark.ATTENDED)) return null
        return AttendanceType.from(dao.textValue(type, id, UserMark.ATTENDED)) ?: AttendanceType.LIVE
    }

    /** 参加形態を設定する。null で不参加に戻す。 */
    suspend fun setAttendance(type: String, id: String, value: AttendanceType?) {
        if (value == null) {
            dao.delete(type, id, UserMark.ATTENDED)
        } else {
            dao.upsert(UserMark(type, id, UserMark.ATTENDED, true, value.raw, Instant.now().toString()))
        }
    }

    /**
     * メモ本文 (未入力は null)。空白だけの保存は「無い」と同じ扱いにする
     * (空文字が残ると UI の「メモあり」判定が立ちっぱなしになるため)。
     */
    suspend fun note(type: String, id: String): String? =
        dao.memo(type, id)?.takeIf { it.isNotBlank() }

    /** メモを保存する。null / 空白のみ なら行ごと削除して「メモなし」に戻す。 */
    suspend fun setNote(type: String, id: String, text: String?) =
        setText(type, id, UserMark.MEMO, text)

    /** 座席メモ (未入力は null)。 */
    suspend fun seat(type: String, id: String): String? =
        dao.textValue(type, id, SEAT)?.takeIf { it.isNotBlank() }

    /** 座席メモを保存する。null / 空白のみ なら行ごと削除。 */
    suspend fun setSeat(type: String, id: String, text: String?) =
        setText(type, id, SEAT, text)

    /**
     * text_value を持つマークの共通の書き込み口。
     *
     * `bool_value` は必ず true で入れる。読み出しに使う [UserMarkDao.textValue] が
     * `bool_value = 1` を条件にしているので、false で入れると書いた値が二度と読めない。
     */
    private suspend fun setText(type: String, id: String, kind: String, text: String?) {
        val trimmed = text?.trim()
        if (trimmed.isNullOrEmpty()) {
            dao.delete(type, id, kind)
        } else {
            dao.upsert(UserMark(type, id, kind, true, trimmed, Instant.now().toString()))
        }
    }

    /** 与えた公演のうち参加マークが付いているものの id。 */
    suspend fun attendedShowIds(showIds: List<String>): Set<String> =
        if (showIds.isEmpty()) emptySet()
        else dao.onIdsIn(UserMark.SHOW, UserMark.ATTENDED, showIds).toSet()

    /** 担当アイドル一覧。 */
    suspend fun pickedIdols(): List<Idol> =
        db.songDao().let { _ -> fetchIdols(dao.idsFor(UserMark.IDOL, UserMark.PICK)) }

    /** 担当アイドルの ID セット (回収ダッシュボードの担当スコープ絞り込み用)。 */
    suspend fun pickedIdolIds(): Set<String> = dao.idsFor(UserMark.IDOL, UserMark.PICK).toSet()

    /** お気に入りアイドルの ID セット。 */
    suspend fun favoriteIdolIds(): Set<String> = dao.idsFor(UserMark.IDOL, UserMark.FAVORITE).toSet()

    /** メモがあるアイドルの ID セット。 */
    suspend fun notedIdolIds(): Set<String> = dao.idsWithNote(UserMark.IDOL).toSet()

    /**
     * 回収に配信参加も含めるか (既定 = 現地参加のみ)。地方勢など配信中心の人向けの設定。
     *
     * 設定の保存先 ([com.fugaif.imaslivedb.ui.theme.AppPreferences]) は Context を要るので、
     * リポジトリから読みに行かず**押し込んでもらう**。逆向き (data → ui) の依存を作らずに
     * 済ませるための向きで、押し込みは設定の読み込み時と変更時の 2 箇所。
     */
    @Volatile
    var includeStreamInCollection: Boolean = false

    /**
     * attended ライブのセトリから自動判定した「回収済み」song_id セット (回収ダッシュボード用)。
     *
     * 現地のみ (既定) は Room の DAO をそのまま使う。配信を含める場合だけ、参加種別の条件を
     * 外した同じ SQL を直接引く — 条件が SQL の WHERE 句にある以上、Kotlin 側で後から
     * 足し引きできないため。DAO に 2 本目を生やせない事情での分岐なので、SQL は
     * [com.fugaif.imaslivedb.data.db.dao.StatsDao.fetchAutoCollectedSongIds] の写しを保つこと。
     */
    suspend fun autoCollectedSongIds(): Set<String> {
        if (!includeStreamInCollection) return db.statsDao().fetchAutoCollectedSongIds().toSet()
        return withContext(Dispatchers.IO) {
            val ids = mutableSetOf<String>()
            // Room の生クエリは呼び出し元スレッドで走る (suspend DAO と違いディスパッチされない)。
            db.query(SQL_AUTO_COLLECTED_ANY_ATTENDANCE, null).use { cursor ->
                while (cursor.moveToNext()) ids.add(cursor.getString(0))
            }
            ids
        }
    }

    /**
     * 参加種別を問わない版の自動回収クエリ (現地・配信・LV すべて回収に数える)。
     * DAO 版との違いは公演マークの `text_value` 条件を落とした 1 点だけで、
     * 対象を「リアルライブ (live/festival)」に絞るところは同じ。
     */
    private val SQL_AUTO_COLLECTED_ANY_ATTENDANCE = """
        SELECT DISTINCT si.song_id
        FROM setlist_items si
        JOIN shows sh ON si.show_id = sh.id
        JOIN events e ON e.id = sh.event_id
        WHERE e.kind IN ('live','festival')
        AND (
            sh.id IN (
                SELECT entity_id FROM user_marks
                WHERE entity_type='show' AND kind='attended' AND bool_value=1
            )
            OR sh.event_id IN (
                SELECT entity_id FROM user_marks
                WHERE entity_type='event' AND kind='attended' AND bool_value=1
            )
        )
    """

    /** お気に入りアイドル一覧。 */
    suspend fun favoriteIdols(): List<Idol> =
        fetchIdols(dao.idsFor(UserMark.IDOL, UserMark.FAVORITE))

    /** お気に入り曲一覧。 */
    suspend fun favoriteSongs(): List<Song> =
        db.songDao().let { sdao ->
            val ids = dao.idsFor(UserMark.SONG, UserMark.FAVORITE)
            ids.mapNotNull { sdao.fetchSong(it) }
        }

    /** お気に入り曲 ID セット (曲一覧行アイコン/絞り込み用の軽量版)。 */
    suspend fun favoriteSongIds(): Set<String> = dao.idsFor(UserMark.SONG, UserMark.FAVORITE).toSet()

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

    /** バックアップエクスポート用の全件取得。 */
    suspend fun getAll(): List<UserMark> = dao.getAll()

    /**
     * バックアップからの復元 (非破壊): ローカルに無い (entityType, entityId, kind) の組だけ追加する。
     * 既存のマークは一切上書きしない。
     */
    suspend fun restoreIfAbsent(marks: List<UserMark>): Int {
        val existingKeys = dao.getAll().map { Triple(it.entityType, it.entityId, it.kind) }.toSet()
        val toInsert = marks.filter { Triple(it.entityType, it.entityId, it.kind) !in existingKeys }
        if (toInsert.isNotEmpty()) dao.insertAll(toInsert)
        return toInsert.size
    }

    companion object {
        /**
         * 座席メモの kind (iOS `UserMarkKind.seat` と同じ生値)。
         *
         * `UserMark` の定数群には無いので、ここをマークの意味の持ち主として正本にする。
         * 画面側で "seat" を直接書かないこと (綴りがズレると別のマークになる)。
         */
        const val SEAT = "seat"
    }
}

data class AttendedEventTypeSets(
    val live: Set<String>,
    val stream: Set<String>,
    val liveViewing: Set<String>
)
