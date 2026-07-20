package com.fugaif.imaslivedb.data.sync

import android.content.Context
import android.util.Log
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.db.dao.SyncDao
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * CloudKit public DB → ローカル Room の差分同期。
 * iOS の CloudKitSyncEngine と同じ依存順・規約 (modifiedAt > lastSync, deletedAt で削除伝搬)。
 * SongCall / SongVideo は Android にテーブルが無いので対象外。
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

    private class Step(
        val type: String,
        val label: String,
        val upsert: suspend (SyncDao, List<CkRecord>) -> Unit,
        val delete: (suspend (SyncDao, List<String>) -> Unit)? = null,
        // 単一PK (id) テーブルのローカル全ID取得。非null (= delete も非null) のステップのみ、
        // フル同期完走後の孤児掃除 (orphan cleanup) の対象になる。
        val localIds: (suspend (SyncDao) -> List<String>)? = null
    )

    private val steps: List<Step> = listOf(
        Step("Brand", "ブランド",
            { d, r -> d.upsertBrands(r.mapNotNull(SyncMappers::brand)) },
            { d, ids -> d.deleteBrands(ids) },
            { d -> d.brandIds() }),
        Step("Idol", "アイドル",
            { d, r -> d.upsertIdols(r.mapNotNull(SyncMappers::idol)) },
            { d, ids -> d.deleteIdols(ids) },
            { d -> d.idolIds() }),
        Step("Event", "イベント",
            { d, r -> d.upsertEvents(r.mapNotNull(SyncMappers::event)) },
            { d, ids -> d.deleteEvents(ids) },
            { d -> d.eventIds() }),
        Step("ImasUnit", "ユニット",
            { d, r -> d.upsertUnits(r.mapNotNull(SyncMappers::unit)) },
            { d, ids -> d.deleteUnits(ids) },
            { d -> d.unitIds() }),
        Step("IdolBrand", "アイドル×ブランド",
            { d, r -> d.upsertIdolBrands(r.mapNotNull(SyncMappers::idolBrand)) }),
        Step("Show", "公演",
            { d, r -> d.upsertShows(r.mapNotNull(SyncMappers::show)) },
            { d, ids -> d.deleteShows(ids) },
            { d -> d.showIds() }),
        Step("Song", "楽曲",
            { d, r -> d.upsertSongs(r.mapNotNull(SyncMappers::song)) },
            { d, ids -> d.deleteSongs(ids) },
            { d -> d.songIds() }),
        Step("UnitMember", "ユニットメンバー",
            { d, r -> d.upsertUnitMembers(r.mapNotNull(SyncMappers::unitMember)) }),
        Step("SongArtist", "楽曲アーティスト",
            { d, r -> d.upsertSongArtists(r.mapNotNull(SyncMappers::songArtist)) }),
        Step("ShowCast", "公演キャスト",
            { d, r -> d.upsertShowCasts(r.mapNotNull(SyncMappers::showCast)) }),
        Step("SetlistItem", "セトリ",
            { d, r -> d.upsertSetlistItems(r.mapNotNull(SyncMappers::setlistItem)) },
            { d, ids -> d.deleteSetlistItems(ids) },
            { d -> d.setlistItemIds() }),
        Step("SetlistPerformer", "セトリ出演者",
            { d, r -> d.upsertSetlistPerformers(r.mapNotNull(SyncMappers::setlistPerformer)) }),
        // Phase 6: コミュニティコンテンツ (songs に依存)
        Step("SongCall", "コーレス",
            { d, r -> d.upsertSongCalls(r.mapNotNull(SyncMappers::songCall)) },
            { d, ids -> d.deleteSongCalls(ids) },
            { d -> d.songCallIds() }),
        Step("SongVideo", "参考動画",
            { d, r -> d.upsertSongVideos(r.mapNotNull(SyncMappers::songVideo)) },
            { d, ids -> d.deleteSongVideos(ids) },
            { d -> d.songVideoIds() }),
    )

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

    /** 差分同期 (初回 lastSync=0 → 全件)。 */
    suspend fun sync() {
        if (!CloudKitConfig.isConfigured) {
            // token 未設定でもエラーにしない: seed DB の実データで継続する (最新化だけ行わない)。
            // 主にコントリビューターのローカルビルド向け。リリース版は token を注入する。
            Log.i(TAG, "CloudKit API token 未設定 → 同期スキップ (seed/既存DBで継続)")
            _state.value = SyncState.Idle
            return
        }
        val dao = db.syncDao()
        // DB が空 (初回 or スキーマ更新による破棄) なら lastSync を無視して全件取得する。
        // fallbackToDestructiveMigration で DB が消えても SharedPreferences の lastSync は
        // 残るため、これを見ないと差分同期になって再投入されず空のままになる。
        val since = if (dao.brandCount() == 0) 0L else prefs.getLong(KEY_LAST_SYNC, 0L)
        // epoch (since=0) から全件取得するフル同期かどうか。orphan 掃除は「完走した全件パス」でのみ
        // 安全に行える (差分同期だと取得範囲外の既存レコードまで消してしまう)。
        val isFullSync = since == 0L
        val startMs = System.currentTimeMillis()
        var total = 0
        try {
            steps.forEachIndexed { i, step ->
                _state.value = SyncState.Syncing(i + 1, steps.size, step.label)
                val records = client.query(step.type, since)
                if (records.isNotEmpty()) {
                    val alive = records.filterNot { it.isDeleted }
                    val deleted = records.filter { it.isDeleted }
                    if (alive.isNotEmpty()) step.upsert(dao, alive)
                    if (deleted.isNotEmpty()) step.delete?.invoke(dao, deleted.map { it.recordName })
                    total += records.size
                    Log.i(TAG, "${step.type}: ${records.size} (alive=${alive.size}, del=${deleted.size})")
                }
                // フル再取得 (epoch から全件) を完走したステップに限り、CloudKit 側で tombstone
                // 無しに物理削除されたレコードをローカルからも掃除する (safety net)。iOS
                // CloudKitSyncEngine.deleteOrphans と同思想: validIds が空なら no-op
                // (取得0件は通信異常の可能性があり、空判定で全消去しては危険なため)。
                if (isFullSync && step.delete != null && step.localIds != null) {
                    val validIds = records.mapNotNullTo(mutableSetOf()) { it.str("id") ?: it.recordName }
                    if (validIds.isNotEmpty()) {
                        val orphanIds = step.localIds.invoke(dao).filterNot { validIds.contains(it) }
                        if (orphanIds.isNotEmpty()) {
                            step.delete.invoke(dao, orphanIds)
                            Log.i(TAG, "${step.type}: orphan_deleted count=${orphanIds.size}")
                        }
                    }
                }
            }
            prefs.edit().putLong(KEY_LAST_SYNC, startMs).apply()
            _state.value = SyncState.Completed(total)
            Log.i(TAG, "sync complete: total=$total, lastSync→$startMs")
        } catch (e: Exception) {
            Log.e(TAG, "sync failed", e)
            _state.value = SyncState.Error(e.message ?: "同期に失敗しました")
        }
    }

    companion object {
        private const val TAG = "CloudKitSync"
        private const val KEY_LAST_SYNC = "last_sync_ms"
    }
}
