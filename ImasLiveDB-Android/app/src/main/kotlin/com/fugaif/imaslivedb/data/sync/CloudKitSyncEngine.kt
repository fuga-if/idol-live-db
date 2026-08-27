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
import uniffi.imas_core.syncParseCompositeRecordName
import uniffi.imas_core.syncRunStartPlan
import uniffi.imas_core.syncStartupPlan
import uniffi.imas_core.syncStepStartPlan
import uniffi.imas_core.syncStepsInOrder
import uniffi.imas_core.syncSupportsOrphanCleanup
import uniffi.imas_core.syncTableInfo
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
     */
    private class StepIo(
        val upsert: suspend (SyncDao, List<CkRow>, List<String>) -> Unit,
        /**
         * tombstone の削除。recordName の分解はコアが済ませ、ここには PK 値の並びが渡る
         * (単一 PK は id 1 要素、複合 PK は syncTableInfo の pkColumns と同順・同数)。
         */
        val delete: suspend (SyncDao, List<List<String>>) -> Unit,
        /**
         * 孤児掃除に使うローカル全 ID。単一 PK テーブルのみ (複合 PK には id 列が無い)。
         * どのステップで掃除してよいかの判定は `syncSupportsOrphanCleanup` が持つ。
         */
        val localIds: (suspend (SyncDao) -> List<String>)? = null
    )

    private fun singlePk(keys: List<List<String>>): List<String> = keys.map { it[0] }

    private val stepIo: Map<String, StepIo> = mapOf(
        "Brand" to StepIo(
            { d, rows, _ -> d.upsertBrands(SyncMappers.brands(rows)) },
            { d, keys -> d.deleteBrands(singlePk(keys)) },
            { d -> d.brandIds() }),
        "Idol" to StepIo(
            // voiceActors はコアの行に載らない (声優は履歴テーブルが正) が、Room の upsert は
            // 行を丸ごと置換するので、生レコードから拾い直して渡さないと CV が消える。
            { d, rows, jsons -> d.upsertIdols(SyncMappers.idols(rows, SyncMappers.voiceActorsById(jsons))) },
            { d, keys -> d.deleteIdols(singlePk(keys)) },
            { d -> d.idolIds() }),
        "Event" to StepIo(
            { d, rows, _ -> d.upsertEvents(SyncMappers.events(rows)) },
            { d, keys -> d.deleteEvents(singlePk(keys)) },
            { d -> d.eventIds() }),
        "ImasUnit" to StepIo(
            { d, rows, _ -> d.upsertUnits(SyncMappers.units(rows)) },
            { d, keys -> d.deleteUnits(singlePk(keys)) },
            { d -> d.unitIds() }),
        // 会場は Show より前に取り込む (shows.venue_id が参照する)。順序はコアの FK 依存順が正。
        "Venue" to StepIo(
            { d, rows, _ -> d.upsertVenues(SyncMappers.venues(rows)) },
            { d, keys -> d.deleteVenues(singlePk(keys)) },
            { d -> d.venueIds() }),
        "Creator" to StepIo(
            { d, rows, _ -> d.upsertCreators(SyncMappers.creators(rows)) },
            { d, keys -> d.deleteCreators(singlePk(keys)) },
            { d -> d.creatorIds() }),
        "UnitVersion" to StepIo(
            { d, rows, _ -> d.upsertUnitVersions(SyncMappers.unitVersions(rows)) },
            { d, keys -> d.deleteUnitVersions(singlePk(keys)) },
            { d -> d.unitVersionIds() }),
        "VenueName" to StepIo(
            { d, rows, _ -> d.upsertVenueNames(SyncMappers.venueNames(rows)) },
            { d, keys -> d.deleteVenueNames(singlePk(keys)) },
            { d -> d.venueNameIds() }),
        "VenueHall" to StepIo(
            { d, rows, _ -> d.upsertVenueHalls(SyncMappers.venueHalls(rows)) },
            { d, keys -> d.deleteVenueHalls(singlePk(keys)) },
            { d -> d.venueHallIds() }),
        "IdolBrand" to StepIo(
            { d, rows, _ -> d.upsertIdolBrands(SyncMappers.idolBrands(rows)) },
            { d, keys -> keys.forEach { d.deleteIdolBrand(it[0], it[1]) } }),
        "Show" to StepIo(
            { d, rows, _ -> d.upsertShows(SyncMappers.shows(rows)) },
            { d, keys -> d.deleteShows(singlePk(keys)) },
            { d -> d.showIds() }),
        "Song" to StepIo(
            { d, rows, _ -> d.upsertSongs(SyncMappers.songs(rows)) },
            { d, keys -> d.deleteSongs(singlePk(keys)) },
            { d -> d.songIds() }),
        "UnitMember" to StepIo(
            { d, rows, _ -> d.upsertUnitMembers(SyncMappers.unitMembers(rows)) },
            { d, keys -> keys.forEach { d.deleteUnitMember(it[0], it[1]) } }),
        "SongArtist" to StepIo(
            { d, rows, _ -> d.upsertSongArtists(SyncMappers.songArtists(rows)) },
            // song_artists だけ PK が 3 列 (song_id, idol_id, role)。
            { d, keys -> keys.forEach { d.deleteSongArtist(it[0], it[1], it[2]) } }),
        "ShowCast" to StepIo(
            { d, rows, _ -> d.upsertShowCasts(SyncMappers.showCasts(rows)) },
            { d, keys -> keys.forEach { d.deleteShowCast(it[0], it[1]) } }),
        "SetlistItem" to StepIo(
            { d, rows, _ -> d.upsertSetlistItems(SyncMappers.setlistItems(rows)) },
            { d, keys -> d.deleteSetlistItems(singlePk(keys)) },
            { d -> d.setlistItemIds() }),
        "SetlistPerformer" to StepIo(
            { d, rows, _ -> d.upsertSetlistPerformers(SyncMappers.setlistPerformers(rows)) },
            { d, keys -> keys.forEach { d.deleteSetlistPerformer(it[0], it[1]) } }),
        // Phase 6: コミュニティコンテンツ (songs に依存)
        "SongCall" to StepIo(
            { d, rows, _ -> d.upsertSongCalls(SyncMappers.songCalls(rows)) },
            { d, keys -> d.deleteSongCalls(singlePk(keys)) },
            { d -> d.songCallIds() }),
        "SongVideo" to StepIo(
            { d, rows, _ -> d.upsertSongVideos(SyncMappers.songVideos(rows)) },
            { d, keys -> d.deleteSongVideos(singlePk(keys)) },
            { d -> d.songVideoIds() }),
    )

    /**
     * tombstone の recordName → DELETE に渡す PK 値の並び。
     *
     * recordType → (テーブル, PK 列) の対応も、複合 PK の recordName `"{table}-{pk1}-{pk2}"`
     * (seed_cloudkit.py の make_record_name と同じ規約) の分解も共有コアが持つ。
     * iOS `AppDatabase.deleteRecords` と同じ手順で、形の合わない recordName は捨てる。
     *
     * 分解だけは recordName 1 件ずつ FFI を跨ぐ (バッチ版がコアに無い)。tombstone は
     * 増分同期あたり数件なので iOS と同じ逐次呼び出しに揃えている。
     *
     * **既知の限界**: コアの分解は body を前から `-` で切るので、**先頭側**の PK 値に `-` が
     * 入っていると切り出しがずれ、DELETE がどの行にも当たらない (末尾の値だけが `-` を
     * 含んでよい)。実データがこれを踏んでおり (`unit_members.unit_id = "3-9days"`,
     * `song_artists.song_id = "765as_arcadia_-bossa_nova_rearrange_mix-"` など)、
     * 新規セトリ項目の `sli_<uuid>` も同じ形をとる。iOS も同じコア関数を呼ぶので
     * 挙動は両 OS で一致しており、直すならコア側 (`parse_composite_record_name`) が正。
     * ここでは落ちた recordName を必ずログに出す。黙って捨てると「削除は伝わっている」と
     * 誤読したまま原因に辿り着けない。
     */
    private fun primaryKeyValues(recordType: String, recordNames: List<String>): List<List<String>> {
        val info = syncTableInfo(recordType) ?: run {
            if (recordNames.isNotEmpty()) {
                Log.w(TAG, "$recordType: 未知のレコードタイプで tombstone ${recordNames.size} 件を破棄")
            }
            return emptyList()
        }
        if (info.pkColumns.size == 1) return recordNames.map { listOf(it) }
        val pkCount = info.pkColumns.size.toUInt()
        val keys = ArrayList<List<String>>(recordNames.size)
        val unparsed = ArrayList<String>()
        for (name in recordNames) {
            val parsed = syncParseCompositeRecordName(name, info.table, pkCount)
            if (parsed != null) keys.add(parsed) else unparsed.add(name)
        }
        if (unparsed.isNotEmpty()) {
            Log.w(
                TAG,
                "$recordType: recordName を PK に分解できず削除を適用できません " +
                    "count=${unparsed.size} names=${unparsed.take(5)}"
            )
        }
        return keys
    }

    /**
     * 増分同期でもこのステップだけ epoch から取り直すか。
     *
     * 会場 3 テーブルは v8→v9 の移行 (MIGRATION_8_9) で**空のまま**作られる。Android は
     * 定期フル再取得を持たず (fullSyncIntervalSeconds=null)、フルに落ちるのは DB が丸ごと
     * 空のときだけなので、放置すると移行済み端末では会場マスタが永久に埋まらない
     * (公演の会場名が生文字列に落ち、キャパ表示と会場フィルタが機能しない)。
     * ローカルが空のときに限り起点を epoch へ落として一度だけ埋める。3 テーブル合計で
     * 500 行強しか無いので取り直しは安い。
     *
     * **Show も同じ移行で同じ欠け方をする**。MIGRATION_8_9 は venue_id / hall /
     * stream_platform を NULL で追加するだけなので、会場マスタだけ埋めても
     * shows.venue_id が NULL のままだと会場機能は一つも動かない (表示は生文字列のまま、
     * キャパは null、会場で絞ると 0 件)。会場を出せる端末が会場を出せない公演しか
     * 持たない、という行き止まりになるので Show も一度だけ取り直す。判定は
     * 「公演はあるのに venue_id を持つ行が 1 件も無い」。埋まれば次回からは走らない。
     *
     * 孤児掃除はこの経路では走らない (`startedFromEpoch` はフル実行でしか真にならない)。
     * 増分の途中で「サーバに無い = 孤児」と判定するのは危険なので、その方が正しい。
     *
     * [alreadyBackfilled] で 1 回に制限する。判定条件は「ローカルが埋まったか」なので、
     * サーバ側にその列やレコードタイプが無い場合は永久に真のままになり、毎回の同期で
     * 全件 (Show なら 1300 行超) を取り直し続けてしまう。埋まらなかったのなら取り直しても
     * 結果は変わらないので、完走したら二度とやらない。
     */
    private suspend fun needsBackfill(recordType: String, dao: SyncDao, alreadyBackfilled: Set<String>): Boolean {
        if (recordType in alreadyBackfilled) return false
        return when (recordType) {
            "Venue" -> dao.venueIds().isEmpty()
            "VenueName" -> dao.venueNameIds().isEmpty()
            "VenueHall" -> dao.venueHallIds().isEmpty()
            "Show" -> dao.showsWithVenueIdCount() == 0 && dao.showCount() > 0
            else -> false
        }
    }

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

            // getStringSet の戻りは変更禁止 (SharedPreferences の内部インスタンス) なので複製する。
            val backfilled = (prefs.getStringSet(KEY_BACKFILLED, emptySet()) ?: emptySet()).toMutableSet()

            steps.forEachIndexed { i, step ->
                _state.value = SyncState.Syncing(i + 1, steps.size, step.displayName)
                val io = stepIo.getValue(step.recordType)
                val isBackfill = needsBackfill(step.recordType, dao, backfilled)
                val stepStart = syncStepStartPlan(
                    step.recordType, isFullSync, runStart.doneSteps,
                    checkpointEpoch = null,         // ステップ途中のチェックポイントは iOS のみ
                    modifiedSinceEpoch = if (isBackfill) null else plan.modifiedSinceEpoch
                )
                if (stepStart.skip) return@forEachIndexed

                // コンテナのスキーマにこのレコードタイプがまだ無いときは、このステップだけ
                // 飛ばして先へ進む (iOS の CKError.unknownItem → continue と同じ)。
                // 会場 3 種は FK 依存順で先頭付近に並ぶので、ここで実行ごと落とすと後続の
                // 公演・楽曲・セトリまで丸ごと取り込まれず、Completed も流れない
                // (= スナップショットも作り直されない)。本物の失敗は従来どおり実行を止める。
                val recordJsons = try {
                    client.query(step.recordType, stepStart.startEpoch.toEpochMillis())
                } catch (e: CloudKitQueryException) {
                    if (!e.isUnknownRecordType) throw e
                    Log.w(TAG, "${step.recordType}: レコードタイプ未作成 → スキップ (${e.serverErrorCode}: ${e.reason})")
                    return@forEachIndexed
                }
                val batch = SyncMappers.ingest(step.recordType, recordJsons, startMs)
                if (recordJsons.isNotEmpty()) {
                    if (batch.rows.isNotEmpty()) io.upsert(dao, batch.rows, recordJsons)
                    // del= は「実際に DELETE を投げた件数」。tombstone の件数を出すと、
                    // 分解に失敗して 1 行も消せていない時に消えたように読めてしまう。
                    val deleteKeys = primaryKeyValues(step.recordType, batch.deletedRecordNames)
                    if (deleteKeys.isNotEmpty()) io.delete(dao, deleteKeys)
                    if (batch.invalidRecordNames.isNotEmpty()) {
                        Log.w(TAG, "${step.recordType}: 必須キー欠損で ${batch.invalidRecordNames.size} 件スキップ")
                    }
                    total += recordJsons.size
                    Log.i(
                        TAG,
                        "${step.recordType}: ${recordJsons.size} " +
                            "(rows=${batch.rows.size}, del=${deleteKeys.size}/${batch.deletedRecordNames.size})"
                    )
                }
                // 埋め直しは書き込みまで通ったときだけ「済み」にする。取得や書き込みで
                // 落ちた実行を済み扱いにすると、埋まっていないのに二度と取り直さなくなる
                // (レコードタイプ未作成でのスキップも上の return でここへ来ない = 再挑戦する)。
                if (isBackfill && backfilled.add(step.recordType)) {
                    prefs.edit().putStringSet(KEY_BACKFILLED, backfilled.toSet()).apply()
                    Log.i(TAG, "${step.recordType}: epoch からの埋め直し完了")
                }
                // epoch から全件取り直して完走したステップに限り、CloudKit 側で tombstone
                // 無しに物理削除されたレコードをローカルからも掃除する (safety net)。
                // 取得0件は通信異常の可能性があるので、コア側で valid_ids が空なら no-op になる。
                if (stepStart.startedFromEpoch && syncSupportsOrphanCleanup(step.recordType)) {
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
                        // ここに来るのは単一 PK テーブルだけなので id 1 要素の並びで渡す。
                        io.delete(dao, orphanIds.map { listOf(it) })
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

        /** epoch から一度取り直したレコードタイプ (v8→v9 移行の埋め直しを 1 回に限るため)。 */
        private const val KEY_BACKFILLED = "backfilled_record_types"
    }
}
