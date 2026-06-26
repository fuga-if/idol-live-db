package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.EventCastRow
import com.fugaif.imaslivedb.data.model.EventStats
import com.fugaif.imaslivedb.data.model.EventWithDate
import com.fugaif.imaslivedb.data.model.Show

class EventRepository(private val db: AppDatabase) {

    suspend fun fetchEvents(brandId: String? = null): List<Event> {
        return if (brandId != null) {
            db.eventDao().fetchEventsByBrand(brandId)
        } else {
            db.eventDao().fetchEvents()
        }
    }

    suspend fun fetchEventsWithFirstDate(brandId: String? = null): List<EventWithDate> {
        val rows = if (brandId != null) {
            db.eventDao().fetchEventsWithFirstDateByBrand(brandId)
        } else {
            db.eventDao().fetchEventsWithFirstDate()
        }
        return rows.map { it.toEventWithDate() }
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
}
