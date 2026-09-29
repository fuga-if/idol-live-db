package com.fugaif.imaslivedb.data.core

import android.content.Context
import android.util.Log
import com.fugaif.imaslivedb.data.sync.CloudKitSyncEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean
import uniffi.imas_core.SnapshotException
import uniffi.imas_core.SnapshotStore

/** スナップショットを読み込めなかった (DB がまだ無い・読み込みに失敗した)。 */
class SnapshotUnavailableException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * 共有コア (imas-core) のインメモリスナップショットをアプリで単一保持するプロバイダ。
 *
 * マスタの読み取りはすべてスナップショットが答える (OS 側の SQL の代わりの経路は持たない。
 * 同じ問いに 2 つの実装が答えると、規則が必ず食い違う。iOS と同じ)。
 * - まだ読み込めていない間の読み取り ([query]) は、読み込みを待つ。失敗したら
 *   [SnapshotUnavailableException] を投げ、次の読み取りでもう一度読み込む。
 * - CloudKit 差分同期の完了 (SyncState.Completed) と、seed の投入・入れ直しのたびに読み直し、
 *   新スナップショットへ原子的に差し替える (core 側 SnapshotStore の規約。失敗したら前のものが残る)。
 *   一度読み込めたら手放さない。
 * - **user_marks (担当/お気に入り/メモ/回収) はスナップショットに含まれない**。
 *   参加マーク等のユーザーデータは Room が正で、必要な id 集合は各リポジトリが
 *   解決してクエリ引数で渡す。
 */
class SnapshotStoreProvider(
    context: Context,
    private val syncEngine: CloudKitSyncEngine
) {
    private val appContext = context.applicationContext

    // Application と同寿命のシングルトンなので cancel 経路は持たない (プロセス終了で消える)。
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // load は DB 全読みで数百 ms かかり得る。多重 reload (起動 load と sync 完了 reload の
    // 競合等) を直列化して「後勝ちで古い方が新しい方を上書く」逆転を防ぐ。
    private val reloadMutex = Mutex()

    private val store = SnapshotStore()

    private val started = AtomicBoolean(false)

    /** 直近の読み込みの失敗 (読み取りが投げる例外の原因)。 */
    @Volatile private var lastLoadFailure: Throwable? = null

    /** 読み込みが成功するたびに 1 つ進む。描画の同期経路の覚え書きを捨てる合図 ([currentGeneration])。 */
    @Volatile private var generation = 0L

    /**
     * 同期の完了・seed の入れ直しで読み直す購読を始める。何度呼んでも始めるのは 1 回だけ。
     * 最初の読み込みはここではせず、最初の読み取り ([loadedStore]) が行う (ウィジェットや
     * 通知だけのプロセスでは、読むときまで読み込まない)。
     */
    fun start() {
        if (!started.compareAndSet(false, true)) return
        scope.launch {
            // CloudKitSyncEngine 側は書き込みの完了を state で公開しているだけなので、
            // エンジンに手を入れず購読で「sync 完了 → スナップショット再構築」を接続する。
            syncEngine.state
                .filterIsInstance<CloudKitSyncEngine.SyncState.Completed>()
                .collect { reload() }
        }
        // seed の初回投入・アプリ更新時の入れ直しでも作り直す (同期の完了を待たない)。
        scope.launch { syncEngine.localDataReplaced.collect { reload() } }
    }

    /**
     * 読み込み済みのストア。まだなら読み込んでから返す。読み込めなければ投げる
     * (次の呼び出しでもう一度読み込む)。
     */
    suspend fun loadedStore(): SnapshotStore {
        start()
        if (!store.isLoaded()) {
            // 待っている間に別の読み込みが済んでいれば読み直さない。
            reloadMutex.withLock { if (!store.isLoaded()) loadLocked() }
        }
        if (!store.isLoaded()) {
            throw SnapshotUnavailableException("マスタデータを読み込めませんでした", lastLoadFailure)
        }
        return store
    }

    /**
     * DB を読み直して新スナップショットへ差し替える。失敗しても現行スナップショット
     * (あれば) が維持される。
     */
    suspend fun reload() {
        reloadMutex.withLock { loadLocked() }
    }

    private suspend fun loadLocked() {
        // Room は初回アクセスまでファイルを作らない。
        val dbFile = appContext.getDatabasePath(DB_NAME)
        if (!dbFile.exists()) {
            lastLoadFailure = IllegalStateException("DB がまだ無い")
            Log.i(TAG, "DB 未作成のため load をスキップ")
            return
        }
        try {
            val stats = withContext(Dispatchers.IO) { store.load(dbFile.absolutePath) }
            lastLoadFailure = null
            generation++
            Log.i(TAG, "snapshot loaded: songs=${stats.songs} idols=${stats.idols}")
        } catch (e: SnapshotException) {
            // 例: Room のマイグレーション中で新カラムがまだ無い等。
            lastLoadFailure = e
            Log.w(TAG, "snapshot load 失敗", e)
        }
    }

    /**
     * 描画から同期で読むための口。読み込み済みなら (世代, ストア)、まだなら null
     * (待たない・読み込みも始めない)。世代は読み直すたびに変わるので、呼び元はこれで覚え書きを捨てる。
     */
    fun currentGeneration(): Pair<Long, SnapshotStore>? =
        if (store.isLoaded()) generation to store else null

    /**
     * 読み込み済みスナップショットに対してクエリを 1 回実行する (まだなら読み込みを待つ)。
     * 読み込めなければ [SnapshotUnavailableException]。
     *
     * FFI 呼び出しは呼び元スレッドをブロックするので、Main から呼ばれても UI を
     * 止めないよう Default ディスパッチャへ逃がす。
     */
    suspend fun <T> query(block: (SnapshotStore) -> T): T {
        val s = loadedStore()
        return withContext(Dispatchers.Default) { block(s) }
    }

    companion object {
        private const val TAG = "SnapshotStore"

        /** AppDatabase.buildDatabase と同じ DB 名 (Room の databaseBuilder に渡している名前)。 */
        private const val DB_NAME = "master.sqlite"
    }
}
