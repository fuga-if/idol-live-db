package com.fugaif.imaslivedb.di

import android.content.Context
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.repository.EventRepository
import com.fugaif.imaslivedb.data.repository.IdolRepository
import com.fugaif.imaslivedb.data.repository.SearchRepository
import com.fugaif.imaslivedb.data.repository.SongRepository
import com.fugaif.imaslivedb.data.repository.StatsRepository
import com.fugaif.imaslivedb.data.repository.UserMarkRepository
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.sync.CloudKitSyncEngine

/**
 * Manual DI container. Obtain via AppModule.from(context).
 * All instances are singletons scoped to the Application.
 */
class AppModule private constructor(context: Context) {

    private val appContext: Context = context.applicationContext
    val database: AppDatabase = AppDatabase.getInstance(context)

    val eventRepository: EventRepository by lazy { EventRepository(database) }
    val songRepository: SongRepository by lazy { SongRepository(database) }
    val idolRepository: IdolRepository by lazy { IdolRepository(database) }
    val statsRepository: StatsRepository by lazy { StatsRepository(database) }
    val searchRepository: SearchRepository by lazy { SearchRepository(database) }
    val userMarkRepository: UserMarkRepository by lazy { UserMarkRepository(database) }
    val communityApi: CommunityApi by lazy { CommunityApi(appContext) }
    val syncEngine: CloudKitSyncEngine by lazy { CloudKitSyncEngine(appContext, database) }

    companion object {
        @Volatile
        private var instance: AppModule? = null

        fun from(context: Context): AppModule {
            return instance ?: synchronized(this) {
                instance ?: AppModule(context.applicationContext).also { instance = it }
            }
        }
    }
}
