package com.fugaif.imaslivedb.di

import android.content.Context
import android.util.Log
import com.fugaif.imaslivedb.data.auth.AuthService
import com.fugaif.imaslivedb.data.backup.BackupTransferApi
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.core.VoiceActorDirectory
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.db.DatabaseBoot
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.image.BulkImageImporter
import com.fugaif.imaslivedb.data.image.CustomImageStore
import com.fugaif.imaslivedb.data.repository.CalendarRepository
import com.fugaif.imaslivedb.data.repository.EditFeedRepository
import com.fugaif.imaslivedb.data.repository.EventRepository
import com.fugaif.imaslivedb.data.repository.ExpenseRepository
import com.fugaif.imaslivedb.data.repository.IdolRepository
import com.fugaif.imaslivedb.data.repository.MasterEditRepository
import com.fugaif.imaslivedb.data.repository.PerformanceEvidenceRepository
import com.fugaif.imaslivedb.data.repository.PersonalTagRepository
import com.fugaif.imaslivedb.data.repository.CoreSetlistForecastRepository
import com.fugaif.imaslivedb.data.repository.PredictionServiceVoting
import com.fugaif.imaslivedb.data.repository.SearchRepository
import com.fugaif.imaslivedb.data.repository.SetlistForecastReading
import com.fugaif.imaslivedb.data.repository.SetlistPredictionVoting
import com.fugaif.imaslivedb.data.repository.ShowTicketRepository
import com.fugaif.imaslivedb.data.repository.SongRepository
import com.fugaif.imaslivedb.data.repository.StatsRepository
import com.fugaif.imaslivedb.data.repository.UnitRepository
import com.fugaif.imaslivedb.data.repository.UserMarkRepository
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.community.DiscordLinkService
import com.fugaif.imaslivedb.data.community.FavoriteAggregation
import com.fugaif.imaslivedb.data.community.LocalContributionLog
import com.fugaif.imaslivedb.data.community.LocalPollVoteLog
import com.fugaif.imaslivedb.data.community.SetlistLikeService
import com.fugaif.imaslivedb.data.community.SetlistPredictionService
import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import com.fugaif.imaslivedb.data.games.GameProgressStore
import com.fugaif.imaslivedb.data.games.QuizResumeStore
import com.fugaif.imaslivedb.data.sync.CloudKitSyncEngine
import com.fugaif.imaslivedb.ui.theme.BrandColors
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.withContext

/**
 * Manual DI container. Obtain via AppModule.from(context).
 * All instances are singletons scoped to the Application.
 */
class AppModule private constructor(context: Context) {

    private val appContext: Context = context.applicationContext
    val database: AppDatabase = AppDatabase.getInstance(context)

    /** 起動時に DB を開く流れ。開けるまで画面は DB を読まない (開けなければ復旧画面)。 */
    val databaseBoot: DatabaseBoot = DatabaseBoot {
        withContext(Dispatchers.IO) { database.openHelper.writableDatabase }
    }

    /**
     * プロセス寿命の処理用 (画面を離れても止まらない)。個々の失敗が他を巻き込まないよう
     * SupervisorJob、捕まえ損ねた例外でプロセスごと落とさないようハンドラで受けて記録だけする。
     */
    val appScope: CoroutineScope = CoroutineScope(
        SupervisorJob() + Dispatchers.IO +
            CoroutineExceptionHandler { _, e -> Log.e(TAG, "バックグラウンドの処理が失敗", e) }
    )

    /**
     * 共有コア (imas-core) のインメモリスナップショット。読み取り系リポジトリの第一経路。
     * Application.onCreate の start() で起動時 load + sync 完了ごとの reload が始まる。
     */
    val snapshotStoreProvider: SnapshotStoreProvider by lazy {
        SnapshotStoreProvider(appContext, syncEngine).also { provider ->
            // ブランドの色は描画から同期で引く (読めていなければ null = ニュートラル)。
            BrandColors.install {
                provider.currentGeneration()?.let { (generation, store) ->
                    runCatching { store.brandRecords() }.getOrNull()?.let { generation to it }
                }
            }
            // 現任の声優も同じく描画から同期で引く (声優の履歴 idol_voice_actors が正)。
            VoiceActorDirectory.install { provider.currentGeneration() }
        }
    }

