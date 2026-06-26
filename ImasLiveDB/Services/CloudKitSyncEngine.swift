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
        if let last = (try? database.lastFullSyncDate()) ?? nil {
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
        if let modifiedSince {
            logger.info("[Sync] incremental start: modifiedSince=\(modifiedSince.ISO8601Format())")
        } else {
            logger.info("[Sync] full start (modifiedSince=nil)")
        }

        var totalFetched = 0
        var fetchedByType: [String: Int] = [:]
        for step in syncSteps {
            await MainActor.run {
                state = .syncing(step.displayName)
            }

            do {
                let records = try await fetchWithRetry(
                    type: step.recordType,
                    modifiedSince: modifiedSince
                )

                if !records.isEmpty {
                    totalFetched += records.count
                    fetchedByType[step.recordType] = records.count
                    let atCount = records.filter { $0.recordID.recordName.contains("@") }.count
                    logger.info("[Sync] \(step.recordType): fetched \(records.count) (\(atCount) with @)")
                    if step.recordType == "Event" {
                        let ml13 = records.first { $0.recordID.recordName == "ev_the_idolm@ster_million_live_13thlive" }
                        if let ml13 {
                            logger.info("[Sync] ML 13thLIVE found: name=\(String(describing: ml13["name"])) brandId=\(String(describing: ml13["brandId"])) kind=\(String(describing: ml13["kind"]))")
                        } else {
                            logger.warning("[Sync] ML 13thLIVE NOT in fetched Event batch")
                        }
                    }
                }
                guard !records.isEmpty else { continue }

                // deletedAt フィールドで生存/削除を分割
                let deleted = records.filter { CKRecordMapper.deletedAt(from: $0) != nil }
                let alive = records.filter { CKRecordMapper.deletedAt(from: $0) == nil }

                // 生存レコードを upsert
                if !alive.isEmpty {
                    try upsertRecords(alive, type: step.recordType, database: database)
                }

                // soft delete 済みレコードをローカルから物理削除（削除伝搬）
                if !deleted.isEmpty {
                    let ids = deleted.map { $0.recordID.recordName }
                    try database.deleteRecords(recordType: step.recordType, ids: ids)
                    logger.info("[Sync] \(step.recordType): soft-deleted \(ids.count) record(s)")
                }

                // 旧仕様で fullSync 時に「CloudKit にない ID をローカルから消す」処理を
                // 入れていたが、CloudKit fetchAllRecords が cursor pagination で全件
                // 揃わない (modifiedAt 同値衝突等) ケースに当たると、部分取得結果を
                // valid 全集合とみなしてローカルの大半 (例: setlist_items 全部) を
                // orphan として削除してしまう致命バグがあった。削除伝搬は soft delete
                // (deletedAt フィールド) 経由のみ受け付ける。
                _ = isFullSync
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

        // メタデータ更新
        do {
            try database.updateLastSyncDate(syncStartDate)
        } catch {
            await MainActor.run {
                state = .error("同期日時の保存に失敗: \(error.localizedDescription)")
            }
            return
        }

        logger.info("[Sync] complete: total fetched=\(totalFetched), lastSync→\(syncStartDate.ISO8601Format())")

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

    /// リトライ付きfetch（.networkUnavailable/.networkFailure/.serviceUnavailable/.zoneBusy/.requestRateLimited → 最大3回）
    private func fetchWithRetry(type: String, modifiedSince: Date?) async throws -> [CKRecord] {
        var lastError: Error?
        for attempt in 0..<Self.maxRetries {
            do {
                return try await CloudKitService.shared.fetchAllRecords(
                    type: type,
                    modifiedSince: modifiedSince
                )
            } catch let ckError as CKError {
                switch ckError.code {
                case .networkUnavailable, .networkFailure, .serviceUnavailable, .zoneBusy, .requestRateLimited:
                    lastError = ckError
                    let retryAfter = ckError.retryAfterSeconds ?? Double(2 << attempt)
                    logger.warning("[Sync] \(type) attempt \(attempt + 1) failed (\(ckError.code.rawValue)), retry after \(retryAfter)s")
                    try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                case .unknownItem:
                    throw ckError
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
