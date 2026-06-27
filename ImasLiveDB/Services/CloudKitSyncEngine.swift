import Foundation
import CloudKit
import Observation
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "CloudKitSync")

/// CloudKitとローカルGRDB間の同期を管理
@Observable
final class CloudKitSyncEngine: @unchecked Sendable {

    // MARK: - Types

    enum SyncState: Sendable, Equatable {
        case idle
        case syncing(String)
        case completed(Date)
        case error(String)

        var description: String {
            switch self {
            case .idle:
                return "待機中"
            case .syncing(let type):
                return "\(type)を同期中…"
            case .completed(let date):
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return "最終同期: \(formatter.string(from: date))"
            case .error(let message):
                return "エラー: \(message)"
            }
        }

        /// 全件再同期が必要なことを示すエラー状態
        static let requiresFullResync = SyncState.error("全件再同期が必要です")
    }

    /// CloudKitレコードタイプと同期順序の定義
    private struct SyncStep: Sendable {
        let recordType: String
        let displayName: String
    }

    // MARK: - Properties

    var state: SyncState = .idle

    /// 同期中の進捗 (0..1)。現在のステップ位置 / 全ステップ数。syncing 以外では nil。
    var syncProgress: Double? {
        guard case .syncing(let name) = state,
              let idx = syncSteps.firstIndex(where: { $0.displayName == name }) else { return nil }
        return Double(idx + 1) / Double(syncSteps.count)
    }

    /// 同期中か。
    var isSyncing: Bool {
        if case .syncing = state { return true }
        return false
    }

    /// 直近の同期サマリ (UI 診断用)。差分同期で何件取れたかを各 recordType 単位で記録。
    var lastSyncSummary: SyncSummary?

    struct SyncSummary: Sendable, Equatable {
        let modifiedSince: Date?
        let fetchedByType: [String: Int]
        let totalFetched: Int
        let completedAt: Date

        var modifiedSinceLabel: String {
            modifiedSince?.ISO8601Format() ?? "(full sync)"
        }
    }

    private static let maxRetries = 3

    /// 同期の再入防止 (フォアグラウンド復帰トリガと起動 sync が重ならないように)。
    private var running = false

    // フルsyncの途中再開用。中断 (バックグラウンド suspend 等) されても、
    // 完了済みステップを覚えておき、次回は残りのステップだけ取得する。
    private let pendingFullStartKey = "sync_pending_full_start"   // Double (epoch秒)
    private let pendingFullDoneKey = "sync_pending_full_done"     // [String] recordType

    /// フルsyncが途中 (未完了) で保留されているか。
    var hasPendingFullSync: Bool {
        UserDefaults.standard.object(forKey: pendingFullStartKey) != nil
    }

    /// 同期順序（外部キー依存関係を考慮）
    private let syncSteps: [SyncStep] = [
        // Phase 1: 独立テーブル
        SyncStep(recordType: "Brand", displayName: "ブランド"),
        // Phase 2: brandsのみ依存
        SyncStep(recordType: "Idol", displayName: "アイドル"),
        SyncStep(recordType: "Event", displayName: "イベント"),
        SyncStep(recordType: "ImasUnit", displayName: "ユニット"),
        // Phase 3: 上記に依存 (CastMember/IdolCast は廃止)
        SyncStep(recordType: "IdolBrand", displayName: "アイドル×ブランド"),
        SyncStep(recordType: "Show", displayName: "公演"),
        SyncStep(recordType: "Song", displayName: "楽曲"),
        SyncStep(recordType: "UnitMember", displayName: "ユニットメンバー"),
        // Phase 4: さらに上に依存
        SyncStep(recordType: "SongArtist", displayName: "楽曲アーティスト"),
        SyncStep(recordType: "ShowCast", displayName: "公演キャスト"),
        SyncStep(recordType: "SetlistItem", displayName: "セトリ"),
        // Phase 5: setlist_itemsに依存
        SyncStep(recordType: "SetlistPerformer", displayName: "セトリ出演者"),
        // Phase 6: コミュニティコンテンツ（songsに依存）
        SyncStep(recordType: "SongCall", displayName: "コーレス"),
        SyncStep(recordType: "SongVideo", displayName: "参考動画"),
    ]

