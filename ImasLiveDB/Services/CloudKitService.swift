import Foundation
import CloudKit

/// CloudKit操作のactor-basedラッパー
actor CloudKitService {
    static let shared = CloudKitService()

    private let container = CKContainer(identifier: "iCloud.com.fugaif.ImasLiveDB")
    private var publicDB: CKDatabase { container.publicCloudDatabase }

    /// レコードの最大取得件数（CloudKit制限）
    private let queryLimit = 400

    // MARK: - Fetch Operations

    /// レコードをページネーション付きで取得
    func fetchRecords(
        type: String,
        predicate: NSPredicate = NSPredicate(value: true),
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil
    ) async throws -> [CKRecord] {
        let query = CKQuery(recordType: type, predicate: predicate)
        query.sortDescriptors = sortDescriptors

        let effectiveLimit = min(limit ?? queryLimit, queryLimit)

        let (results, _) = try await publicDB.records(
            matching: query,
            resultsLimit: effectiveLimit
        )

        return try results.map { try $0.1.get() }
    }

    /// 指定タイプの全レコードを自動ページネーションで取得
    func fetchAllRecords(type: String, modifiedSince: Date? = nil) async throws -> [CKRecord] {
        // 単純な「modifiedAt > X + cursor pagination + sort modifiedAt ASC」だと、
        // 同じ modifiedAt を持つ record が page 境界に集中するケースで cursor 切替時に
        // 一部 record が落ちる。`___recordName` を secondary sort に使うのが本筋だが
        // Sortable index 設定が必要で運用コストが高いため、ここでは外側のループで
        // 「直前バッチの最大 modifiedAt - 1ms」を起点に再クエリしながら recordName
        // で dedup する方式にする。境界に重複が出るが dedup で吸収。
        //
        // 注: TRUEPREDICATE は CloudKit が内部的に recordName を sort key として使うため、
        // recordName が Queryable に index 設定されていないと「Field 'recordName' is not
        // marked queryable」 エラー。 modifiedAt > 1970-01-01 で全件取得する方式が安全。

        var collected: [String: CKRecord] = [:]
        var startDate = modifiedSince ?? Date(timeIntervalSince1970: 0)
        // SongArtist (~20k 件) など差分が大きい時に取りこぼさないよう余裕を持たせる。
        // maxIterations は「直前バッチの最大 modifiedAt - 1ms」を起点に再クエリする外周ループの
        // 回数上限 (総件数の上限ではない)。各外周内では cursor pagination で queryLimit (=400) 件
        // ずつ取得する。境界に出る重複は recordName dedup で吸収する。
        let maxIterations = 200

        for _ in 0..<maxIterations {
            let predicate = NSPredicate(format: "modifiedAt > %@", startDate as NSDate)
            let query = CKQuery(recordType: type, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: true)]

            var batch: [CKRecord] = []
            var cursor: CKQueryOperation.Cursor?
            let (initialResults, initialCursor) = try await publicDB.records(
                matching: query,
                resultsLimit: queryLimit
            )
            batch.append(contentsOf: try initialResults.map { try $0.1.get() })
            cursor = initialCursor

            while let currentCursor = cursor {
                let (results, nextCursor) = try await publicDB.records(
                    continuingMatchFrom: currentCursor,
                    resultsLimit: queryLimit
                )
                batch.append(contentsOf: try results.map { try $0.1.get() })
                cursor = nextCursor
            }

            if batch.isEmpty { break }
            let beforeCount = collected.count
            for record in batch {
                collected[record.recordID.recordName] = record
            }
            let added = collected.count - beforeCount

            // 1 件も新規追加が無ければ全件取得済みとみなして終了
            if added == 0 { break }

            // 次回起点: 今回 batch の最大 modifiedAt から 1ms 引く
            // (境界の record を取りこぼさず、dedup で重複排除)
            guard let maxDate = batch.compactMap({ $0["modifiedAt"] as? Date }).max() else { break }
            startDate = maxDate.addingTimeInterval(-0.001)
        }

        return Array(collected.values)
    }

    /// modifiedAt > startDate のレコードを「最大 maxPages ページ分だけ」取得し、続きがあれば
    /// 継続用の cursor も返す。呼び出し側 (SyncEngine) がこれを繰り返し呼び、バッチごとに
    /// upsert + チェックポイント保存することで、巨大ステップが途中中断されても再開できる。
    ///
    /// `continuing` に前回の cursor を渡すと、新しいクエリを張り直さず同じクエリの続きを取得する。
    /// これが無いと `start = maxDate - 1ms` で張り直すため、**同一 modifiedAt のレコードが
    /// 1 チャンク (maxPages×queryLimit) を超える**ケースで、張り直したクエリが毎回同じ先頭
    /// チャンクを返して新規ゼロで打ち切られ、それ以降のレコードが永久に欠落する。
    /// cursor で読み切ってから start を進めることで、単一 modifiedAt が何件あっても取りこぼさない。
    func fetchChunk(
        type: String,
        after startDate: Date,
        continuing inCursor: CKQueryOperation.Cursor? = nil,
        maxPages: Int = 3
    ) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        var batch: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        var pages = 0

        if let inCursor {
            // 同一クエリの続き (単一 modifiedAt がチャンク超のケースを cursor で読み切る)。
            cursor = inCursor
        } else {
            let predicate = NSPredicate(format: "modifiedAt > %@", startDate as NSDate)
            let query = CKQuery(recordType: type, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: true)]
            let (initialResults, initialCursor) = try await publicDB.records(
                matching: query, resultsLimit: queryLimit
            )
            batch.append(contentsOf: try initialResults.map { try $0.1.get() })
            cursor = initialCursor
            pages = 1
        }

        while let currentCursor = cursor, pages < maxPages {
            let (results, nextCursor) = try await publicDB.records(
                continuingMatchFrom: currentCursor, resultsLimit: queryLimit
            )
            batch.append(contentsOf: try results.map { try $0.1.get() })
            cursor = nextCursor
            pages += 1
        }
        // cursor が非 nil なら「このクエリにまだ続きがある」= 呼び出し側は同じ cursor で継続する。
        return (batch, cursor)
    }

    /// 現在のiCloudユーザーのレコードIDを取得
    func fetchUserRecordID() async throws -> CKRecord.ID? {
        try await container.userRecordID()
    }

    /// recordName を直接指定して取得 (lookup API)。
    /// CKQuery (predicate ベース) で取りこぼされる recordName を救済するための逃げ道。
    /// 401 ms 単位のレートリミット回避のため、最大 200 件を 1 batch で投げる。
    func fetchByRecordNames(_ recordNames: [String]) async throws -> [CKRecord] {
        guard !recordNames.isEmpty else { return [] }
        var results: [CKRecord] = []
        let chunkSize = 200
        for chunkStart in stride(from: 0, to: recordNames.count, by: chunkSize) {
            let chunk = Array(recordNames[chunkStart..<min(chunkStart + chunkSize, recordNames.count)])
            let ids = chunk.map { CKRecord.ID(recordName: $0) }
            let dict = try await publicDB.records(for: ids)
            for (_, result) in dict {
                if case .success(let record) = result {
                    results.append(record)
                }
            }
        }
        return results
    }

    /// デバッグ用 — `showId == X` で SetlistItem を query。
    /// modifiedAt 経由の query が iOS SDK バグで取りこぼす場合の検証用。
    func debugFetchSetlistItemsByShowId(_ showId: String) async throws -> [CKRecord] {
        let predicate = NSPredicate(format: "showId == %@", showId)
        let query = CKQuery(recordType: "SetlistItem", predicate: predicate)
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        let (initial, initialCursor) = try await publicDB.records(matching: query, resultsLimit: 400)
        records.append(contentsOf: try initial.map { try $0.1.get() })
        cursor = initialCursor
        while let c = cursor {
            let (next, nextCursor) = try await publicDB.records(continuingMatchFrom: c, resultsLimit: 400)
            records.append(contentsOf: try next.map { try $0.1.get() })
            cursor = nextCursor
        }
        return records
    }

    /// iCloudアカウントの状態を確認
    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    // MARK: - Write Operations
    // CloudKit Public DB への直接書き込みは廃止。 マスタ編集は EditService (POST /edits)
    // 経由でサーバ側 S2S 認証を借用する (一般 iCloud ユーザは他人 (Server Token)
    // 所有レコードを更新できないため)。 抜け穴を残さないよう saveAndDelete は削除済。
}
