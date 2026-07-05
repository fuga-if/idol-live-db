package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase

/**
 * 編集フィード (`GET /edits`) の対象レコードをローカル DB から解決する。iOS `editFeedReading` の簡易移植。
 * 詳細画面への遷移は持たず、可読タイトルの解決のみを担う (このタスクでは各詳細画面を触らない制約のため)。
 */
class EditFeedRepository(private val db: AppDatabase) {

    /** recordType / recordName から人間可読なタイトルを解決する。解決できなければ null。 */
    suspend fun recordTitle(recordType: String, recordName: String): String? {
        return when (recordType) {
            "Song" -> db.songDao().fetchSong(recordName)?.title
            "Idol" -> db.idolDao().fetchIdol(recordName)?.name
            "Event" -> db.eventDao().fetchEvent(recordName)?.name
            "Show" -> showTitle(recordName)
            // ShowSetlist (セトリの show 単位スナップショット) は record_name = showId。
            "ShowSetlist" -> showTitle(recordName)
            // SetlistItem は showId 経由で公演タイトルへ解決する。
            "SetlistItem" -> db.setlistDao().fetchShowIdForItem(recordName)?.let { showTitle(it) }
            else -> null
        }
    }

    private suspend fun showTitle(showId: String): String? {
        val show = db.showDao().fetchShow(showId) ?: return null
        val event = db.eventDao().fetchEvent(show.eventId)
        val parts = listOfNotNull(event?.name, show.name.takeIf { it.isNotBlank() && it != event?.name })
        return parts.joinToString(" ").ifEmpty { null }
    }
}
