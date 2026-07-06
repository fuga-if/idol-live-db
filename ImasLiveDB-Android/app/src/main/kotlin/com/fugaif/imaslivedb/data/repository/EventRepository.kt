package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.AllPerformerRow
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.EventCastRow
import com.fugaif.imaslivedb.data.model.EventStats
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.SetlistItem
import com.fugaif.imaslivedb.data.model.SetlistPerformer
import com.fugaif.imaslivedb.data.model.SetlistRow
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.ShowWithEventName

class EventRepository(private val db: AppDatabase) {

    suspend fun fetchEvents(brandId: String? = null): List<Event> {
        return if (brandId != null) {
            db.eventDao().fetchEventsByBrand(brandId)
        } else {
            db.eventDao().fetchEvents()
        }
    }

    suspend fun fetchEventsWithFirstDate(): List<EventWithDateRange> {
        return db.eventDao().fetchEventsWithFirstDate().map { it.toEventWithDateRange() }
    }

    suspend fun fetchEventStats(eventId: String): EventStats {
        return db.eventDao().fetchEventStats(eventId)
    }

    suspend fun fetchEventCastMembers(eventId: String): List<EventCastRow> {
        return db.eventDao().fetchEventCastMembers(eventId)
    }

    suspend fun fetchShows(eventId: String): List<Show> {
        return db.showDao().fetchShows(eventId)
    }

    suspend fun fetchEvent(id: String): Event? {
        return db.eventDao().fetchEvent(id)
    }

    suspend fun fetchShow(id: String): Show? {
        return db.showDao().fetchShow(id)
    }

    suspend fun fetchLatestShow(): Show? {
        return db.showDao().fetchLatestShow()
    }

    /** オープン編集「セトリ編集」の対象公演を選ぶピッカー用。 */
    suspend fun searchShows(query: String, limit: Int = 30): List<ShowWithEventName> {
        val trimmed = query.trim()
        return if (trimmed.isEmpty()) {
            db.showDao().fetchRecentShowsWithEventName(limit)
        } else {
            db.showDao().searchShowsWithEventName("%$trimmed%", limit)
        }
    }

    suspend fun fetchSetlist(showId: String): List<SetlistRow> {
        return db.setlistDao().fetchSetlist(showId)
    }

    suspend fun fetchAllPerformers(showId: String): List<AllPerformerRow> {
        return db.setlistDao().fetchAllPerformers(showId)
    }

    /**
     * セトリ編集の保存後、サーバ確定値でローカル DB を全置換する (iOS `showWriting.replaceSetlist` と同じ)。
     * ローカル反映は admin が直接反映 (POST /edits) できた場合のみ呼ばれる想定。
     */
    suspend fun replaceSetlist(
        deletedItemIds: List<String>,
        deletedPerformers: List<Pair<String, String>>,
        items: List<SetlistItem>,
        performers: List<SetlistPerformer>
    ) {
        if (deletedItemIds.isNotEmpty()) db.setlistDao().deleteItems(deletedItemIds)
        for ((itemId, idolId) in deletedPerformers) db.setlistDao().deletePerformer(itemId, idolId)
        if (items.isNotEmpty()) db.setlistDao().upsertItems(items)
        if (performers.isNotEmpty()) db.setlistDao().upsertPerformers(performers)
    }
}
