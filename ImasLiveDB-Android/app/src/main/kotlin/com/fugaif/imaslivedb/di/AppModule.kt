package com.fugaif.imaslivedb.di

import android.content.Context
import com.fugaif.imaslivedb.data.auth.AuthService
import com.fugaif.imaslivedb.data.backup.BackupTransferApi
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.repository.EditFeedRepository
import com.fugaif.imaslivedb.data.repository.EventRepository
import com.fugaif.imaslivedb.data.repository.IdolRepository
import com.fugaif.imaslivedb.data.repository.PersonalTagRepository
import com.fugaif.imaslivedb.data.repository.SearchRepository
import com.fugaif.imaslivedb.data.repository.SongRepository
import com.fugaif.imaslivedb.data.repository.StatsRepository
import com.fugaif.imaslivedb.data.repository.UserMarkRepository
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.community.LocalContributionLog
import com.fugaif.imaslivedb.data.community.LocalPollVoteLog
import com.fugaif.imaslivedb.data.games.GameProgressStore
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
    val statsRepository: StatsRepository by lazy { StatsRepository(database, communityApi) }
    val searchRepository: SearchRepository by lazy { SearchRepository(database) }
    val userMarkRepository: UserMarkRepository by lazy { UserMarkRepository(database) }
    val personalTagRepository: PersonalTagRepository by lazy { PersonalTagRepository(database) }
    val authService: AuthService by lazy { AuthService(appContext) }
    val communityApi: CommunityApi by lazy { CommunityApi(appContext, authService) }
    val editApi: EditApi by lazy { EditApi(appContext, authService) }
    val editFeedRepository: EditFeedRepository by lazy { EditFeedRepository(database) }
    val syncEngine: CloudKitSyncEngine by lazy { CloudKitSyncEngine(appContext, database) }
    val localContributionLog: LocalContributionLog by lazy { LocalContributionLog(appContext) }
    val localPollVoteLog: LocalPollVoteLog by lazy { LocalPollVoteLog(appContext) }
    val gameProgressStore: GameProgressStore by lazy { GameProgressStore(appContext) }
    val backupTransferApi: BackupTransferApi by lazy { BackupTransferApi(appContext, authService) }

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
