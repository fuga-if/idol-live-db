package com.fugaif.imaslivedb.data.sync

import android.content.Context
import android.util.Log
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.db.dao.SyncDao
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import uniffi.imas_core.CkRow
import uniffi.imas_core.SyncCompletionState
import uniffi.imas_core.SyncMode
import uniffi.imas_core.SyncStartupState
import uniffi.imas_core.SyncStep
import uniffi.imas_core.syncCompletionPlan
import uniffi.imas_core.syncOrphanIds
import uniffi.imas_core.syncRunStartPlan
import uniffi.imas_core.syncStartupPlan
import uniffi.imas_core.syncStepStartPlan
import uniffi.imas_core.syncStepsInOrder
import uniffi.imas_core.syncSupportsOrphanCleanup
import kotlin.math.roundToLong

/**
 * CloudKit public DB → ローカル Room の差分同期。
 *
 * 「どのモードで走るか」「どの順で取るか」「どこから取るか」「何を孤児として消してよいか」
 * 「完了時に何を保存するか」は共有コア (`domain::sync_planning`) の純粋関数が決め、
 * ここは HTTP (CloudKitClient) と Room への実書き込みだけを担う。
 * CloudKit の transport は iOS (CloudKit.framework) と非対称なので共有しない。
 *
 * Android は iOS 固有の機能を持たないので、コアには「退化した入力」を渡す:
 *  - 中断されたフル同期の再開が無い → hasPendingFullSync=false / checkpointEpoch=null
 *  - 定期フル再取得 (iOS 24h) が無い → fullSyncIntervalSeconds=null
 *  - cursor の概念が無い ([CloudKitClient] が continuationMarker を内部で使い切る)
 *
 * Venue / VenueName / VenueHall は Room に同期先の DAO が無いのでステップから外している
 * (seed から入った行がそのまま残る)。SongCall / SongVideo は Phase 6 で追加済み。
 */
class CloudKitSyncEngine(context: Context, private val db: AppDatabase) {

    private val appContext = context.applicationContext
    private val client = CloudKitClient()
    private val prefs = appContext.getSharedPreferences("imas_sync", Context.MODE_PRIVATE)

    private val _state = MutableStateFlow<SyncState>(SyncState.Idle)
    val state: StateFlow<SyncState> = _state.asStateFlow()

    sealed class SyncState {
        data object Idle : SyncState()
        data class Syncing(val step: Int, val total: Int, val label: String) : SyncState()
        data class Completed(val fetched: Int) : SyncState()
        data class Error(val message: String) : SyncState()
    }

    /**
     * recordType ごとの書き込み口。順序とラベルはコアが持つので、ここは
     * 「行をどのテーブルに入れ、どう消し、どの ID を孤児判定に使うか」だけ。
     *
     * delete / localIds が null のステップ (複合 PK の junction) は削除伝搬も孤児掃除も
     * 行わない。recordName の分解が曖昧で、親レコードの再同期で概ね収束するため。
     */
    private class StepIo(
        val upsert: suspend (SyncDao, List<CkRow>, List<String>) -> Unit,
        val delete: (suspend (SyncDao, List<String>) -> Unit)? = null,
        val localIds: (suspend (SyncDao) -> List<String>)? = null
    )

    private val stepIo: Map<String, StepIo> = mapOf(
        "Brand" to StepIo(
            { d, rows, _ -> d.upsertBrands(SyncMappers.brands(rows)) },
            { d, ids -> d.deleteBrands(ids) },
            { d -> d.brandIds() }),
        "Idol" to StepIo(
            // voiceActors はコアの行に載らない (声優は履歴テーブルが正) が、Room の upsert は
            // 行を丸ごと置換するので、生レコードから拾い直して渡さないと CV が消える。
            { d, rows, jsons -> d.upsertIdols(SyncMappers.idols(rows, SyncMappers.voiceActorsById(jsons))) },
            { d, ids -> d.deleteIdols(ids) },
            { d -> d.idolIds() }),
        "Event" to StepIo(
            { d, rows, _ -> d.upsertEvents(SyncMappers.events(rows)) },
            { d, ids -> d.deleteEvents(ids) },
            { d -> d.eventIds() }),
        "ImasUnit" to StepIo(
            { d, rows, _ -> d.upsertUnits(SyncMappers.units(rows)) },
            { d, ids -> d.deleteUnits(ids) },
            { d -> d.unitIds() }),
        "IdolBrand" to StepIo({ d, rows, _ -> d.upsertIdolBrands(SyncMappers.idolBrands(rows)) }),
        "Show" to StepIo(
            { d, rows, _ -> d.upsertShows(SyncMappers.shows(rows)) },
            { d, ids -> d.deleteShows(ids) },
            { d -> d.showIds() }),
        "Song" to StepIo(
            { d, rows, _ -> d.upsertSongs(SyncMappers.songs(rows)) },
            { d, ids -> d.deleteSongs(ids) },
            { d -> d.songIds() }),
        "UnitMember" to StepIo({ d, rows, _ -> d.upsertUnitMembers(SyncMappers.unitMembers(rows)) }),
        "SongArtist" to StepIo({ d, rows, _ -> d.upsertSongArtists(SyncMappers.songArtists(rows)) }),
        "ShowCast" to StepIo({ d, rows, _ -> d.upsertShowCasts(SyncMappers.showCasts(rows)) }),
        "SetlistItem" to StepIo(
            { d, rows, _ -> d.upsertSetlistItems(SyncMappers.setlistItems(rows)) },
            { d, ids -> d.deleteSetlistItems(ids) },
            { d -> d.setlistItemIds() }),
        "SetlistPerformer" to StepIo({ d, rows, _ -> d.upsertSetlistPerformers(SyncMappers.setlistPerformers(rows)) }),
        // Phase 6: コミュニティコンテンツ (songs に依存)
        "SongCall" to StepIo(
            { d, rows, _ -> d.upsertSongCalls(SyncMappers.songCalls(rows)) },
            { d, ids -> d.deleteSongCalls(ids) },
            { d -> d.songCallIds() }),
        "SongVideo" to StepIo(
            { d, rows, _ -> d.upsertSongVideos(SyncMappers.songVideos(rows)) },
            { d, ids -> d.deleteSongVideos(ids) },
            { d -> d.songVideoIds() }),
    )

