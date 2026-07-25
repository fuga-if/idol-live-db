import Foundation
import GRDB
import Observation
import os

@Observable
final class AppDatabase: @unchecked Sendable {
    /// シングルトン
    static let shared = AppDatabase()

    /// データベース書き込み口（WALモードの DatabasePool）。
    /// `DatabasePool` は WAL のリーダ/ライタ並行を活かし、同期や reseed の長尺 write 中も
    /// 一覧/詳細の read が WAL スナップショットから並行実行される。型は `any DatabaseWriter`
    /// にして、テストでは in-memory な `DatabaseQueue` を注入できるようにする。
    let dbQueue: any DatabaseWriter

    /// reseed の共有状態。起動時の DB セットアップ (非 MainActor) から書き込まれ、
    /// マイページ診断や起動アラートから読まれるため、`OSAllocatedUnfairLock` で保護する
    /// (旧 `nonisolated(unsafe) static var` のデータ競合対策)。
    private struct ReseedState: Sendable {
        var summary: String = "未実行"
        /// non-nil の間はユーザー可視のアラート対象 (reseed が失敗した)。
        var failureDetail: String?
    }
    private static let reseedState = OSAllocatedUnfairLock(initialState: ReseedState())

    /// 最後の reseedMasterTablesIfNeeded の結果サマリ。 マイページ診断で表示する。
    static var lastReseedStatus: String {
        reseedState.withLock { $0.summary }
    }
    /// reseed が失敗した場合のユーザー可視メッセージ (成功時は nil)。起動アラートに使う。
    static var lastReseedFailure: String? {
        reseedState.withLock { $0.failureDetail }
    }

    /// 起動時 reseed が失敗した場合のユーザー可視メッセージ。UI 監視用に init 時点で確定する。
    /// (静的状態を @Observable なインスタンスに写して、起動フローの alert から参照できるようにする)
    var reseedFailureMessage: String?

