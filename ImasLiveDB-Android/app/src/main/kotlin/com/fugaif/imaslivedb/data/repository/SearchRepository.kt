package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.SearchResults

class SearchRepository(private val db: AppDatabase) {

    suspend fun search(query: String): SearchResults {
        val pattern = "%$query%"
        return SearchResults(
            songs = db.searchDao().searchSongs(pattern),
            idols = db.searchDao().searchIdols(pattern),
            events = db.searchDao().searchEvents(pattern)
        )
    }
}
