package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.db.AppDatabase

/**
 * 編集フィード (`GET /edits`) の対象レコードをローカル DB から解決する。iOS `editFeedReading` の簡易移植。
 * 詳細画面への遷移は持たず、可読タイトルの解決のみを担う (このタスクでは各詳細画面を触らない制約のため)。
 *
 * 名前の解決は共有コア (imas-core) のスナップショットを第一経路にする。スナップショットが
 * ひと世代古いと「編集されたばかりのレコード」を引けないことがあるが、その場合は
 * コアが null を返して Room 経路が引き直すので、フィードの表示は落ちない。
 */
class EditFeedRepository(
    private val db: AppDatabase,
    // null = スナップショット経路なし (テスト等)。その場合は常に SQL 経路。
    private val snapshots: SnapshotStoreProvider? = null
) {

    /** recordType / recordName から人間可読なタイトルを解決する。解決できなければ null。 */
    suspend fun recordTitle(recordType: String, recordName: String): String? {
        return when (recordType) {
            "Song" -> songTitle(recordName)
            "Idol" -> idolName(recordName)
            "Event" -> eventName(recordName)
            "Show" -> showTitle(recordName)
            // ShowSetlist (セトリの show 単位スナップショット) は record_name = showId。
            "ShowSetlist" -> showTitle(recordName)
            // SetlistItem は showId 経由で公演タイトルへ解決する。コアは show → セトリ項目の
            // 向きしか持たず (setlist_item_id からの逆引き API が無い) ここは SQL 経路のまま。
            "SetlistItem" -> db.setlistDao().fetchShowIdForItem(recordName)?.let { showTitle(it) }
            else -> null
        }
    }

    private suspend fun songTitle(songId: String): String? {
        snapshots?.query { store -> store.songRecordsByIds(listOf(songId)).firstOrNull()?.title }
            ?.let { return it }
        return db.songDao().fetchSong(songId)?.title
    }

    private suspend fun idolName(idolId: String): String? {
        snapshots?.query { store -> store.idolRecordsByIds(listOf(idolId)).firstOrNull()?.name }
            ?.let { return it }
        return db.idolDao().fetchIdol(idolId)?.name
    }

    private suspend fun eventName(eventId: String): String? {
        snapshots?.query { store -> store.eventRecord(eventId)?.name }?.let { return it }
        return db.eventDao().fetchEvent(eventId)?.name
    }

    private suspend fun showTitle(showId: String): String? {
        // 公演名と親イベント名の 2 段引き。1 表示 = provider.query 1 回に収める。
        val fromCore = snapshots?.query { store ->
            val show = store.showRecord(showId) ?: return@query null
            joinTitle(eventName = store.eventRecord(show.eventId)?.name, showName = show.name)
        }
        if (fromCore != null) return fromCore

        val show = db.showDao().fetchShow(showId) ?: return null
        return joinTitle(eventName = db.eventDao().fetchEvent(show.eventId)?.name, showName = show.name)
    }

    /** 「イベント名 公演名」。公演名がイベント名と同じ/空なら重ねない。 */
    private fun joinTitle(eventName: String?, showName: String): String? {
        val parts = listOfNotNull(eventName, showName.takeIf { it.isNotBlank() && it != eventName })
        return parts.joinToString(" ").ifEmpty { null }
    }
}