    private init() {
        do {
            self.dbQueue = try Self.openDatabase()
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
        self.reseedFailureMessage = Self.lastReseedFailure
    }

    /// テスト用イニシャライザ
    init(dbQueue: any DatabaseWriter) throws {
        self.dbQueue = dbQueue
    }

    // MARK: - Database Setup

    /// PRAGMA integrity_check が "ok" でなければ DB ファイルを削除して例外を投げる。
    /// 次回起動時に Bundle DB から再コピーされる。
    private static func verifyIntegrityOrDelete(at url: URL) throws {
        var roConfig = Configuration()
        roConfig.readonly = true
        let queue = try DatabaseQueue(path: url.path, configuration: roConfig)
        let result = try queue.read { db in
            // quick_check は integrity_check の約6倍高速 (ページ単位の構造検査)。
            // 正常時の戻り値 "ok" は同じなので判定はそのまま流用できる。
            try String.fetchOne(db, sql: "PRAGMA quick_check")
        }
        if result != "ok" {
            try? FileManager.default.removeItem(at: url)
            Logger.database.error("bundle_db_integrity_failed: \(result ?? "nil", privacy: .public)")
            throw NSError(
                domain: "AppDatabase",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Bundle DB integrity_check failed: \(result ?? "nil")"]
            )
        }
    }

    private static func openDatabase() throws -> DatabasePool {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbURL = documentsURL.appendingPathComponent("master.sqlite")

        // 接続ごとに適用する共通設定。DatabasePool は WAL を自動で有効化するため、
        // ここでは foreign_keys を明示 ON にする (DEBUG では SQL トレースも仕込む)。
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            #if DEBUG
            db.trace(options: .statement) { event in
                Logger.database.debug("sql: \(event.description)")
            }
            #endif
        }
        // デフォルト 5 だと、詳細画面の async let 並行 fetch (4並行程度) に一覧画面や
        // カレンダー等の同時読み込みが重なるとリーダー接続を奪い合い、GRDB 内部で
        // read の順番待ちが発生する (cooperative pool 自体は解放されるが体感レイテンシが伸びる)。
        // 実運用の最大同時読み込み想定 (詳細画面の fan-out 4 + 一覧/カレンダー等の並行読み込み
        // 数本) をまかなえるよう、デフォルトの2倍の 10 を確保する。書き込みは write 側の
        // 単一コネクションのみを使うため増やしても衝突リスクは増えない。
        config.maximumReaderCount = 10

        if let bundleURL = Bundle.main.url(forResource: "master", withExtension: "sqlite") {
            if !fileManager.fileExists(atPath: dbURL.path) {
                try fileManager.copyItem(at: bundleURL, to: dbURL)
                // 万一 Bundle DB が破損していたら検知して削除。コード署名で
                // 起こり得ない前提だが、破損したまま起動するより停止する方が安全。
                try verifyIntegrityOrDelete(at: dbURL)
            }
        } else if !fileManager.fileExists(atPath: dbURL.path) {
            let pool = try DatabasePool(path: dbURL.path, configuration: config)
            try DatabaseMigrations.migrator.migrate(pool)
            return pool
        }

        let pool = try DatabasePool(path: dbURL.path, configuration: config)
        try seedMigrationHistoryIfNeeded(pool)
        try DatabaseMigrations.migrator.migrate(pool)
        // event.kind の再適用は CloudKit pull 直後に効けばよい定常処理。毎起動で同期 UPDATE を
        // 走らせるとメインスレッドを数十〜数百ms 塞ぐため、バックグラウンドに退避する。
        Task.detached(priority: .utility) { [pool] in
            do {
                try reseedEventKindIfNeeded(pool)
            } catch {
                Logger.database.error("reseedEventKindIfNeeded failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // reseedMasterTablesIfNeeded は破壊的 (DELETE + INSERT) なので失敗時はアプリ
        // 起動自体を止めないように吸収する。 失敗してもローカル DB の旧値で動作継続。
        do {
            try reseedMasterTablesIfNeeded(pool)
        } catch {
            let detail = "\(error.localizedDescription) | \(String(describing: error))"
            reseedState.withLock {
                $0.summary = "失敗: \(detail)"
                // ユーザーには「マスタ更新が反映されず旧データで動作している」ことを伝える。
                $0.failureDetail = "最新のデータ更新の取り込みに失敗しました。アプリを再起動しても直らない場合は再インストールをお試しください。\n(詳細: \(error.localizedDescription))"
            }
            Logger.database.error("reseedMasterTablesIfNeeded failed: \(detail, privacy: .public)")
        }
        return pool
    }

    /// Bundle DB の data_version が Documents DB より新しいときに、 マスタテーブル一式を
    /// Bundle DB の内容で上書きする。 既存ユーザの Documents DB に古い show_cast 等が
    /// 残ったままでマスタ更新が反映されない問題への対処。
    /// user_marks (担当/お気に入り/メモ/attended) や custom_image_paths など、 ユーザ
    /// 固有のデータは触らない。
    private static func reseedMasterTablesIfNeeded(_ dbQueue: any DatabaseWriter) throws {
        guard let bundleURL = Bundle.main.url(forResource: "master", withExtension: "sqlite") else {
            Logger.database.info("[reseed] bundle master.sqlite not found, skip")
            return
        }
        // Bundle 内は read-only 領域なので GRDB/SQLite の open 試行 (WAL sidecar 等) で
        // SQLITE_CANTOPEN になる。 一旦 tmp に複製してそちらを ATTACH する。
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bundle_master_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        try FileManager.default.copyItem(at: bundleURL, to: tmpURL)

        // バージョン比較は ATTACH 前に軽量な read で済ませる。
        var roConfig = Configuration()
        roConfig.readonly = true
        let bundleVersion = try DatabaseQueue(path: tmpURL.path, configuration: roConfig).read { db -> Int in
            Int(try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key='data_version'") ?? "0") ?? 0
        }
        let localVersion = try dbQueue.read { db -> Int in
            Int(try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key='data_version'") ?? "0") ?? 0
        }
        Logger.database.info("[reseed] bundle=\(bundleVersion, privacy: .public) local=\(localVersion, privacy: .public)")
        guard bundleVersion > localVersion else { return }

        // 触らないテーブル (= ユーザデータ + grdb_migrations)
        let preservedTables: Set<String> = [
            "user_marks",
            "custom_image_paths",
            "grdb_migrations",
            "meta",  // 自前で書き換える
            "song_calls", "song_videos",  // コミュニティ投稿系 (CloudKit)
            "song_tags",  // タグ投票 (CloudKit/サーバ)
            "device_song_tag", "device_song_penlight",
        ]

        // コピー本体は純処理として分離 (テスト可能性 + 責務分離)。
        let (ok, skipped) = try Self.copyMasterTables(
            into: dbQueue,
            fromBundleAt: tmpURL.path,
            preserving: preservedTables,
            newVersion: bundleVersion
        )
        let summary = "v\(localVersion)→v\(bundleVersion) ok=\(ok) skipped=\(skipped)"
        reseedState.withLock {
            $0.summary = summary
            $0.failureDetail = nil
        }
        Logger.database.info("[reseed] done \(summary, privacy: .public)")
    }

    /// Bundle DB (`bundlePath`) の内容で `writer` 側マスタテーブルを一括コピーする純処理。
    /// `preservedTables` は触らず、`newVersion` を `meta.data_version` に書き、`(ok, skipped)` を返す。
    /// Bundle 取得やバージョン比較から分離してあり、テストは 2 つの一時 DB を渡して検証できる。
    ///
    /// - 一括コピー: 全 13 万行を `[String:[Row]]` にメモリロードして行単位 execute していた旧実装
    ///   (アプデ後初回起動が数秒フリーズ) を、`INSERT INTO main.t SELECT ... FROM bundle.t` に置換。
    /// - ATTACH はトランザクション内では実行できないため `writeWithoutTransaction` で開き、コピー本体
    ///   だけを明示トランザクションで囲う。
    /// - FK 違反があれば COMMIT で例外を投げ、トランザクション全体がロールバックする (呼び出し元の
    ///   `openDatabase` が捕捉してユーザー可視アラートにする / 旧: サイレント全停止)。
    static func copyMasterTables(
        into writer: any DatabaseWriter,
        fromBundleAt bundlePath: String,
        preserving preservedTables: Set<String>,
        newVersion: Int
    ) throws -> (ok: Int, skipped: Int) {
        var ok = 0
        var skipped = 0
        try writer.writeWithoutTransaction { db in
            try db.execute(sql: "ATTACH DATABASE ? AS bundle", arguments: [bundlePath])
            defer { try? db.execute(sql: "DETACH DATABASE bundle") }

            let bundleTables = try String.fetchAll(db, sql: "SELECT name FROM bundle.sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
            let localTables = Set(try String.fetchAll(db, sql: "SELECT name FROM main.sqlite_master WHERE type='table'"))
            // Bundle 側に存在し、ローカルにもあり、保護対象でないテーブルのみ再投入する。
            let targets = bundleTables.filter { !preservedTables.contains($0) && localTables.contains($0) }

            try db.inTransaction {
                // ⚠️ PRAGMA foreign_keys はトランザクション内では変更できない (no-op)。
                // defer_foreign_keys はトランザクション内で有効で、FK 検証を COMMIT 時まで遅延する。
                // ただし **CASCADE (ON DELETE CASCADE) は FK 検証ではなくアクションなので defer の
                // 対象外**。 子テーブルを先に INSERT した後に親テーブルを DELETE すると CASCADE で
                // 再削除される (例: setlist_performers INSERT → setlist_items DELETE で空に戻る)。
                // 対策として **全テーブル DELETE → 全テーブル INSERT** の 2 段に分ける。
                try db.execute(sql: "PRAGMA defer_foreign_keys = ON")

                // Phase 1: 全テーブル DELETE (CASCADE による意図しない再削除を先に完了させる)
                for table in targets {
                    try db.execute(sql: "DELETE FROM main.\"\(table)\"")
                }
                // Phase 2: 一括コピー。列差分 (バンドル側に無い列 / 余分な列) に備え、
                // main と bundle の共通列だけを対象にする (旧 safeCols 相当)。
                for table in targets {
                    let mainCols = Set(try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info(?, 'main')", arguments: [table]))
                    let bundleCols = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info(?, 'bundle')", arguments: [table])
                    let safeCols = bundleCols.filter { mainCols.contains($0) }
                    guard !safeCols.isEmpty else { skipped += 1; continue }
                    let colList = safeCols.map { "\"\($0)\"" }.joined(separator: ",")
                    try db.execute(sql: "INSERT INTO main.\"\(table)\" (\(colList)) SELECT \(colList) FROM bundle.\"\(table)\"")
                    ok += 1
                }
                try db.execute(sql: "UPDATE main.meta SET value = ? WHERE key = 'data_version'", arguments: [String(newVersion)])
                return .commit
            }
        }
        return (ok, skipped)
    }

    /// CloudKit 同期で `kind` が default 'live' に上書きされる対策。
    /// 起動毎に Bundle 同梱の v7_event_kind_data.sql を idempotent に再適用する。
    private static func reseedEventKindIfNeeded(_ dbQueue: any DatabaseWriter) throws {
        guard let url = Bundle.main.url(forResource: "v7_event_kind_data", withExtension: "sql"),
              let sql = try? String(contentsOf: url, encoding: .utf8) else { return }
        try dbQueue.write { db in
            try db.execute(sql: sql)
        }
    }

    /// Bundle 由来の master.sqlite には grdb_migrations が無いため、
    /// スキーマ実体（カラム・テーブル）を直接検査して「適用済み」識別子を pre-populate する。
    /// インデックス存在だけでは「カラムが追加されたがインデックスがない」ケースでALTER重複が起きるため、
    /// 各マイグレーションの特徴的なスキーマ変更を直接確認する。
    private static func seedMigrationHistoryIfNeeded(_ dbQueue: any DatabaseWriter) throws {
        try dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")

            // v1: brands テーブルが存在すれば基本スキーマ作成済み
            let hasBrands = try Row.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='brands'") != nil
            guard hasBrands else { return }
            try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v1_create_tables')")

            // v2: songs テーブルの composer カラムで判定（インデックスではなくカラム存在）
            let songsColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(songs)").map { $0["name"] as String? }
            if songsColumns.contains("composer") {
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v2_add_indexes')")
            }

            // v3: song_calls テーブルの存在で判定
            let hasSongCalls = try Row.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='song_calls'") != nil
            if hasSongCalls {
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v3_song_calls_and_videos')")
            }

            // v4: user_marks テーブルの存在で判定
            let hasUserMarks = try Row.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='user_marks'") != nil
            if hasUserMarks {
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v4_user_marks')")
            }

            // v5: events テーブルの is_solo カラム存在で判定（インデックスではなくカラム）
            let eventsColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(events)").map { $0["name"] as String? }
            if eventsColumns.contains("is_solo") {
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v5_event_solo_flag')")
            }

            // v6: events.is_streaming カラム存在で判定（Bundle DBが既に v6 相当のスキーマを持つ場合スキップ）
            if eventsColumns.contains("is_streaming") {
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v6_sync_bundle_schema')")
            }

            // v7: events.kind カラム存在で判定
            if eventsColumns.contains("kind") {
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v7_event_kind')")
            }

            // v14: idols.is_external カラム存在で判定 (Bundle DB 同梱済みなら skip)
            let idolsColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(idols)").map { $0["name"] as String? }
            if idolsColumns.contains("is_external") {
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v14_idol_is_external')")
            }

            // v15: events.ticket_deadline / ticket_lottery_date / ticket_url
            // (events の table_info は上で取得済みの eventsColumns を再利用する)
            if eventsColumns.contains("ticket_deadline") {
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v15_event_ticket_info')")
            }

            // v17: idols.aliases (Bundle DB に既にあれば skip)
            if idolsColumns.contains("aliases") {
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v17_idol_aliases')")
            }

            // v18: events.joint_brand_ids (Bundle DB に既にあれば skip)
            if eventsColumns.contains("joint_brand_ids") {
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v18_event_joint_brands')")
            }

            // v19: idols.voice_actors カラム存在 + cast テーブル不在で判定。
            // Bundle DB は cast/idol_cast 廃止済 + voice_actors 追加済なので、 ここで pre-populate
            // しないと新規インストール時に v19 migration が「cast テーブル無し」で SQL エラー →
            // アプリ起動クラッシュ (Apple 審査 reject の原因)。
            let hasCastTable = try Row.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='cast'") != nil
            if idolsColumns.contains("voice_actors") && !hasCastTable {
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v19_drop_cast')")
                // 同時に過去の v16 (legacy infinity event 掃除) も Bundle DB では関係ないので skip
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v16_remove_legacy_infinity_event')")
            }

            // v21: show_cast.cast_role カラム存在で判定 (Bundle DB が役割データ込みで持つなら skip)。
            let showCastColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(show_cast)").map { $0["name"] as String? }
            if showCastColumns.contains("cast_role") {
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v21_show_cast_cast_role')")
            }

            // v22: events.ticket_open_date カラム存在で判定 (Bundle DB が既に持つなら skip)。
            if eventsColumns.contains("ticket_open_date") {
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v22_event_ticket_open_date')")
            }
        }
    }

    // MARK: - Event Queries

    func fetchEvents(brandId: String? = nil) throws -> [Event] {
        try dbQueue.read { db in try Self.fetchEventsQuery(db, brandId: brandId) }
    }

    func fetchEventsAsync(brandId: String? = nil) async throws -> [Event] {
        try await dbQueue.read { db in try Self.fetchEventsQuery(db, brandId: brandId) }
    }

    private static func fetchEventsQuery(_ db: Database, brandId: String?) throws -> [Event] {
        var request = Event.all()
        if let brandId {
            request = request.filter(Column("brand_id") == brandId)
        }
        return try request.fetchAll(db)
    }

    /// イベント一覧（最初の公演日付付き、降順）
    ///
    /// - Parameters:
    ///   - brandId: ブランド絞り込み（nil で全件）
    ///   - includeEmpty: セトリが無いイベントも含めるか
    ///   - liveOnly: true で `kind = 'live'`（アイマス主催のみ）。false なら `kind IN ('live','festival')`。
    ///   - kinds: 表示対象 kind を明示指定したい場合（liveOnly より優先）。デフォルトは `['live','festival']`。
    func fetchEventsWithFirstDate(
        brandId: String? = nil,
        includeEmpty: Bool = true,
        liveOnly: Bool = false,
        kinds: [EventKind]? = nil
    ) throws -> [EventWithDate] {
        try dbQueue.read { db in try Self.fetchEventsWithFirstDateQuery(db, brandId: brandId, includeEmpty: includeEmpty, liveOnly: liveOnly, kinds: kinds) }
    }

    func fetchEventsWithFirstDateAsync(brandId: String? = nil, includeEmpty: Bool = true, liveOnly: Bool = false, kinds: [EventKind]? = nil) async throws -> [EventWithDate] {
        try await dbQueue.read { db in try Self.fetchEventsWithFirstDateQuery(db, brandId: brandId, includeEmpty: includeEmpty, liveOnly: liveOnly, kinds: kinds) }
    }

    private static func fetchEventsWithFirstDateQuery(_ db: Database, brandId: String?, includeEmpty: Bool, liveOnly: Bool, kinds: [EventKind]?) throws -> [EventWithDate] {
        var conditions: [String] = []
        var arguments = StatementArguments()

        // kind フィルタ: 明示指定 > liveOnly > デフォルト(live+festival)
        let targetKinds: [EventKind] = kinds ?? (liveOnly ? [.live] : [.live, .festival])
        let kindPlaceholders = targetKinds.map { _ in "?" }.joined(separator: ", ")
        conditions.append("e.kind IN (\(kindPlaceholders))")
        arguments += StatementArguments(targetKinds.map(\.rawValue))

        if let brandId {
            conditions.append("e.brand_id = ?")
            arguments += StatementArguments([brandId])
        }
        if !includeEmpty {
            conditions.append(Self.hasSetlistCondition)
        }

        var sql = """
            SELECT e.id, e.brand_id, e.name, e.event_type, e.is_streaming, e.is_solo, e.kind,
                   MIN(s.date) AS first_date,
                   MAX(s.date) AS last_date
            FROM events e
            LEFT JOIN shows s ON s.event_id = e.id
            """
        sql += "\nWHERE " + conditions.joined(separator: "\nAND ")
        sql += "\nGROUP BY e.id ORDER BY COALESCE(MIN(s.date), '') DESC"

        return try Row.fetchAll(db, sql: sql, arguments: arguments).map(Self.eventWithDate)
    }

    /// イベント統計（公演数・楽曲数・ユニーク曲数・キャスト数）
    func fetchEventStatsAsync(eventId: String) async throws -> EventStats {
        try await dbQueue.read { db in try Self.fetchEventStatsQuery(db, eventId: eventId) }
    }

    private static func fetchEventStatsQuery(_ db: Database, eventId: String) throws -> EventStats {
        let sql = """
            WITH event_shows AS (SELECT id FROM shows WHERE event_id = ?)
            SELECT
                (SELECT COUNT(*) FROM event_shows) AS show_count,
                (SELECT COUNT(*) FROM setlist_items WHERE show_id IN (SELECT id FROM event_shows)) AS total_songs,
                (SELECT COUNT(DISTINCT song_id) FROM setlist_items WHERE show_id IN (SELECT id FROM event_shows)) AS unique_songs,
                (SELECT COUNT(DISTINCT idol_id) FROM show_cast WHERE show_id IN (SELECT id FROM event_shows)) AS cast_count
            """
        return try EventStats.fetchOne(db, sql: sql, arguments: [eventId])
            ?? EventStats(showCount: 0, totalSongs: 0, uniqueSongs: 0, castCount: 0)
    }

    /// イベントの出演キャスト一覧（アイドル情報付き）
    func fetchEventCastMembers(eventId: String) throws -> [EventCastRow] {
        try dbQueue.read { db in
            // Cast 廃止後: show_cast 直結で idol を引く。 EventCastRow.id/name は idol を採用。
            let sql = """
                SELECT DISTINCT i.id, i.name, i.color AS idol_color, i.name AS idol_name, i.id AS idol_id
                FROM show_cast sc
                JOIN shows sh ON sc.show_id = sh.id
                JOIN idols i ON i.id = sc.idol_id
                WHERE sh.event_id = ?
                ORDER BY i.sort_order
                """
            return try EventCastRow.fetchAll(db, sql: sql, arguments: [eventId])
        }
    }

    /// イベントの show ごとの出席アイドル集合を返す (DAY 別表示用)。
    func fetchEventAttendanceAsync(eventId: String) async throws -> EventAttendance? {
        try await dbQueue.read { db in try Self.fetchEventAttendanceQuery(db, eventId: eventId) }
    }

    private static func fetchEventAttendanceQuery(_ db: Database, eventId: String) throws -> EventAttendance? {
        // event の primary brand と joint_brand_ids を取得
        guard let eventRow = try Row.fetchOne(db, sql: "SELECT brand_id, joint_brand_ids FROM events WHERE id = ?", arguments: [eventId]),
              let brandId = eventRow["brand_id"] as? String
        else { return nil }
        let jointBrandIds = (eventRow["joint_brand_ids"] as? String)?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []
        let candidateBrandIds = [brandId] + jointBrandIds

        let shows = try Show
            .filter(Column("event_id") == eventId)
            .order(Column("date"), Column("sort_order"))
            .fetchAll(db)

        // ライブ最初の公演日。アイドル実装日 (idols.debut_date) がこれより
        // 後のアイドルは「未実装期 = 出席判定対象外」として brandIdols から除外。
        // debut_date 未登録 (NULL) は対象に含める (安全側)。
        let eventStartDate = shows.first?.date

        // 欠席判定の母集団:
        //  - **primary** = idols.brand_id == event.brand_id (例: ML 13th なら ML 専属だけ)
        //  - **joint** = joint_brand_ids に列挙された各ブランドの primary アイドル
        //  → 多重所属 (idol_brands) でゲスト出演として登録されているアイドルは含めない。
        //    そうしないと AS が ML 13th で「欠席」表示される誤検出が起きる。
        let placeholders = candidateBrandIds.map { _ in "?" }.joined(separator: ",")
        let brandIdols: [Idol]
        if candidateBrandIds.count >= 3 {
            // 3ブランド以上の越境フェス (MOIW / IWSF 等) は選抜出演なので、
            // 「母集団 = 実出演者 (show_cast ∪ 歌唱)」にする。ブランド全員を欠席候補に
            // 出すと数百人が「欠席」表示になり無意味なため。2 ブランド以下 (765MILLIONSTARS
            // 等) は従来通りブランド全員を母集団にして「誰が欠席か」を出す。
            brandIdols = try Idol.fetchAll(db, sql: """
                SELECT * FROM idols WHERE id IN (
                    SELECT sc.idol_id FROM show_cast sc
                      JOIN shows sh ON sh.id = sc.show_id WHERE sh.event_id = ?
                    UNION
                    SELECT sp.idol_id FROM setlist_performers sp
                      JOIN setlist_items si ON si.id = sp.setlist_item_id
                      JOIN shows sh ON sh.id = si.show_id WHERE sh.event_id = ?
                ) AND is_external = 0
                ORDER BY sort_order
                """, arguments: [eventId, eventId])
        } else if let eventStartDate {
            brandIdols = try Idol.fetchAll(db, sql: """
                SELECT * FROM idols
                WHERE brand_id IN (\(placeholders))
                  AND is_external = 0
                  AND (debut_date IS NULL OR debut_date <= ?)
                ORDER BY sort_order
                """, arguments: StatementArguments(candidateBrandIds + [eventStartDate])!)
        } else {
            brandIdols = try Idol.fetchAll(db, sql: """
                SELECT * FROM idols
                WHERE brand_id IN (\(placeholders))
                  AND is_external = 0
                ORDER BY sort_order
                """, arguments: StatementArguments(candidateBrandIds)!)
        }

        guard !brandIdols.isEmpty else { return nil }

        // 出演者判定:
        // - setlist_performers (歌唱ベース) を主とする (show_cast は過去公演で欠損あり、 例:円環 second)
        // - 未来公演や setlist 未入力イベントでは setlist_performers が空なので、
        //   show_cast を fallback で UNION して出演者を拾う。
        // - 母集団は primary brand + joint_brand_ids なので、 idols.brand_id で
        //   絞ってマッチさせる (idol_brands ではない)。
        let presenceArgs = StatementArguments([eventId] + candidateBrandIds + [eventId] + candidateBrandIds)!
        let presenceRows = try Row.fetchAll(db, sql: """
            SELECT show_id, idol_id FROM (
                SELECT DISTINCT si.show_id AS show_id, sp.idol_id AS idol_id
                FROM setlist_items si
                JOIN setlist_performers sp ON sp.setlist_item_id = si.id
                JOIN shows sh ON sh.id = si.show_id
                JOIN idols i ON i.id = sp.idol_id
                WHERE sh.event_id = ? AND i.brand_id IN (\(placeholders))
                UNION
                SELECT DISTINCT sc.show_id AS show_id, sc.idol_id AS idol_id
                FROM show_cast sc
                JOIN shows sh ON sh.id = sc.show_id
                JOIN idols i ON i.id = sc.idol_id
                WHERE sh.event_id = ? AND i.brand_id IN (\(placeholders))
            )
            """, arguments: presenceArgs)

        var presenceByShow: [String: Set<String>] = [:]
        for row in presenceRows {
            let showId: String = row["show_id"]
            let idolId: String = row["idol_id"]
            presenceByShow[showId, default: []].insert(idolId)
        }

        // 役割付き出演 (cast_role が 'lead' / 'guest') を show 別に収集。
        let roleRows = try Row.fetchAll(db, sql: """
            SELECT sc.show_id AS show_id, sc.idol_id AS idol_id, sc.cast_role AS cast_role
            FROM show_cast sc
            JOIN shows sh ON sh.id = sc.show_id
            WHERE sh.event_id = ? AND sc.cast_role IN ('lead', 'guest')
            """, arguments: [eventId])
        var leadByShow: [String: Set<String>] = [:]
        var guestByShow: [String: Set<String>] = [:]
        for row in roleRows {
            let showId: String = row["show_id"]
            let idolId: String = row["idol_id"]
            let role: String = row["cast_role"]
            if role == "lead" {
                leadByShow[showId, default: []].insert(idolId)
            } else if role == "guest" {
                guestByShow[showId, default: []].insert(idolId)
            }
        }

        return EventAttendance(
            brandIdols: brandIdols,
            shows: shows,
            presenceByShow: presenceByShow,
            leadByShow: leadByShow,
            guestByShow: guestByShow
        )
    }

    /// イベントのメンバー出席状況（不在アイドル情報）
    /// ブランド全体のアイドル数が60名以下のイベントのみ意味を持つ。
    func fetchEventAbsenceInfo(eventId: String) throws -> EventAbsenceInfo? {
        try dbQueue.read { db in
            // 1. イベントの brand_id を取得
            guard let brandId = try Row.fetchOne(db, sql: "SELECT brand_id FROM events WHERE id = ?", arguments: [eventId])?["brand_id"] as? String
            else { return nil }

            // 2. ブランド全体のアイドル一覧（idol_brands 経由で多重所属に対応）
            //    例: ML ライブで 765AS13 が「ブランド全体」に含まれる。
            //    外部ゲスト演者 (is_external) はブランドの一部ではないので除外。
            let allIdolsSQL = """
                SELECT DISTINCT i.* FROM idols i
                JOIN idol_brands ib ON ib.idol_id = i.id
                WHERE ib.brand_id = ? AND i.is_external = 0
                ORDER BY i.sort_order
                """
            let allIdols = try Idol.fetchAll(db, sql: allIdolsSQL, arguments: [brandId])

            guard !allIdols.isEmpty else { return nil }

            // 3. このイベントに出演したアイドル (show_cast 直結、 idol_brands 経由でブランド絞り込み)
            let presentSQL = """
                SELECT DISTINCT i.* FROM idols i
                JOIN show_cast sc ON sc.idol_id = i.id
                JOIN shows sh ON sh.id = sc.show_id
                JOIN idol_brands ib ON ib.idol_id = i.id
                WHERE sh.event_id = ? AND ib.brand_id = ?
                ORDER BY i.sort_order
                """
            let presentIdols = try Idol.fetchAll(db, sql: presentSQL, arguments: [eventId, brandId])
            let presentIds = Set(presentIdols.map(\.id))

            // 4. 不在アイドル = 全体 - 出演
            let absentIdols = allIdols.filter { !presentIds.contains($0.id) }

            return EventAbsenceInfo(
                totalIdols: allIdols.count,
                presentIdols: presentIdols,
                absentIdols: absentIdols
            )
        }
    }

    /// イベント詳細（公演リスト付き、日付昇順）
    func fetchShowsAsync(eventId: String) async throws -> [Show] {
        try await dbQueue.read { db in try Self.fetchShowsByEventQuery(db, eventId: eventId) }
    }

    private static func fetchShowsByEventQuery(_ db: Database, eventId: String) throws -> [Show] {
        try Show
            .filter(Column("event_id") == eventId)
            .order(Column("date"), Column("sort_order"))
            .fetchAll(db)
    }

    /// 公演をイベント名・公演名で検索（コミュニティ投稿用）
    func searchShows(query: String, limit: Int = 30) throws -> [ShowWithEventName] {
        try dbQueue.read { db in try Self.searchShowsQuery(db, query: query, limit: limit) }
    }

    func searchShowsAsync(query: String, limit: Int = 30) async throws -> [ShowWithEventName] {
        try await dbQueue.read { db in try Self.searchShowsQuery(db, query: query, limit: limit) }
    }

    private static func searchShowsQuery(_ db: Database, query: String, limit: Int) throws -> [ShowWithEventName] {
        let pattern = "%\(query.likeEscaped)%"
        let sql = """
            SELECT s.id, s.event_id, s.name, s.date, s.venue, e.name AS event_name
            FROM shows s
            JOIN events e ON s.event_id = e.id
            WHERE s.name LIKE ? ESCAPE '\\' OR e.name LIKE ? ESCAPE '\\'
            ORDER BY s.date DESC
            LIMIT ?
            """
        return try ShowWithEventName.fetchAll(db, sql: sql, arguments: [pattern, pattern, limit])
    }

    /// 公演全件取得（初期表示用）
    func fetchAllShowsAsync(limit: Int = 50) async throws -> [ShowWithEventName] {
        try await dbQueue.read { db in try Self.fetchAllShowsQuery(db, limit: limit) }
    }

    private static func fetchAllShowsQuery(_ db: Database, limit: Int) throws -> [ShowWithEventName] {
        let sql = """
            SELECT s.id, s.event_id, s.name, s.date, s.venue, e.name AS event_name
            FROM shows s
            JOIN events e ON s.event_id = e.id
            ORDER BY s.date DESC
            LIMIT ?
            """
        return try ShowWithEventName.fetchAll(db, sql: sql, arguments: [limit])
    }

    // MARK: - Setlist Queries

    /// セトリ取得（公演ID指定）
    func fetchSetlistAsync(showId: String) async throws -> [SetlistRow] {
        try await dbQueue.read { db in try Self.fetchSetlistQuery(db, showId: showId) }
    }

    private static func fetchSetlistQuery(_ db: Database, showId: String) throws -> [SetlistRow] {
        let sql = """
            SELECT si.id, si.position, si.section, si.notes, si.unit_name,
                   s.id AS song_id, s.title AS song_title, s.apple_music_id,
                   s.artwork_url, s.preview_url, s.brand_id AS song_brand_id
            FROM setlist_items si
            JOIN songs s ON si.song_id = s.id
            WHERE si.show_id = ?
            ORDER BY si.position
            """
        return try SetlistRow.fetchAll(db, sql: sql, arguments: [showId])
    }

    /// セトリ曲の出演アイドル取得 (Cast 廃止後は idol 直結)。
    /// PerformerRow.id は idol_id (旧 cast_id を踏襲する形)、 name は声優名 (現役)。
    func fetchPerformers(setlistItemId: String) throws -> [PerformerRow] {
        try dbQueue.read { db in
            let sql = """
                SELECT i.id, COALESCE(i.voice_actors, i.name) AS name,
                       i.color AS idol_color, i.name AS idol_name, i.id AS idol_id
                FROM setlist_performers sp
                JOIN idols i ON i.id = sp.idol_id
                WHERE sp.setlist_item_id = ?
                """
            return try PerformerRow.fetchAll(db, sql: sql, arguments: [setlistItemId])
        }
    }

    /// セトリ全曲の出演アイドルを一括取得 (N+1 防止)。
    func fetchAllPerformersAsync(showId: String) async throws -> [String: [PerformerRow]] {
        try await dbQueue.read { db in try Self.fetchAllPerformersQuery(db, showId: showId) }
    }

    private static func fetchAllPerformersQuery(_ db: Database, showId: String) throws -> [String: [PerformerRow]] {
        let sql = """
            SELECT sp.setlist_item_id,
                   i.id AS performer_id,
                   COALESCE(i.voice_actors, i.name) AS cast_name,
                   i.color AS idol_color, i.name AS idol_name, i.id AS idol_id
            FROM setlist_items si
            JOIN setlist_performers sp ON si.id = sp.setlist_item_id
            JOIN idols i ON i.id = sp.idol_id
            WHERE si.show_id = ?
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: [showId])
        var result: [String: [PerformerRow]] = [:]
        for row in rows {
            let itemId: String = row["setlist_item_id"]
            // voice_actors は "中村繪里子,過去CV" のカンマ区切り。 先頭 (現役) のみ表示。
            let rawName: String = row["cast_name"]
            let displayName = rawName.split(separator: ",").first.map(String.init) ?? rawName
            let performer = PerformerRow(
                id: row["performer_id"],
                name: displayName,
                idolColor: row["idol_color"],
                idolName: row["idol_name"],
                idolId: row["idol_id"]
            )
            result[itemId, default: []].append(performer)
        }
        return result
    }

    /// 複数楽曲のオリメンIDを一括取得: [song_id: Set<idol_id>]
    func fetchOriginalArtistIdsAsync(songIds: [String]) async throws -> [String: Set<String>] {
        guard !songIds.isEmpty else { return [:] }
        return try await dbQueue.read { db in try Self.fetchOriginalArtistIdsQuery(db, songIds: songIds) }
    }

    private static func fetchOriginalArtistIdsQuery(_ db: Database, songIds: [String]) throws -> [String: Set<String>] {
        let placeholders = songIds.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT song_id, idol_id FROM song_artists
            WHERE song_id IN (\(placeholders)) AND role = 'original'
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(songIds))
        var result: [String: Set<String>] = [:]
        for row in rows {
            let songId: String = row["song_id"]
            let idolId: String = row["idol_id"]
            result[songId, default: []].insert(idolId)
        }
        return result
    }

    /// 指定公演の出演者 (show_cast) がオリメンの曲 song_id 集合を返す。
    /// 「この公演の出演者が歌う曲」で予想ピッカーを絞り込むために使う。
    func fetchOriginalSongIdsAsync(forShowCastOf showId: String) async throws -> Set<String> {
        try await dbQueue.read { db in try Self.fetchOriginalSongIdsQuery(db, forShowCastOf: showId) }
    }

    private static func fetchOriginalSongIdsQuery(_ db: Database, forShowCastOf showId: String) throws -> Set<String> {
        let sql = """
            SELECT DISTINCT sa.song_id
            FROM song_artists sa
            JOIN show_cast sc ON sc.idol_id = sa.idol_id
            WHERE sa.role = 'original' AND sc.show_id = ?
            """
        return Set(try String.fetchAll(db, sql: sql, arguments: [showId]))
    }

    // MARK: - Filtered Fetch Methods

    /// SongFilterCriterion で楽曲一覧を取得
    func fetchSongs(criterion: SongFilterCriterion) throws -> [SongWithArtists] {
        switch criterion {
        case .brand(let id, _):
            return try fetchSongs(filter: SongSearchFilter(brandId: id))
        case .cdSeries(let series):
            let songs = try dbQueue.read { db in try Self.songsByCdSeriesQuery(db, series: series) }
            return Self.songsWithArtists(songs)
        case .seriesGroup(let name):
            let songs = try dbQueue.read { db in try Self.songsBySeriesGroupQuery(db, name: name) }
            return Self.songsWithArtists(songs)
        case .songType(let type):
            return try fetchSongs(filter: SongSearchFilter(songType: type))
        case .releaseYear(let year):
            let songs = try dbQueue.read { db in try Self.songsByReleaseYearQuery(db, year: year) }
            return Self.songsWithArtists(songs)
        case .creator(let name):
            let withRoles = try fetchSongsByCreator(name)
            return withRoles.map { SongWithArtists(song: $0.song, artistNames: $0.song.singerLabel ?? "") }
        case .songIds(let ids, _):
            guard !ids.isEmpty else { return [] }
            let songs = try dbQueue.read { db in try Self.songsByIdsOrderedQuery(db, ids: ids) }
            return Self.songsWithArtists(songs)
        }
    }

    /// (async) SongFilterCriterion で楽曲一覧を取得。cooperative thread pool をブロックしない。
    func fetchSongsAsync(criterion: SongFilterCriterion) async throws -> [SongWithArtists] {
        switch criterion {
        case .brand(let id, _):
            return try await fetchSongsAsync(filter: SongSearchFilter(brandId: id))
        case .cdSeries(let series):
            let songs = try await dbQueue.read { db in try Self.songsByCdSeriesQuery(db, series: series) }
            return Self.songsWithArtists(songs)
        case .seriesGroup(let name):
            let songs = try await dbQueue.read { db in try Self.songsBySeriesGroupQuery(db, name: name) }
            return Self.songsWithArtists(songs)
        case .songType(let type):
            return try await fetchSongsAsync(filter: SongSearchFilter(songType: type))
        case .releaseYear(let year):
            let songs = try await dbQueue.read { db in try Self.songsByReleaseYearQuery(db, year: year) }
            return Self.songsWithArtists(songs)
        case .creator(let name):
            let withRoles = try await fetchSongsByCreatorAsync(name)
            return withRoles.map { SongWithArtists(song: $0.song, artistNames: $0.song.singerLabel ?? "") }
        case .songIds(let ids, _):
            guard !ids.isEmpty else { return [] }
            let songs = try await dbQueue.read { db in try Self.songsByIdsOrderedQuery(db, ids: ids) }
            return Self.songsWithArtists(songs)
        }
    }

    private static func songsWithArtists(_ songs: [Song]) -> [SongWithArtists] {
        songs.map { SongWithArtists(song: $0, artistNames: $0.singerLabel ?? "") }
    }

    private static func songsByCdSeriesQuery(_ db: Database, series: String) throws -> [Song] {
        try Song.filter(Column("cd_series") == series).order(Column("release_date"), Column("title_kana")).fetchAll(db)
    }

    private static func songsBySeriesGroupQuery(_ db: Database, name: String) throws -> [Song] {
        try Song.filter(Column("series_group") == name)
            .order(Column("release_date"), Column("title_kana"))
            .fetchAll(db)
    }

    private static func songsByReleaseYearQuery(_ db: Database, year: String) throws -> [Song] {
        try Song.filter(Column("release_date").like("\(year)%"))
            .order(Column("release_date"), Column("title_kana"))
            .fetchAll(db)
    }

    private static func songsByIdsOrderedQuery(_ db: Database, ids: [String]) throws -> [Song] {
        try Song.filter(ids.contains(Column("id")))
            .order(Column("title_kana"), Column("title"))
            .fetchAll(db)
    }

    /// 関連楽曲: 同じシリーズ → 同じユニット → 歌唱アイドル共有 の重み付けでスコアし、近い順に返す。
    /// マスタ (ローカル) のみで完結する関連性。コミュニティのタグ類似は別系統 (CommunityAPI.similarSongsByTags)。
    func fetchRelatedSongsAsync(to song: Song, limit: Int = 8) async throws -> [Song] {
        try await dbQueue.read { db in try Self.fetchRelatedSongsQuery(db, to: song, limit: limit) }
    }

    private static func fetchRelatedSongsQuery(_ db: Database, to song: Song, limit: Int) throws -> [Song] {
        let seriesGroup = try String.fetchOne(
            db, sql: "SELECT series_group FROM songs WHERE id = ?", arguments: [song.id]
        )
        let artistIds = try String.fetchAll(
            db, sql: "SELECT idol_id FROM song_artists WHERE song_id = ? AND role = 'original'",
            arguments: [song.id]
        )

        var ordered: [String] = []
        var byId: [String: (song: Song, score: Int)] = [:]
        func add(_ songs: [Song], weight: Int) {
            for s in songs where s.id != song.id {
                if byId[s.id] == nil { ordered.append(s.id) }
                byId[s.id, default: (s, 0)].score += weight
            }
        }

        if let sg = seriesGroup, !sg.isEmpty {
            add(try Song.filter(Column("series_group") == sg).fetchAll(db), weight: 3)
        }
        if let unitId = song.unitId, !unitId.isEmpty {
            add(try Song.filter(Column("unit_id") == unitId).fetchAll(db), weight: 2)
        }
        if !artistIds.isEmpty {
            let placeholders = artistIds.map { _ in "?" }.joined(separator: ",")
            let sharedSongIds = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT song_id FROM song_artists WHERE role = 'original' AND idol_id IN (\(placeholders))",
                arguments: StatementArguments(artistIds)
            )
            if !sharedSongIds.isEmpty {
                add(try Song.filter(sharedSongIds.contains(Column("id"))).fetchAll(db), weight: 1)
            }
        }

        return ordered
            .compactMap { byId[$0] }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return (lhs.song.releaseDate ?? "") > (rhs.song.releaseDate ?? "")
            }
            .prefix(limit)
            .map(\.song)
    }

    /// クリエイター名（作曲・作詞・編曲 横断）で楽曲を検索し、各曲での役割付きで返す
    func fetchSongsByCreator(_ name: String) throws -> [SongWithRoles] {
        guard let trimmedName = Self.normalizedCreatorName(name) else { return [] }
        let candidates = try dbQueue.read { db in try Self.fetchSongsByCreatorQuery(db, trimmedName: trimmedName) }
        return Self.songsWithCreatorRoles(candidates, trimmedName: trimmedName)
    }

    /// (async) クリエイター名検索。cooperative thread pool をブロックしない。
    func fetchSongsByCreatorAsync(_ name: String) async throws -> [SongWithRoles] {
        guard let trimmedName = Self.normalizedCreatorName(name) else { return [] }
        let candidates = try await dbQueue.read { db in try Self.fetchSongsByCreatorQuery(db, trimmedName: trimmedName) }
        return Self.songsWithCreatorRoles(candidates, trimmedName: trimmedName)
    }

    private static func normalizedCreatorName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func fetchSongsByCreatorQuery(_ db: Database, trimmedName: String) throws -> [Song] {
        let pattern = "%\(trimmedName.likeEscaped)%"
        return try Song.filter(
            Column("composer").like(pattern, escape: "\\") ||
            Column("lyricist").like(pattern, escape: "\\") ||
            Column("arranger").like(pattern, escape: "\\")
        ).order(Column("title_kana"), Column("title")).fetchAll(db)
    }

    private static func songsWithCreatorRoles(_ candidates: [Song], trimmedName: String) -> [SongWithRoles] {
        let separators = CharacterSet(charactersIn: "/／,、・")
        return candidates.compactMap { song in
            let roles = [("作曲", song.composer), ("作詞", song.lyricist), ("編曲", song.arranger)]
                .compactMap { label, field -> String? in
                    guard let value = field else { return nil }
                    let parts = value.components(separatedBy: separators)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    return parts.contains(trimmedName) ? label : nil
                }
            guard !roles.isEmpty else { return nil }
            return SongWithRoles(song: song, artists: [], roles: roles)
        }
    }

    /// IdolFilterCriterion でアイドル一覧を取得
    func fetchIdols(criterion: IdolFilterCriterion) throws -> [Idol] {
        switch criterion {
        case .brand(let id, _):
            return try fetchIdols(brandId: id)
        case .birthMonth(let month):
            return try dbQueue.read { db in try Self.idolsByBirthMonthQuery(db, month: month) }
        case .constellation(let c):
            return try dbQueue.read { db in try Self.idolsByConstellationQuery(db, constellation: c) }
        case .birthPlace(let p):
            return try dbQueue.read { db in try Self.idolsByBirthPlaceQuery(db, birthPlace: p) }
        case .bloodType(let t):
            return try dbQueue.read { db in try Self.idolsByBloodTypeQuery(db, bloodType: t) }
        }
    }

    /// (async) IdolFilterCriterion でアイドル一覧を取得。cooperative thread pool をブロックしない。
    func fetchIdolsAsync(criterion: IdolFilterCriterion) async throws -> [Idol] {
        switch criterion {
        case .brand(let id, _):
            return try await fetchIdolsAsync(brandId: id)
        case .birthMonth(let month):
            return try await dbQueue.read { db in try Self.idolsByBirthMonthQuery(db, month: month) }
        case .constellation(let c):
            return try await dbQueue.read { db in try Self.idolsByConstellationQuery(db, constellation: c) }
        case .birthPlace(let p):
            return try await dbQueue.read { db in try Self.idolsByBirthPlaceQuery(db, birthPlace: p) }
        case .bloodType(let t):
            return try await dbQueue.read { db in try Self.idolsByBloodTypeQuery(db, bloodType: t) }
        }
    }

    private static func idolsByBirthMonthQuery(_ db: Database, month: Int) throws -> [Idol] {
        let paddedMonth = String(format: "--%02d-", month)
        return try Idol.filter(Column("birthday").like("\(paddedMonth)%"))
            .order(Column("sort_order"))
            .fetchAll(db)
    }

    private static func idolsByConstellationQuery(_ db: Database, constellation: String) throws -> [Idol] {
        try Idol.filter(Column("constellation") == constellation).order(Column("sort_order")).fetchAll(db)
    }

    private static func idolsByBirthPlaceQuery(_ db: Database, birthPlace: String) throws -> [Idol] {
        try Idol.filter(Column("birth_place") == birthPlace).order(Column("sort_order")).fetchAll(db)
    }

    private static func idolsByBloodTypeQuery(_ db: Database, bloodType: String) throws -> [Idol] {
        try Idol.filter(Column("blood_type") == bloodType).order(Column("sort_order")).fetchAll(db)
    }

    /// (async) EventFilterCriterion でイベント一覧を取得。cooperative thread pool をブロックしない。
    func fetchEventsWithDateAsync(criterion: EventFilterCriterion, includeEmpty: Bool = true) async throws -> [EventWithDate] {
        switch criterion {
        case .brand(let id, _):
            return try await fetchEventsWithFirstDateAsync(brandId: id, includeEmpty: includeEmpty)
        case .year(let year):
            return try await dbQueue.read { db in try Self.eventsWithDateByYearQuery(db, year: year, includeEmpty: includeEmpty) }
        }
    }

    private static func eventsWithDateByYearQuery(_ db: Database, year: Int, includeEmpty: Bool) throws -> [EventWithDate] {
        var havingConditions = ["strftime('%Y', first_date) = ?"]
        if !includeEmpty {
            havingConditions.append(Self.hasSetlistCondition)
        }
        let sql = """
            SELECT e.id, e.brand_id, e.name, e.event_type, e.is_streaming, e.is_solo, e.kind,
                   MIN(s.date) AS first_date
            FROM events e
            LEFT JOIN shows s ON s.event_id = e.id
            WHERE e.kind IN ('live', 'festival')
            GROUP BY e.id
            HAVING \(havingConditions.joined(separator: " AND "))
            ORDER BY COALESCE(MIN(s.date), '') DESC
            """
        return try Row.fetchAll(db, sql: sql, arguments: [String(year)]).map(Self.eventWithDate)
    }

    /// 指定 event_id 集合に該当する EventWithDate を、最新公演日降順で返す。
    /// MyPage の参加ライブ一覧などで使用。 空配列を渡したら空配列を返す。
    func fetchEventsByIds(_ ids: [String]) throws -> [EventWithDate] {
        guard !ids.isEmpty else { return [] }
        return try dbQueue.read { db in try Self.fetchEventsByIdsQuery(db, ids) }
    }

    func fetchEventsByIdsAsync(_ ids: [String]) async throws -> [EventWithDate] {
        guard !ids.isEmpty else { return [] }
        return try await dbQueue.read { db in try Self.fetchEventsByIdsQuery(db, ids) }
    }

    private static func fetchEventsByIdsQuery(_ db: Database, _ ids: [String]) throws -> [EventWithDate] {
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT e.id, e.brand_id, e.name, e.event_type, e.is_streaming, e.is_solo, e.kind,
                   MIN(s.date) AS first_date,
                   MAX(s.date) AS last_date
            FROM events e
            LEFT JOIN shows s ON s.event_id = e.id
            WHERE e.id IN (\(placeholders))
            GROUP BY e.id
            ORDER BY COALESCE(MIN(s.date), '') DESC
            """
        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(ids))
            .map(Self.eventWithDate)
    }

    /// 参加したライブ(イベント)を重複なしで返す。
    /// 「イベント単位の参加マーク」と「公演(show)単位の参加マーク→所属イベント」を UNION で統合する。
    /// (参加を公演単位で付けるユーザーが多く、event マークだけ見るとリストが取りこぼすため)
    func fetchAttendedEventsWithDate() throws -> [EventWithDate] {
        try dbQueue.read { db in try Self.fetchAttendedEventsWithDateQuery(db) }
    }

    func fetchAttendedEventsWithDateAsync() async throws -> [EventWithDate] {
        try await dbQueue.read { db in try Self.fetchAttendedEventsWithDateQuery(db) }
    }

    private static func fetchAttendedEventsWithDateQuery(_ db: Database) throws -> [EventWithDate] {
        let sql = """
            SELECT e.id, e.brand_id, e.name, e.event_type, e.is_streaming, e.is_solo, e.kind,
                   MIN(s.date) AS first_date,
                   MAX(s.date) AS last_date
            FROM events e
            LEFT JOIN shows s ON s.event_id = e.id
            WHERE e.id IN (
                SELECT entity_id FROM user_marks
                WHERE entity_type = 'event' AND kind = 'attended' AND bool_value = 1
                UNION
                SELECT sh.event_id FROM user_marks um
                JOIN shows sh ON sh.id = um.entity_id
                WHERE um.entity_type = 'show' AND um.kind = 'attended' AND um.bool_value = 1
            )
            GROUP BY e.id
            ORDER BY COALESCE(MIN(s.date), '') DESC
            """
        return try Row.fetchAll(db, sql: sql).map(Self.eventWithDate)
    }

    /// 参加したイベントを「現地参加を含む」「配信参加を含む」の2集合に分類して返す。
    /// 1イベント内で現地公演と配信公演が混在する場合は両方に入る。
    /// 種別は user_marks.text_value ("live"/"stream")。旧データ(種別なし)は現地扱い。
    /// 参加ライブ一覧の現地/配信フィルタで使用。
    func fetchAttendedEventTypeSetsAsync() async throws -> (live: Set<String>, stream: Set<String>, liveViewing: Set<String>) {
        try await dbQueue.read { db in try Self.fetchAttendedEventTypeSetsQuery(db) }
    }

    private static func fetchAttendedEventTypeSetsQuery(_ db: Database) throws -> (live: Set<String>, stream: Set<String>, liveViewing: Set<String>) {
        let sql = """
            SELECT event_id, text_value AS atype FROM (
                SELECT entity_id AS event_id, text_value
                FROM user_marks
                WHERE entity_type='event' AND kind='attended' AND bool_value=1
                UNION ALL
                SELECT sh.event_id AS event_id, um.text_value
                FROM user_marks um
                JOIN shows sh ON sh.id = um.entity_id
                WHERE um.entity_type='show' AND um.kind='attended' AND um.bool_value=1
            )
            """
        var live: Set<String> = []
        var stream: Set<String> = []
        var liveViewing: Set<String> = []
        for row in try Row.fetchAll(db, sql: sql) {
            guard let eventId: String = row["event_id"] else { continue }
            let atype: String? = row["atype"]
            switch atype {
            case "stream":       stream.insert(eventId)
            case "live_viewing": liveViewing.insert(eventId)
            default:             live.insert(eventId)  // "live" または種別なし(旧データ) は現地扱い
            }
        }
        return (live, stream, liveViewing)
    }

    /// (async) ShowFilterCriterion で公演一覧を取得。cooperative thread pool をブロックしない。
    func fetchShowsAsync(criterion: ShowFilterCriterion) async throws -> [Show] {
        switch criterion {
        case .venue(let venue):
            return try await dbQueue.read { db in try Self.showsByVenueQuery(db, venue: venue) }
        case .date(let date):
            return try await dbQueue.read { db in try Self.showsByDateQuery(db, date: date) }
        }
    }

    private static func showsByVenueQuery(_ db: Database, venue: String) throws -> [Show] {
        try Show.filter(Column("venue") == venue).order(Column("date").desc).fetchAll(db)
    }

    /// 会場マスタ一式。245施設 + 名前246件 + ホール40件と小さいので一括で読み、
    /// 当時名やキャパの解決はメモリ上 (`VenueDirectory`) で行う (公演ごとの N+1 を避ける)。
    func fetchVenueDirectoryAsync() async throws -> VenueDirectory {
        try await dbQueue.read { db in try Self.fetchVenueDirectoryQuery(db) }
    }

    private static func fetchVenueDirectoryQuery(_ db: Database) throws -> VenueDirectory {
        VenueDirectory(
            venues: try Venue.order(Column("sort_order")).fetchAll(db),
            names: try VenueName.fetchAll(db),
            halls: try VenueHall.fetchAll(db)
        )
    }

    /// 指定会場で公演があったイベントの id 集合。
    /// 会場は show 単位、絞り込み対象は event 単位なので逆引きが要る
    /// (1 イベントが複数会場をまたぐツアーもあるため DISTINCT で取る)。
    func fetchEventIdsAtVenueAsync(_ venueId: String) async throws -> Set<String> {
        try await dbQueue.read { db in try Self.fetchEventIdsAtVenueQuery(db, venueId: venueId) }
    }

    private static func fetchEventIdsAtVenueQuery(_ db: Database, venueId: String) throws -> Set<String> {
        Set(try String.fetchAll(
            db,
            sql: "SELECT DISTINCT event_id FROM shows WHERE venue_id = ?",
            arguments: [venueId]
        ))
    }

    /// 検索語に一致した会場を event_id ごとに 1 件返す。
    /// 「武道館」で検索してライブ名だけ並ぶと、なぜヒットしたのか分からないため、
    /// 会場一致で拾えたものは行に会場名を出して理由を見せる。
    func fetchVenuesMatchingAsync(query: String, eventIds: [String]) async throws -> [String: String] {
        try await dbQueue.read { db in try Self.fetchVenuesMatchingQuery(db, query: query, eventIds: eventIds) }
    }

    private static func fetchVenuesMatchingQuery(_ db: Database, query: String, eventIds: [String]) throws -> [String: String] {
        guard !eventIds.isEmpty, !query.isEmpty else { return [:] }
        let placeholders = eventIds.map { _ in "?" }.joined(separator: ",")
        let pattern = "%\(query.lowercased().likeEscaped)%"
        let sql = """
            SELECT event_id, MIN(venue) AS venue FROM shows
            WHERE event_id IN (\(placeholders))
              AND venue IS NOT NULL AND LOWER(venue) LIKE ? ESCAPE '\\'
            GROUP BY event_id
            """
        var args: [DatabaseValueConvertible] = eventIds
        args.append(pattern)
        var result: [String: String] = [:]
        for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)) {
            result[row["event_id"]] = row["venue"]
        }
        return result
    }

    private static func showsByDateQuery(_ db: Database, date: String) throws -> [Show] {
        try Show.filter(Column("date") == date).order(Column("sort_order")).fetchAll(db)
    }

    // MARK: - Private Helpers

    /// 「中身がある」イベントの定義: shows があるか、または setlist_items まで揃っているか。
    /// 未来公演 (shows 登録済みだが setlist まだ) も「中身あり」として扱うよう shows のみ
    /// を OR 条件で許す (旧仕様は両方必須で 8thLIVE 等の未来公演を全消ししていた)。
    private static let hasSetlistCondition = """
        EXISTS (
            SELECT 1 FROM shows sh
            WHERE sh.event_id = e.id
        )
        """

    private static func eventWithDate(_ row: Row) -> EventWithDate {
        EventWithDate(
            event: Event(
                id: row["id"],
                brandId: row["brand_id"],
                name: row["name"],
                eventType: row["event_type"],
                isStreaming: row["is_streaming"] ?? false,
                isSolo: row["is_solo"] ?? true,
                kind: row["kind"] ?? "live"
            ),
            firstDate: row["first_date"],
            lastDate: row["last_date"]
        )
    }
}