    // MARK: - Public Methods

    /// フルSync — 全データをダウンロード（初回 or 強制リフレッシュ）
    func performFullSync(database: AppDatabase) async {
        let bgTask = await UIApplication.shared.beginBackgroundTask(withName: "cloudkit_full_sync")
        defer {
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }
        await performSync(database: database, modifiedSince: nil)
    }

    /// 差分Sync — 前回同期以降の変更のみ
    func performIncrementalSync(database: AppDatabase) async {
        let bgTask = await UIApplication.shared.beginBackgroundTask(withName: "cloudkit_incremental_sync")
        defer {
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }
        do {
            let lastSync = try database.lastSyncDate()
            await performSync(database: database, modifiedSince: lastSync)
        } catch {
            logger.error("lastSyncDate取得失敗: \(error.localizedDescription)")
            await MainActor.run {
                state = .requiresFullResync
            }
        }
    }

    /// アプリ起動時 Sync。 lastFullSyncDate が 24 時間以上前 (or 未設定) なら fullSync、
    /// それ以外は incremental。 差分が大きいテーブル (SongArtist ~20k) で incremental の取りこぼし
    /// が起きないよう、 1 日 1 回は必ず全件取り直す。
    func performStartupSync(database: AppDatabase) async {
        let bgTask = await UIApplication.shared.beginBackgroundTask(withName: "cloudkit_startup_sync")
        defer {
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }
        let shouldFull: Bool
        if hasPendingFullSync {
            // 前回のフルsyncが途中で中断されている → 残りを再開 (フル扱い)。
            shouldFull = true
        } else if let last = (try? database.lastFullSyncDate()) ?? nil {
            shouldFull = Date().timeIntervalSince(last) > 24 * 3600
        } else {
            shouldFull = true
        }
        if shouldFull {
            logger.info("[Sync] startup → full (last full sync stale or absent)")
            await performSync(database: database, modifiedSince: nil)
            try? database.updateLastFullSyncDate(Date())
        } else {
            logger.info("[Sync] startup → incremental")
            do {
                let lastSync = try database.lastSyncDate()
                await performSync(database: database, modifiedSince: lastSync)
            } catch {
                logger.error("lastSyncDate取得失敗: \(error.localizedDescription)")
                await MainActor.run { state = .requiresFullResync }
            }
        }
    }


    // MARK: - Private

