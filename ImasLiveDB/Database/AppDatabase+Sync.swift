//  AppDatabase の CloudKit Sync Upsert Methods / SongCall / SongVideo Methods / CloudKit Sync Delete Methods / Sync Metadata を切り出したもの。
//  分割の意図と分割線の引き方は docs/ARCHITECTURE.md を参照。
//  ここにあるのは移動してきたクエリだけで、ロジックは 1 行も変えていない。

import Foundation
import GRDB
import os

private let syncUpsertLogger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "SyncUpsert")

extension AppDatabase {

    // MARK: - CloudKit Sync Upsert Methods

    /// 全レコードを1トランザクション内に一括 upsert する。メモリ節約のためチャンク単位で処理。
    ///
    /// WHY upsert (INSERT ON CONFLICT DO UPDATE) not insert(onConflict: .replace):
    /// REPLACE は既存行を DELETE→INSERT するため、foreign_keys=ON 環境では
    /// ON DELETE CASCADE の子テーブル (song_artists / setlist_items / setlist_performers /
    /// unit_members 等) を巻き込んで削除する。増分 Pull で親レコードのメタだけ来た場合に
    /// 原唱者情報等が消える。upsert は行を更新するだけなので CASCADE を発火させない。
    ///
    /// WHY per-record savepoint: CloudKit の同期データは他ユーザーのコミュニティ編集も含む
    /// 外部境界の入力であり、親レコード未着 (取りこぼし) や不整合な参照が混ざりうる。
    /// savepoint 無しで1件が FK 違反すると `dbQueue.write` の外側トランザクション全体が
    /// ロールバックされ、そのステップの他の正常なレコードまで全滅する。さらに次回起動でも
    /// 同じ差分範囲を再取得して同じ行で失敗し続け、実質そのユーザーの同期が永久に止まる。
    /// 1件ずつ savepoint で保護し、違反した行だけ捨てて続行する。
    private func upsertChunked<T: PersistableRecord>(_ records: [T], chunkSize: Int = 500) throws {
        try dbQueue.write { db in try Self.upsertChunkedQuery(db, records, chunkSize) }
    }

    /// (async) upsertChunked の非同期版。cooperative thread pool をブロックしない。
    /// リポジトリ経由の書き込み (upsertEvents/Shows/Idols/Songs/SongArtists/SetlistItems) から使う。
    private func upsertChunkedAsync<T: PersistableRecord & Sendable>(_ records: [T], chunkSize: Int = 500) async throws {
        try await dbQueue.write { db in try Self.upsertChunkedQuery(db, records, chunkSize) }
    }

    private static func upsertChunkedQuery<T: PersistableRecord>(_ db: Database, _ records: [T], _ chunkSize: Int) throws {
        for chunk in records.chunks(ofCount: chunkSize) {
            for record in chunk {
                do {
                    try db.inSavepoint {
                        try record.upsert(db)
                        return .commit
                    }
                } catch {
                    syncUpsertLogger.error("upsert skip (\(T.databaseTableName)): \(error.localizedDescription)")
                }
            }
        }
    }

    func upsertBrands(_ brands: [Brand]) throws { try upsertChunked(brands) }
    func upsertIdols(_ idols: [Idol]) throws { try upsertChunked(idols) }
    func upsertIdolsAsync(_ idols: [Idol]) async throws { try await upsertChunkedAsync(idols) }
    func upsertEvents(_ events: [Event]) throws { try upsertChunked(events) }
    func upsertEventsAsync(_ events: [Event]) async throws { try await upsertChunkedAsync(events) }
    func upsertVenues(_ venues: [Venue]) throws { try upsertChunked(venues) }
    func upsertCreators(_ rows: [Creator]) throws { try upsertChunked(rows) }
    func upsertUnitVersions(_ versions: [UnitVersion]) throws { try upsertChunked(versions) }
    func upsertVenueNames(_ names: [VenueName]) throws { try upsertChunked(names) }
    func upsertVenueHalls(_ halls: [VenueHall]) throws { try upsertChunked(halls) }
    func upsertShows(_ shows: [Show]) throws { try upsertChunked(shows) }
    func upsertShowsAsync(_ shows: [Show]) async throws { try await upsertChunkedAsync(shows) }
    func upsertSongs(_ songs: [Song]) throws { try upsertChunked(songs) }
    func upsertSongsAsync(_ songs: [Song]) async throws { try await upsertChunkedAsync(songs) }
    func upsertUnits(_ units: [Unit]) throws { try upsertChunked(units) }
    func upsertIdolBrands(_ idolBrands: [IdolBrand]) throws { try upsertChunked(idolBrands) }
    func upsertSongArtists(_ songArtists: [SongArtist]) throws { try upsertChunked(songArtists) }
    func upsertSongArtistsAsync(_ songArtists: [SongArtist]) async throws { try await upsertChunkedAsync(songArtists) }
    func upsertUnitMembers(_ unitMembers: [UnitMember]) throws { try upsertChunked(unitMembers) }
    func upsertShowCasts(_ showCasts: [ShowCast]) throws { try upsertChunked(showCasts) }
    func upsertSetlistItems(_ setlistItems: [SetlistItem]) throws { try upsertChunked(setlistItems) }
    func upsertSetlistItemsAsync(_ setlistItems: [SetlistItem]) async throws { try await upsertChunkedAsync(setlistItems) }
    func upsertSetlistPerformers(_ setlistPerformers: [SetlistPerformer]) throws { try upsertChunked(setlistPerformers) }