    val eventRepository: EventRepository by lazy { EventRepository(database, snapshotStoreProvider) }
    val calendarRepository: CalendarRepository by lazy { CalendarRepository(database, snapshotStoreProvider) }
    val songRepository: SongRepository by lazy { SongRepository(database, snapshotStoreProvider) }
    val idolRepository: IdolRepository by lazy { IdolRepository(database, snapshotStoreProvider) }
    val unitRepository: UnitRepository by lazy { UnitRepository(database, snapshotStoreProvider) }
    val statsRepository: StatsRepository by lazy { StatsRepository(database, communityApi, snapshotStoreProvider) }
    val searchRepository: SearchRepository by lazy { SearchRepository(snapshotStoreProvider) }
    // 曲詳細の披露実績 (共起曲 / 歌唱者)。集計はコアのスナップショットが答える。
    val performanceEvidenceRepository: PerformanceEvidenceRepository by lazy {
        PerformanceEvidenceRepository(database, snapshotStoreProvider)
    }
    /** ユーザーが端末に取り込んだアイドル/ユニット/ブランド画像。filesDir 配下でウィジェットと共有する。 */
    val customImageStore: CustomImageStore by lazy { CustomImageStore(appContext) }
    /** 画像の一括インポート。進捗を画面をまたいで持つため、アプリで 1 つ。 */
    val bulkImageImporter: BulkImageImporter by lazy {
        BulkImageImporter(
            store = customImageStore,
            idolRepository = idolRepository,
            statsRepository = statsRepository,
            snapshots = snapshotStoreProvider,
        )
    }
    val userMarkRepository: UserMarkRepository by lazy {
        UserMarkRepository(database, onSongFavoriteChanged = favoriteAggregation::report)
    }
    /** 曲のお気に入りをみんなの集計に送る (失敗は端末に積んで送り直す)。 */
    val favoriteAggregation: FavoriteAggregation by lazy {
        FavoriteAggregation(appContext, appScope, send = communityApi::toggleFavorite)
    }
    val personalTagRepository: PersonalTagRepository by lazy { PersonalTagRepository(database) }
    val expenseRepository: ExpenseRepository by lazy { ExpenseRepository(database) }
    val showTicketRepository: ShowTicketRepository by lazy { ShowTicketRepository(database) }
    val authService: AuthService by lazy { AuthService(appContext) }
    /** Worker (imas-live-api) への HTTP。セッションはリクエストの時点の値を付ける。 */
    val workerHttpClient: WorkerHttpClient by lazy { WorkerHttpClient(appContext, { authService.sessionToken }, renewer = authService) }
    val communityApi: CommunityApi by lazy { CommunityApi(workerHttpClient) }
    val editApi: EditApi by lazy { EditApi(workerHttpClient, authService) }
    val setlistLikeService: SetlistLikeService by lazy { SetlistLikeService(workerHttpClient) }
    /** Discord のロール受け取り (認可 URL の発行)。 */
    val discordLinkService: DiscordLinkService by lazy { DiscordLinkService(workerHttpClient) }
    /** セトリ予想 (みんなの予想)。覚え書きを画面をまたいで共有するため、アプリで 1 つ。 */
    val setlistPredictionService: SetlistPredictionService by lazy { SetlistPredictionService(workerHttpClient) }
    /** セトリ予想への投票 (機械予測の「予想に入れる」が使う)。 */
    val setlistPredictionVoting: SetlistPredictionVoting by lazy { PredictionServiceVoting(setlistPredictionService) }
    /** セトリの機械予測。点数も理由もコアのスナップショットが答える。 */
    val setlistForecastReading: SetlistForecastReading by lazy { CoreSetlistForecastRepository(snapshotStoreProvider) }
    val editFeedRepository: EditFeedRepository by lazy { EditFeedRepository(snapshotStoreProvider) }
    val masterEditRepository: MasterEditRepository by lazy { MasterEditRepository(database, snapshotStoreProvider) }
    val syncEngine: CloudKitSyncEngine by lazy { CloudKitSyncEngine(appContext, database, scope = appScope) }
    val localContributionLog: LocalContributionLog by lazy { LocalContributionLog(appContext) }
    val localPollVoteLog: LocalPollVoteLog by lazy { LocalPollVoteLog(appContext) }
    val gameProgressStore: GameProgressStore by lazy { GameProgressStore(appContext) }
    val quizResumeStore: QuizResumeStore by lazy { QuizResumeStore(appContext) }
    val backupTransferApi: BackupTransferApi by lazy { BackupTransferApi(workerHttpClient) }

    companion object {
        private const val TAG = "AppModule"

        @Volatile
        private var instance: AppModule? = null

        fun from(context: Context): AppModule {
            return instance ?: synchronized(this) {
                instance ?: AppModule(context.applicationContext).also { instance = it }
            }
        }
    }
}