    private func performSync(database: AppDatabase, modifiedSince: Date?) async {
        // 再入防止: 既に走っている同期があれば何もしない (二重 fetch を避ける)。
        if running { logger.info("[Sync] skip: already running"); return }
        running = true
        defer { running = false }

        // iCloudアカウント確認
        do {
            let status = try await CloudKitService.shared.accountStatus()
            guard status == .available else {
                await MainActor.run {
                    state = .error("iCloudアカウントが利用できません")
                }
                return
            }
        } catch {
            await MainActor.run {
                state = .error("iCloud状態の確認に失敗: \(error.localizedDescription)")
            }
            return
        }

        let syncStartDate = Date()
        let isFullSync = (modifiedSince == nil)

        // フルsyncは途中再開対応: 中断 (バックグラウンド suspend 等) されても、
        // 開始時刻と完了ステップを永続化しておき、再開時は残りステップだけ取得する。
        let ud = UserDefaults.standard
        let effectiveStart: Date
        var doneSteps: Set<String> = []
        if isFullSync {
            if let saved = ud.object(forKey: pendingFullStartKey) as? Double {
                effectiveStart = Date(timeIntervalSince1970: saved)
                doneSteps = Set(ud.stringArray(forKey: pendingFullDoneKey) ?? [])
                logger.info("[Sync] full RESUME: \(doneSteps.count)/\(self.syncSteps.count) steps already done")
            } else {
                effectiveStart = syncStartDate
                ud.set(syncStartDate.timeIntervalSince1970, forKey: pendingFullStartKey)
                ud.set([String](), forKey: pendingFullDoneKey)
                logger.info("[Sync] full start (modifiedSince=nil)")
            }
        } else {
            effectiveStart = syncStartDate
            logger.info("[Sync] incremental start: modifiedSince=\(modifiedSince!.ISO8601Format())")
        }

        var totalFetched = 0
        var fetchedByType: [String: Int] = [:]
        for step in syncSteps {
            // フルsync再開: 完了済みステップはスキップ。
            if isFullSync && doneSteps.contains(step.recordType) { continue }
            await MainActor.run {
                state = .syncing(step.displayName)
            }

            let ckptKey = "sync_ckpt_\(step.recordType)"
            do {
                // ステップ内チャンクループ: バッチ毎に upsert + チェックポイント保存。
                // 巨大ステップ (SongArtist ~20k 等) が途中中断されても、保存した modifiedAt
                // から再開できる (= 全件取り直さない)。
                var start = (ud.object(forKey: ckptKey) as? Double).map { Date(timeIntervalSince1970: $0) }
                    ?? modifiedSince ?? Date(timeIntervalSince1970: 0)
                var seen = Set<String>()
                while true {
                    let records = try await fetchChunkWithRetry(type: step.recordType, after: start)
                    if records.isEmpty { break }

                    let before = seen.count
                    for r in records { seen.insert(r.recordID.recordName) }
                    let added = seen.count - before

                    // deletedAt フィールドで生存/削除を分割
                    let deleted = records.filter { CKRecordMapper.deletedAt(from: $0) != nil }
                    let alive = records.filter { CKRecordMapper.deletedAt(from: $0) == nil }
                    if !alive.isEmpty {
                        try upsertRecords(alive, type: step.recordType, database: database)
                    }
                    // 削除伝搬は soft delete (deletedAt) 経由のみ。
                    if !deleted.isEmpty {
                        let ids = deleted.map { $0.recordID.recordName }
                        try database.deleteRecords(recordType: step.recordType, ids: ids)
                    }
                    totalFetched += records.count
                    fetchedByType[step.recordType, default: 0] += records.count

                    guard let maxDate = records.compactMap({ $0["modifiedAt"] as? Date }).max() else { break }
                    ud.set(maxDate.timeIntervalSince1970, forKey: ckptKey)   // 途中チェックポイント
                    if added == 0 { break }                                 // 新規ゼロ = 取得完了
                    start = maxDate.addingTimeInterval(-0.001)
                }

                // ステップ完了: チェックポイント削除 + (フルsync) 完了ステップを記録。
                ud.removeObject(forKey: ckptKey)
                if isFullSync {
                    doneSteps.insert(step.recordType)
                    ud.set(Array(doneSteps), forKey: pendingFullDoneKey)
                }
            } catch let ckError as CKError {
                switch ckError.code {
                case .unknownItem:
                    // レコードタイプ未作成 → スキップ
                    continue
                case .invalidArguments:
                    // "Field '...' is not queryable" 等、スキーマ側のインデックス未設定
                    let msg = ckError.localizedDescription
                    let isIndexError = msg.contains("not queryable") || msg.contains("not sortable")
                    if isIndexError {
                        logger.error("[Sync] CloudKit スキーマ未設定 (\(step.recordType)): \(msg)")
                        await MainActor.run {
                            state = .error(
                                "スキーマ設定が必要です: CloudKit Dashboard で \(step.recordType) の modifiedAt を QUERYABLE + SORTABLE に設定してください"
                            )
                        }
                    } else {
                        await MainActor.run {
                            state = .error("\(step.displayName)の同期に失敗: \(msg)")
                        }
                    }
                    return
                default:
                    await MainActor.run {
                        state = .error("\(step.displayName)の同期に失敗: \(ckError.localizedDescription)")
                    }
                    return
                }
            } catch {
                AppAnalytics.event("sync_error")
                await MainActor.run {
                    state = .error("\(step.displayName)の同期に失敗: \(error.localizedDescription)")
                }
                return
            }
        }

        // メタデータ更新。フルsyncは「開始時刻 (再開なら元の開始時刻)」を lastSync にして、
        // 長時間同期の最中に変わったレコードを次回の差分syncで拾えるようにする。
        let lastSyncToSave = isFullSync ? effectiveStart : syncStartDate
        do {
            try database.updateLastSyncDate(lastSyncToSave)
        } catch {
            await MainActor.run {
                state = .error("同期日時の保存に失敗: \(error.localizedDescription)")
            }
            return
        }

        // フルsync完了: 途中再開用の保留状態をクリア。
        if isFullSync {
            ud.removeObject(forKey: pendingFullStartKey)
            ud.removeObject(forKey: pendingFullDoneKey)
        }

        logger.info("[Sync] complete: total fetched=\(totalFetched), lastSync→\(lastSyncToSave.ISO8601Format())")

        let summary = SyncSummary(
            modifiedSince: modifiedSince,
            fetchedByType: fetchedByType,
            totalFetched: totalFetched,
            completedAt: Date()
        )
        await MainActor.run {
            lastSyncSummary = summary
            state = .completed(syncStartDate)
        }
    }