    /// 編集 UI 用: 全曲を id+title だけのコンパクト型で返す。
    func fetchAllSongsForPickerAsync() async throws -> [PickedSong] {
        try await dbQueue.read { db in try Self.fetchAllSongsForPickerQuery(db) }
    }

    private static func fetchAllSongsForPickerQuery(_ db: Database) throws -> [PickedSong] {
        let rows = try Row.fetchAll(db, sql: "SELECT id, title, title_kana FROM songs ORDER BY title")
        return rows.map { PickedSong(id: $0["id"], title: $0["title"], titleKana: $0["title_kana"]) }
    }

    /// あいまい検索の母集団 (曲名 + 読み)。
    ///
    /// 並びは問わない (コアが照合して並べ直す)。実体を読まないので安い。
    ///
    /// `brand_id = 'other'` (歌枠カバー等) は除く。曲一覧が既定でこれを隠しており
    /// (`SongSearchFilter.includeOtherBrand`)、あいまい候補にだけ出てくると
    /// 「一覧に無い曲が『もしかして』に並ぶ」ことになる。
    /// `IS NOT` にしているのは、brand_id が NULL の曲を落とさないため (`<>` だと NULL は偽)。
    func fetchSongSpellingsAsync() async throws -> [SongSpelling] {
        try await dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT id, title, title_kana FROM songs WHERE brand_id IS NOT 'other'")
                .map { SongSpelling(id: $0["id"], title: $0["title"], titleKana: $0["title_kana"]) }
        }
    }

    /// 編集 UI 用: 出演者 picker に出す全アイドル (sort_order 順)。
    /// Cast 廃止により idol を直接返すようになった。
    func fetchAllIdolsForPickerAsync() async throws -> [Idol] {
        try await dbQueue.read { db in try Self.fetchAllIdolsForPickerQuery(db) }
    }

    private static func fetchAllIdolsForPickerQuery(_ db: Database) throws -> [Idol] {
        try Idol.order(Column("sort_order")).fetchAll(db)
    }

    /// admin 編集: 指定 show の setlist を完全置換 (旧 items/performers 削除 → 新 items/performers 挿入)。
    /// CloudKit 側書き込み成功後にローカル DB を一致させるために呼ぶ。
    func replaceSetlist(showId: String, items: [SetlistItem], performers: [SetlistPerformer]) throws {
        try dbQueue.write { db in try Self.replaceSetlistQuery(db, showId: showId, items: items, performers: performers) }
    }

    /// (async) admin 編集: 指定 show の setlist を完全置換。cooperative thread pool をブロックしない。
    func replaceSetlistAsync(showId: String, items: [SetlistItem], performers: [SetlistPerformer]) async throws {
        try await dbQueue.write { db in try Self.replaceSetlistQuery(db, showId: showId, items: items, performers: performers) }
    }

    private static func replaceSetlistQuery(_ db: Database, showId: String, items: [SetlistItem], performers: [SetlistPerformer]) throws {
        try db.execute(
            sql: """
                DELETE FROM setlist_performers
                WHERE setlist_item_id IN (SELECT id FROM setlist_items WHERE show_id = ?)
                """,
            arguments: [showId]
        )
        try db.execute(sql: "DELETE FROM setlist_items WHERE show_id = ?", arguments: [showId])
        for item in items {
            try item.insert(db, onConflict: .replace)
        }
        for performer in performers {
            try performer.insert(db, onConflict: .replace)
        }
    }

    // MARK: - SongCall / SongVideo Methods

    func upsertSongCalls(_ calls: [SongCall]) throws {
        try upsertAll(calls)
    }

    func upsertSongCallsAsync(_ calls: [SongCall]) async throws {
        try await upsertAllAsync(calls)
    }

    func fetchCallResponsesForSongAsync(songId: String) async throws -> [SongCall] {
        try await fetchBySongIdAsync(songId)
    }

    func upsertSongVideos(_ videos: [SongVideo]) throws {
        try upsertAll(videos)
    }

    func upsertSongVideosAsync(_ videos: [SongVideo]) async throws {
        try await upsertAllAsync(videos)
    }

    func fetchVideosForSongAsync(songId: String) async throws -> [SongVideo] {
        try await fetchBySongIdAsync(songId)
    }

    // WHY upsert: REPLACE の DELETE→INSERT は ON DELETE CASCADE を発火させ子行を消す。
    // 行更新の upsert で回避する (upsertChunked と同じ理由)。
    private func upsertAll<T: PersistableRecord>(_ records: [T]) throws {
        try dbQueue.write { db in try Self.upsertAllQuery(db, records) }
    }

    private func upsertAllAsync<T: PersistableRecord & Sendable>(_ records: [T]) async throws {
        try await dbQueue.write { db in try Self.upsertAllQuery(db, records) }
    }

    private static func upsertAllQuery<T: PersistableRecord>(_ db: Database, _ records: [T]) throws {
        for record in records {
            try record.upsert(db)
        }
    }

    private func fetchBySongId<T: FetchableRecord & TableRecord>(_ songId: String) throws -> [T] {
        try dbQueue.read { db in try Self.fetchBySongIdQuery(db, songId) }
    }

    private func fetchBySongIdAsync<T: FetchableRecord & TableRecord & Sendable>(_ songId: String) async throws -> [T] {
        try await dbQueue.read { db in try Self.fetchBySongIdQuery(db, songId) }
    }

    private static func fetchBySongIdQuery<T: FetchableRecord & TableRecord>(_ db: Database, _ songId: String) throws -> [T] {
        try T.filter(Column("song_id") == songId)
            .order(Column("created_at").desc)
            .fetchAll(db)
    }

    // MARK: - CloudKit Sync Delete Methods

    /// soft delete: CloudKit の deletedAt 付きレコードをローカルDBから物理削除する。
    /// 単一 PK は ids = [recordName] 直接、複合 PK は recordName を split して WHERE col1=? AND col2=? で削除。
    ///
    /// recordType → (table 名, PK カラム) の対応と、複合 PK の recordName
    /// "{table}-{pk1}-{pk2}" (seed_cloudkit.py の make_record_name と一致) の分解規則は
    /// imas-core (Rust) の `domain/sync_planning.rs`。DELETE 文の組み立てだけ Swift に残す
    /// (SQL 方言と GRDB の引数バインドは OS 側の責務)。
    func deleteRecords(recordType: String, ids: [String]) throws {
        guard !ids.isEmpty, let info = syncTableInfo(recordType: recordType) else { return }
        try dbQueue.write { db in
            if info.pkColumns.count == 1 {
                let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
                try db.execute(
                    sql: "DELETE FROM \(info.table) WHERE \(info.pkColumns[0]) IN (\(placeholders))",
                    arguments: StatementArguments(ids)
                )
            } else {
                // 複合 PK: recordName を分解
                let whereClause = info.pkColumns.map { "\($0) = ?" }.joined(separator: " AND ")
                for recordName in ids {
                    guard let parts = syncParseCompositeRecordName(
                        recordName: recordName,
                        table: info.table,
                        pkCount: UInt32(info.pkColumns.count)
                    ) else { continue }
                    try db.execute(
                        sql: "DELETE FROM \(info.table) WHERE \(whereClause)",
                        arguments: StatementArguments(parts)
                    )
                }
            }
        }
    }

    /// orphan 削除: fullSync 時に CloudKit に存在しない ID をローカルDBから削除する (safety net)
    /// validIds が空の場合は何もしない（全件削除を防ぐため）
    ///
    /// 「掃除してよい recordType か」「どの ID が孤児か」の判定は共有コア
    /// (`domain/sync_planning.rs`)。取得 0 件でローカルを全消去しない安全弁もそちら側。
    func deleteOrphans(recordType: String, validIds: Set<String>) throws {
        guard !validIds.isEmpty, let info = syncTableInfo(recordType: recordType) else { return }
        // 複合 PK テーブル (song_artists 等) には単一の "id" 列が無く `SELECT id FROM ...` が
        // 例外を投げるため、単一 PK テーブルのみ対象にするガード。
        guard syncSupportsOrphanCleanup(recordType: recordType) else { return }
        let table = info.table
        let valid = Array(validIds)
        try dbQueue.write { db in
            // ローカルの全 ID を取得して差分を計算
            let localIds = try String.fetchAll(db, sql: "SELECT id FROM \(table)")
            let orphanIds = syncOrphanIds(localIds: localIds, validIds: valid)
            guard !orphanIds.isEmpty else { return }
            let placeholders = orphanIds.map { _ in "?" }.joined(separator: ", ")
            try db.execute(
                sql: "DELETE FROM \(table) WHERE id IN (\(placeholders))",
                arguments: StatementArguments(orphanIds)
            )
            Logger.sync.info("orphan_deleted: \(recordType) count=\(orphanIds.count)")
        }
    }

    // MARK: - Sync Metadata

    func updateLastSyncDate(_ date: Date) throws {
        try dbQueue.write { db in
            try Meta.setValue(db, ISO8601DateFormatter.shared.string(from: date), forKey: "last_sync_at")
        }
    }

    func lastSyncDate() throws -> Date? {
        let value = try fetchMetaValue(forKey: "last_sync_at")
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter.shared.date(from: value)
    }

    /// 直近の fullSync (modifiedSince=nil) 実行日時。
    /// 24時間以上経過したら起動時に再度 fullSync する判定に使う。
    func updateLastFullSyncDate(_ date: Date) throws {
        try dbQueue.write { db in
            try Meta.setValue(db, ISO8601DateFormatter.shared.string(from: date), forKey: "last_full_sync_at")
        }
    }

    func lastFullSyncDate() throws -> Date? {
        let value = try fetchMetaValue(forKey: "last_full_sync_at")
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter.shared.date(from: value)
    }

}