    /**
     * FK 依存順のステップ (親テーブルが先)。順序とラベルはコアが持つ。
     *
     * lazy にしてあるのは、ネイティブライブラリ未同梱のビルド (Rust 未ビルドの
     * コントリビューター環境) でコンストラクタごと落とさないため。sync() の try の中で
     * 初めて触るので、失敗しても SyncState.Error に落ちる。
     */
    private val steps: List<SyncStep> by lazy { syncStepsInOrder(stepIo.keys.toList()) }

    /** ローカルに既にデータがあるか (初回判定用)。 */
    suspend fun hasData(): Boolean = db.syncDao().brandCount() > 0

    /**
     * 起動時のローカルデータ準備: DB が空なら seed (assets/master_seed.sqlite) を投入する。
     * 「seed = 基準データ / CloudKit = 増分」の連続したパイプラインの第1段で、ここで投入してから
     * sync() で最新差分を当てる。投入後にデータがあるか (= UI を即表示してよいか) を返す。
     */
    suspend fun ensureLocalData(): Boolean {
        val hasData = SeedImporter.importIfNeeded(appContext, db)
        // seed 投入に失敗しデータが依然として空の場合、無言で「データを準備中…」に留まらせず
        // 既存の Error state を通じてユーザーに可視化する (iOS ImasLiveDBApp の起動時アラート相当)。
        if (!hasData) {
            SeedImporter.lastImportError?.let { _state.value = SyncState.Error(it) }
        }
        return hasData
    }