    /// リトライ付きチャンク fetch (modifiedAt > after を最大数ページ分)。途中再開ループで使う。
    private func fetchChunkWithRetry(type: String, after startDate: Date) async throws -> [CKRecord] {
        var lastError: Error?
        for attempt in 0..<Self.maxRetries {
            do {
                return try await CloudKitService.shared.fetchChunk(type: type, after: startDate)
            } catch let ckError as CKError {
                switch ckError.code {
                case .networkUnavailable, .networkFailure, .serviceUnavailable, .zoneBusy, .requestRateLimited:
                    lastError = ckError
                    let retryAfter = ckError.retryAfterSeconds ?? Double(2 << attempt)
                    logger.warning("[Sync] \(type) chunk attempt \(attempt + 1) failed (\(ckError.code.rawValue)), retry after \(retryAfter)s")
                    try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                default:
                    throw ckError
                }
            }
        }
        throw lastError!
    }

    /// CKRecordをモデルに変換してDBにupsert。無効レコードはcompactMapでスキップ。
    private func upsertRecords(_ records: [CKRecord], type: String, database: AppDatabase) throws {
        func mapped<T>(_ transform: (CKRecord) -> T?) -> [T] {
            records.compactMap { record in
                let result = transform(record)
                if result == nil {
                    logger.warning("ckrecord_invalid type=\(type) recordName=\(record.recordID.recordName)")
                }
                return result
            }
        }
        switch type {
        case "Brand":
            try database.upsertBrands(mapped(CKRecordMapper.brand))
        case "Idol":
            try database.upsertIdols(mapped(CKRecordMapper.idol))
        case "CastMember":
            // Cast テーブル廃止: 旧 CK レコードは無視。
            break
        case "Event":
            try database.upsertEvents(mapped(CKRecordMapper.event))
        case "ImasUnit":
            try database.upsertUnits(mapped(CKRecordMapper.unit))
        case "IdolCast":
            // IdolCast 廃止: voiceActors に統合済み。
            break
        case "IdolBrand":
            try database.upsertIdolBrands(mapped(CKRecordMapper.idolBrand))
        case "Show":
            try database.upsertShows(mapped(CKRecordMapper.show))
        case "Song":
            try database.upsertSongs(mapped(CKRecordMapper.song))
        case "UnitMember":
            try database.upsertUnitMembers(mapped(CKRecordMapper.unitMember))
        case "SongArtist":
            try database.upsertSongArtists(mapped(CKRecordMapper.songArtist))
        case "ShowCast":
            try database.upsertShowCasts(mapped(CKRecordMapper.showCast))
        case "SetlistItem":
            try database.upsertSetlistItems(mapped(CKRecordMapper.setlistItem))
        case "SetlistPerformer":
            try database.upsertSetlistPerformers(mapped(CKRecordMapper.setlistPerformer))
        case "SongCall":
            try database.upsertSongCalls(mapped(CKRecordMapper.songCall))
        case "SongVideo":
            try database.upsertSongVideos(mapped(CKRecordMapper.songVideo))
        default:
            break
        }
    }
}
