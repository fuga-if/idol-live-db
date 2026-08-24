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
import uniffi.imas_core.SnapshotException
import uniffi.imas_core.SnapshotStore

/**
 * 共有コア (imas-core) のインメモリスナップショットをアプリで単一保持するプロバイダ。
 *
 * - 起動時に Room の DB ファイル (master.sqlite) を READ_ONLY で読み切って load する
 * - CloudKit 差分同期の完了 (SyncState.Completed) を購読し、そのたびに reload して
 *   新スナップショットへ原子的に差し替える (core 側 SnapshotStore の規約)
 * - **user_marks (担当/お気に入り/メモ/回収) はスナップショットに含まれない**。
 *   参加マーク等のユーザーデータは Room が正で、必要な id 集合は各リポジトリが
 *   解決してクエリ引数で渡す
 *
 * スナップショットが使えない局面 (ネイティブ .so 無しのコントリビュータービルド、
 * load 失敗、未ロード) では [query] が null を返し、呼び出し側 (リポジトリ) が
 * 既存の Room/SQL 経路へフォールバックする。アプリはどの状態でも機能を失わない。
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

    // ネイティブライブラリが同梱されていないビルド (Rust 未ビルドのコントリビューター環境) で
    // クラスロード時に落とさないため、生成失敗は「スナップショット経路なし」に落とす。
    private val store: SnapshotStore? = runCatching { SnapshotStore() }
        .onFailure { Log.w(TAG, "SnapshotStore 生成失敗 → SQL 経路のみで継続", it) }
        .getOrNull()

    /**
     * 起動時に一度呼ぶ。初回 load と、sync 完了ごとの reload 購読を開始する。
     *
     * 初回インストール直後は DB ファイルがまだ無く初回 load はスキップされるが、
     * seed 投入後の初回フル同期が Completed を流すのでそこで load される。
     */
    fun start() {
        if (store == null) return
        scope.launch { reload() }
        scope.launch {
            // CloudKitSyncEngine 側は書き込みの完了を state で公開しているだけなので、
            // エンジンに手を入れず購読で「sync 完了 → スナップショット再構築」を接続する。
            syncEngine.state
                .filterIsInstance<CloudKitSyncEngine.SyncState.Completed>()
                .collect { reload() }
        }
    }

    /**
     * DB を読み直して新スナップショットへ差し替える。失敗しても現行スナップショット
     * (あれば) が維持されるので、読み手は古い方 or SQL 経路で継続できる。
     */
    suspend fun reload() {
        val s = store ?: return
        reloadMutex.withLock {
            // Room は初回アクセスまでファイルを作らない。存在しない段階で load しても
            // 失敗ログが出るだけなので、初回同期の Completed を待つ。
            val dbFile = appContext.getDatabasePath(DB_NAME)
            if (!dbFile.exists()) {
                Log.i(TAG, "DB 未作成のため load をスキップ (初回同期完了後に再試行)")
                return
            }
            try {
                val stats = withContext(Dispatchers.IO) { s.load(dbFile.absolutePath) }
                Log.i(TAG, "snapshot loaded: songs=${stats.songs} idols=${stats.idols}")
            } catch (e: SnapshotException) {
                // 例: Room のマイグレーション中で新カラムがまだ無い等。次の sync 完了で
                // 再試行されるまで SQL 経路で継続する。
                Log.w(TAG, "snapshot load 失敗 → SQL 経路で継続", e)
            }
        }
    }

    /**
     * ロード済みスナップショットに対してクエリを 1 回実行する。
     * 未ロード・利用不可・型付きエラー時は null (= 呼び出し側は SQL へフォールバック)。
     *
     * FFI 呼び出しは呼び元スレッドをブロックするので、Main から呼ばれても UI を
     * 止めないよう Default ディスパッチャへ逃がす。
     */
    suspend fun <T> query(block: (SnapshotStore) -> T): T? {
        val s = store ?: return null
        if (!s.isLoaded()) return null
        return withContext(Dispatchers.Default) {
            try {
                block(s)
            } catch (e: SnapshotException) {
                // isLoaded 直後の unload 競合 (NotLoaded) 等。フォールバックに任せる。
                Log.w(TAG, "snapshot query 失敗 → SQL 経路へフォールバック", e)
                null
            }
        }
    }

    companion object {
        private const val TAG = "SnapshotStore"

        /** AppDatabase.buildDatabase と同じ DB 名 (Room の databaseBuilder に渡している名前)。 */
        private const val DB_NAME = "master.sqlite"
    }
}