    /** 差分同期 (初回 lastSync 無し → 全件)。 */
    suspend fun sync() {
        if (!CloudKitConfig.isConfigured) {
            // token 未設定でもエラーにしない: seed DB の実データで継続する (最新化だけ行わない)。
            // 主にコントリビューターのローカルビルド向け。リリース版は token を注入する。
            Log.i(TAG, "CloudKit API token 未設定 → 同期スキップ (seed/既存DBで継続)")
            _state.value = SyncState.Idle
            return
        }
        val dao = db.syncDao()
        val startMs = System.currentTimeMillis()
        var total = 0
        try {
            // DB が空 (初回 or スキーマ更新による破棄) なら lastSync を無視して全件取得する。
            // fallbackToDestructiveMigration で DB が消えても SharedPreferences の lastSync は
            // 残るため、これを見ないと差分同期になって再投入されず空のままになる。
            val plan = syncStartupPlan(
                SyncStartupState(
                    hasPendingFullSync = false,     // Android は中断フルの再開を持たない
                    localDataEmpty = dao.brandCount() == 0,
                    lastFullSyncEpoch = null,
                    // prefs の既定値 0 は「起点なし」= フルの合図なので None に写す。
                    lastSyncEpoch = prefs.getLong(KEY_LAST_SYNC, 0L).takeIf { it > 0L }?.toEpochSeconds(),
                    nowEpoch = startMs.toEpochSeconds(),
                    fullSyncIntervalSeconds = null  // 定期フル再取得は iOS だけの機能
                )
            )
            val isFullSync = plan.mode == SyncMode.FULL
            // 再開の概念が無いので effectiveStartEpoch == 開始時刻に退化する。それでも通すのは
            // last_sync に何を保存するかの規則を iOS と 1 か所で共有するため。
            val runStart = syncRunStartPlan(isFullSync, startMs.toEpochSeconds(), null, emptyList())
            Log.i(TAG, "sync start: mode=${plan.mode} reason=${plan.reason}")

            steps.forEachIndexed { i, step ->
                _state.value = SyncState.Syncing(i + 1, steps.size, step.displayName)
                val io = stepIo.getValue(step.recordType)
                val stepStart = syncStepStartPlan(
                    step.recordType, isFullSync, runStart.doneSteps,
                    checkpointEpoch = null,         // ステップ途中のチェックポイントは iOS のみ
                    modifiedSinceEpoch = plan.modifiedSinceEpoch
                )
                if (stepStart.skip) return@forEachIndexed

                val recordJsons = client.query(step.recordType, stepStart.startEpoch.toEpochMillis())
                val batch = SyncMappers.ingest(step.recordType, recordJsons, startMs)
                if (recordJsons.isNotEmpty()) {
                    if (batch.rows.isNotEmpty()) io.upsert(dao, batch.rows, recordJsons)
                    if (batch.deletedRecordNames.isNotEmpty()) io.delete?.invoke(dao, batch.deletedRecordNames)
                    if (batch.invalidRecordNames.isNotEmpty()) {
                        Log.w(TAG, "${step.recordType}: 必須キー欠損で ${batch.invalidRecordNames.size} 件スキップ")
                    }
                    total += recordJsons.size
                    Log.i(
                        TAG,
                        "${step.recordType}: ${recordJsons.size} " +
                            "(rows=${batch.rows.size}, del=${batch.deletedRecordNames.size})"
                    )
                }
                // epoch から全件取り直して完走したステップに限り、CloudKit 側で tombstone
                // 無しに物理削除されたレコードをローカルからも掃除する (safety net)。
                // 取得0件は通信異常の可能性があるので、コア側で valid_ids が空なら no-op になる。
                if (stepStart.startedFromEpoch && syncSupportsOrphanCleanup(step.recordType)) {
                    val delete = io.delete ?: return@forEachIndexed
                    val localIds = io.localIds ?: return@forEachIndexed
                    // valid_ids には「行にできたレコード」だけでなく「必須キー欠損で捨てた
                    // レコード」も入れる。捨てたレコードもサーバ上には在る以上、保護対象から
                    // 外すと対応するローカル行が孤児と誤判定されて DELETE される
                    // (旧実装は取得した全レコードの id/recordName を保護していた)。
                    // 単一 PK テーブルは recordName == id (tools/seed_cloudkit.py) なので
                    // recordName をそのまま突き合わせてよい。
                    // deletedRecordNames は入れない: 直前の io.delete で既にローカルから
                    // 消えており localIds に現れないし、全件が tombstone のページで
                    // 「valid_ids が空なら no-op」というコア側の安全弁を殺さずに済む。
                    val validIds = SyncMappers.rowIds(batch.rows) + batch.invalidRecordNames
                    val orphanIds = syncOrphanIds(localIds(dao), validIds)
                    if (orphanIds.isNotEmpty()) {
                        delete(dao, orphanIds)
                        Log.i(TAG, "${step.recordType}: orphan_deleted count=${orphanIds.size}")
                    }
                }
            }

            val completion = syncCompletionPlan(
                SyncCompletionState(
                    isFullSync = isFullSync,
                    // last_full_sync_at は 24h 判定 (iOS のみ) を進める書き込みなので Android では立てない。
                    isStartupRun = false,
                    effectiveStartEpoch = runStart.effectiveStartEpoch,
                    syncStartEpoch = startMs.toEpochSeconds(),
                    completionEpoch = System.currentTimeMillis().toEpochSeconds(),
                    totalFetched = total.toUInt(),
                    allStepsCompleted = true
                )
            )
            if (completion.shouldSaveLastSync) {
                prefs.edit().putLong(KEY_LAST_SYNC, completion.lastSyncEpochToSave.toEpochMillis()).apply()
            }
            // shouldNotifyMasterChanged は使わない: Android は Completed を購読して
            // スナップショットを再ロードしており、0 件同期でも state は必ず進める必要がある。
            _state.value = SyncState.Completed(total)
            Log.i(TAG, "sync complete: total=$total, lastSync→${completion.lastSyncEpochToSave}")
        } catch (e: Exception) {
            Log.e(TAG, "sync failed", e)
            _state.value = SyncState.Error(e.message ?: "同期に失敗しました")
        }
    }

    // コアのエポックは秒 (f64)。Android は ms を持っているので境界で必ず換算する。
    // 単位を混ぜると境界巻き戻し幅が 1000 倍ずれる。
    private fun Long.toEpochSeconds(): Double = this / 1000.0

    // 秒 → ms。ms/1000.0 は 2 進で厳密に表せないことがあるので四捨五入で戻す
    // (切り捨てだと 1ms 手前になり、境界のレコードを毎回取り直す)。
    private fun Double.toEpochMillis(): Long = (this * 1000.0).roundToLong()

    companion object {
        private const val TAG = "CloudKitSync"
        private const val KEY_LAST_SYNC = "last_sync_ms"
    }
}
