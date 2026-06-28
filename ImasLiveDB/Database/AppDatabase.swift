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
    /// 最後の reseedMasterTablesIfNeeded の結果サマリ。 マイページ診断で表示する。
    nonisolated(unsafe) static var lastReseedStatus: String = "未実行"

    private init() {
        do {
            self.dbQueue = try Self.openDatabase()
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
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
            Self.lastReseedStatus = "失敗: \(detail)"
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
        // Bundle 内は read-only 領域なので GRDB の open 試行 (WAL sidecar 等) で
        // SQLITE_CANTOPEN になる。 一旦 tmp に複製してそちらを開く。
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bundle_master_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        try FileManager.default.copyItem(at: bundleURL, to: tmpURL)
        var roConfig = Configuration()
        roConfig.readonly = true
        let bundleQueue = try DatabaseQueue(path: tmpURL.path, configuration: roConfig)
        let bundleVersion = try bundleQueue.read { db -> Int in
            let v = try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key='data_version'") ?? "0"
            return Int(v) ?? 0
        }
        let localVersion = try dbQueue.read { db -> Int in
            let v = try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key='data_version'") ?? "0"
            return Int(v) ?? 0
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

        let masterRows: [String: [Row]] = try bundleQueue.read { db -> [String: [Row]] in
            let names = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
            var dump: [String: [Row]] = [:]
            for name in names where !preservedTables.contains(name) {
                dump[name] = try Row.fetchAll(db, sql: "SELECT * FROM \(name)")
            }
            return dump
        }

        try dbQueue.write { db in
            // ⚠️ PRAGMA foreign_keys はトランザクション内では変更できない (no-op)。
            // defer_foreign_keys はトランザクション内で有効で、FK 検証を COMMIT 時まで遅延する。
            // これにより masterRows(順序不定) を DELETE+INSERT しても親子順序に依存せず、
            // 最終状態が整合していれば commit 時に一括検証される (無言 skip を防ぐ)。
            try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
            let localTables = Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'"))
            var ok = 0
            var skipped = 0
            for (table, rows) in masterRows where localTables.contains(table) {
                do {
                    try db.execute(sql: "DELETE FROM \(table)")
                    guard let first = rows.first else { continue }
                    let cols = first.columnNames
                    let localCols = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info(?)", arguments: [table])
                    let localColSet = Set(localCols)
                    let safeCols = cols.filter { localColSet.contains($0) }
                    guard !safeCols.isEmpty else { continue }
                    let placeholders = safeCols.map { _ in "?" }.joined(separator: ",")
                    let colList = safeCols.map { "\"\($0)\"" }.joined(separator: ",")
                    let sql = "INSERT INTO \(table) (\(colList)) VALUES (\(placeholders))"
                    for row in rows {
                        let values = safeCols.map { row[$0] as DatabaseValue }
                        try db.execute(sql: sql, arguments: StatementArguments(values))
                    }
                    ok += 1
                } catch {
                    Logger.database.error("[reseed] table \(table, privacy: .public) failed: \(error.localizedDescription, privacy: .public) | \(String(describing: error), privacy: .public)")
                    skipped += 1
                }
            }
            try db.execute(sql: "UPDATE meta SET value = ? WHERE key = 'data_version'", arguments: [String(bundleVersion)])
            // defer_foreign_keys はトランザクション終了時に自動リセットされるため明示復帰は不要。
            let summary = "v\(localVersion)→v\(bundleVersion) ok=\(ok) skipped=\(skipped)"
            Self.lastReseedStatus = summary
            Logger.database.info("[reseed] done \(summary, privacy: .public)")
        }
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
        try dbQueue.read { db in
            var request = Event.all()
            if let brandId {
                request = request.filter(Column("brand_id") == brandId)
            }
            return try request.fetchAll(db)
        }
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
        try dbQueue.read { db in
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
    }

    /// イベント統計（公演数・楽曲数・ユニーク曲数・キャスト数）
    func fetchEventStats(eventId: String) throws -> EventStats {
        try dbQueue.read { db in
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
    func fetchEventAttendance(eventId: String) throws -> EventAttendance? {
        try dbQueue.read { db in
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
    func fetchShows(eventId: String) throws -> [Show] {
        try dbQueue.read { db in
            try Show
                .filter(Column("event_id") == eventId)
                .order(Column("date"), Column("sort_order"))
                .fetchAll(db)
        }
    }

    /// 公演をイベント名・公演名で検索（コミュニティ投稿用）
    func searchShows(query: String, limit: Int = 30) throws -> [ShowWithEventName] {
        try dbQueue.read { db in
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
    }

    /// 公演全件取得（初期表示用）
    func fetchAllShows(limit: Int = 50) throws -> [ShowWithEventName] {
        try dbQueue.read { db in
            let sql = """
                SELECT s.id, s.event_id, s.name, s.date, s.venue, e.name AS event_name
                FROM shows s
                JOIN events e ON s.event_id = e.id
                ORDER BY s.date DESC
                LIMIT ?
                """
            return try ShowWithEventName.fetchAll(db, sql: sql, arguments: [limit])
        }
    }

    // MARK: - Setlist Queries

    /// セトリ取得（公演ID指定）
    func fetchSetlist(showId: String) throws -> [SetlistRow] {
        try dbQueue.read { db in
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
    func fetchAllPerformers(showId: String) throws -> [String: [PerformerRow]] {
        try dbQueue.read { db in
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
    }

    /// 複数楽曲のオリメンIDを一括取得: [song_id: Set<idol_id>]
    func fetchOriginalArtistIds(songIds: [String]) throws -> [String: Set<String>] {
        guard !songIds.isEmpty else { return [:] }
        return try dbQueue.read { db in
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
    }

    /// 指定公演の出演者 (show_cast) がオリメンの曲 song_id 集合を返す。
    /// 「この公演の出演者が歌う曲」で予想ピッカーを絞り込むために使う。
    func fetchOriginalSongIds(forShowCastOf showId: String) throws -> Set<String> {
        try dbQueue.read { db in
            let sql = """
                SELECT DISTINCT sa.song_id
                FROM song_artists sa
                JOIN show_cast sc ON sc.idol_id = sa.idol_id
                WHERE sa.role = 'original' AND sc.show_id = ?
                """
            return Set(try String.fetchAll(db, sql: sql, arguments: [showId]))
        }
    }

    // MARK: - Song Queries

    /// 楽曲一覧
    /// 指定 song_id のリストに対して、各 song に紐付く performer idol 配列を返す。
    /// song_artists は (song_id, idol_id) 直接マッピング。
    /// 一覧表示でアイドルアイコンを並べるため一括取得する。
    func fetchSongPerformerIdolsMap(songIds: [String]) throws -> [String: [Idol]] {
        guard !songIds.isEmpty else { return [:] }
        return try dbQueue.read { db in
            let placeholders = songIds.map { _ in "?" }.joined(separator: ", ")
            let sql = """
                SELECT sa.song_id AS sid, i.*
                FROM song_artists sa
                JOIN idols i ON i.id = sa.idol_id
                WHERE sa.song_id IN (\(placeholders))
                  AND sa.role = 'original'
                ORDER BY sa.song_id, i.sort_order
                """
            var result: [String: [Idol]] = [:]
            for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(songIds)) {
                let sid: String = row["sid"]
                let idol = try Idol(row: row)
                if !(result[sid]?.contains(where: { $0.id == idol.id }) ?? false) {
                    result[sid, default: []].append(idol)
                }
            }
            return result
        }
    }

    func fetchSongs(
        filter: SongSearchFilter = SongSearchFilter(),
        sortOrder: SongSortOrder = .titleKana,
        ascending: Bool? = nil
    ) throws -> [SongWithArtists] {
        let asc = ascending ?? sortOrder.defaultAscending
        return try dbQueue.read { db in
            // SQL + WHERE条件を動的構築
            var conditions: [String] = []
            var args: [DatabaseValueConvertible] = []

            // デフォルトではリミックス・別バージョンを除外
            if !filter.includeRemixes {
                conditions.append("s.parent_song_id IS NULL")
            }

            if !filter.brandIds.isEmpty {
                let placeholders = filter.brandIds.map { _ in "?" }.joined(separator: ",")
                conditions.append("s.brand_id IN (\(placeholders))")
                for id in filter.brandIds { args.append(id) }
            } else if !filter.includeOtherBrand {
                // ブランド未選択 (全件) のときは既定で other (歌枠カバー等) を隠す。
                conditions.append("s.brand_id IS NOT 'other'")
            }
            if filter.excludeLiveOnly {
                // ライブ履歴のみのファントム曲を除外。カタログメタ (配信ID / 原唱者 /
                // リリース日 / CD / 作家) を1つでも持てば正規曲として出す。何も無い曲
                // (セトリ追加で生まれただけのカバー等) だけを隠す。
                conditions.append("""
                    (
                        (s.apple_music_id IS NOT NULL AND s.apple_music_id <> '')
                        OR (s.release_date IS NOT NULL AND s.release_date <> '')
                        OR (s.cd_title IS NOT NULL AND s.cd_title <> '')
                        OR (s.cd_series IS NOT NULL AND s.cd_series <> '')
                        OR (s.composer IS NOT NULL AND s.composer <> '')
                        OR (s.lyricist IS NOT NULL AND s.lyricist <> '')
                        OR (s.arranger IS NOT NULL AND s.arranger <> '')
                        OR EXISTS (SELECT 1 FROM song_artists sa WHERE sa.song_id = s.id)
                    )
                    """)
            }
            if let title = filter.title, !title.isEmpty {
                conditions.append("(s.title LIKE ? ESCAPE '\\' OR s.title_kana LIKE ? ESCAPE '\\')")
                args.append("%\(title.likeEscaped)%")
                args.append("%\(title.likeEscaped)%")
            }
            if let songwriter = filter.songwriter, !songwriter.isEmpty {
                conditions.append("(s.composer LIKE ? ESCAPE '\\' OR s.lyricist LIKE ? ESCAPE '\\' OR s.arranger LIKE ? ESCAPE '\\')")
                args.append("%\(songwriter.likeEscaped)%")
                args.append("%\(songwriter.likeEscaped)%")
                args.append("%\(songwriter.likeEscaped)%")
            }
            if let cdSeries = filter.cdSeries, !cdSeries.isEmpty {
                conditions.append("s.cd_series LIKE ? ESCAPE '\\'")
                args.append("%\(cdSeries.likeEscaped)%")
            }
            if let seriesGroup = filter.seriesGroup, !seriesGroup.isEmpty {
                conditions.append("s.series_group = ?")
                args.append(seriesGroup)
            }
            if let songType = filter.songType {
                conditions.append("s.song_type = ?")
                args.append(songType)
            }

            // アイドル名フィルタ（song_artists JOIN）
            let hasIdolIds = !(filter.idolIds ?? []).isEmpty
            let hasIdolName = !(filter.idolName ?? "").isEmpty
            let needsArtistJoin = hasIdolIds || hasIdolName
            let needsLiveJoin = !(filter.liveName ?? "").isEmpty

            var sql = "SELECT DISTINCT s.* FROM songs s"
            if needsArtistJoin {
                sql += " JOIN song_artists sa ON s.id = sa.song_id JOIN idols i ON sa.idol_id = i.id"
                if hasIdolIds, let idolIds = filter.idolIds, !idolIds.isEmpty {
                    let placeholders = idolIds.map { _ in "?" }.joined(separator: ",")
                    conditions.append("sa.idol_id IN (\(placeholders))")
                    for id in idolIds { args.append(id) }
                } else if hasIdolName, let idolName = filter.idolName, !idolName.isEmpty {
                    conditions.append("(i.name LIKE ? ESCAPE '\\' OR i.name_kana LIKE ? ESCAPE '\\')")
                    args.append("%\(idolName.likeEscaped)%")
                    args.append("%\(idolName.likeEscaped)%")
                }
            }
            if needsLiveJoin, let liveName = filter.liveName, !liveName.isEmpty {
                sql += " JOIN setlist_items si ON s.id = si.song_id JOIN shows sh ON si.show_id = sh.id JOIN events ev ON sh.event_id = ev.id"
                conditions.append("ev.name LIKE ? ESCAPE '\\'")
                args.append("%\(liveName.likeEscaped)%")
            }

            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }

            let dirSQL = asc ? "ASC" : "DESC"
            switch sortOrder {
            case .titleKana:
                sql += " ORDER BY s.title_kana \(dirSQL), s.title \(dirSQL)"
            case .releaseDate:
                sql += " ORDER BY s.release_date \(dirSQL), s.title_kana"
            case .performanceCount, .collectedCount, .collectedRate:
                break
            }

            let songs = try Song.fetchAll(db, sql: sql, arguments: StatementArguments(args))

            var results = songs.map { song in
                SongWithArtists(song: song, artistNames: song.singerLabel ?? "")
            }

            // 数値系ソートは fetch 後に Swift で並び替え。 asc=true ならで小→大、 false なら大→小。
            func cmp(_ a: Int, _ b: Int) -> Bool { asc ? a < b : a > b }
            switch sortOrder {
            case .titleKana, .releaseDate:
                break
            case .performanceCount:
                let countMap = try totalSongPerformanceCountMap(db)
                results.sort { cmp(countMap[$0.song.id, default: 0], countMap[$1.song.id, default: 0]) }
            case .collectedCount:
                let countMap = try attendedSongCountMap(db)
                results.sort { cmp(countMap[$0.song.id, default: 0], countMap[$1.song.id, default: 0]) }
            case .collectedRate:
                let attendedMap = try attendedSongCountMap(db)
                let totalMap = try totalSongPerformanceCountMap(db)
                results.sort { lhs, rhs in
                    let lt = totalMap[lhs.song.id, default: 0]
                    let rt = totalMap[rhs.song.id, default: 0]
                    let lr = lt > 0 ? Double(attendedMap[lhs.song.id, default: 0]) / Double(lt) : 0
                    let rr = rt > 0 ? Double(attendedMap[rhs.song.id, default: 0]) / Double(rt) : 0
                    if lr != rr { return asc ? lr < rr : lr > rr }
                    return cmp(attendedMap[lhs.song.id, default: 0], attendedMap[rhs.song.id, default: 0])
                }
            }

            return results
        }
    }

    /// song_id → 全公演での披露回数。
    private func totalSongPerformanceCountMap(_ db: Database) throws -> [String: Int] {
        let rows = try SongPerfCount.fetchAll(
            db, sql: "SELECT song_id, COUNT(*) as cnt FROM setlist_items GROUP BY song_id"
        )
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.songId, $0.cnt) })
    }

    /// ユーザが参加した show (event 単位の attended も配下 show を含む) 経由の
    /// song_id → 回収回数。 楽曲一覧の「現地回収回数順 / 回収率順」で使用。
    private func attendedSongCountMap(_ db: Database) throws -> [String: Int] {
        let sql = """
            SELECT si.song_id AS song_id, COUNT(DISTINCT si.show_id) AS cnt
            FROM setlist_items si
            WHERE si.show_id IN (
                SELECT entity_id FROM user_marks
                WHERE entity_type='show' AND kind='attended' AND bool_value=1
            ) OR si.show_id IN (
                SELECT id FROM shows
                WHERE event_id IN (
                    SELECT entity_id FROM user_marks
                    WHERE entity_type='event' AND kind='attended' AND bool_value=1
                )
            )
            GROUP BY si.song_id
            """
        let rows = try SongPerfCount.fetchAll(db, sql: sql)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.songId, $0.cnt) })
    }

    /// 楽曲取得（ID指定）
    func fetchSong(id: String) throws -> Song? {
        try dbQueue.read { db in
            try Song.fetchOne(db, key: id)
        }
    }

    /// 楽曲一括取得（複数ID指定・IN句1回）。N+1防止用。
    func fetchSongs(ids: [String]) throws -> [Song] {
        guard !ids.isEmpty else { return [] }
        return try dbQueue.read { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            return try Song.fetchAll(db, sql: "SELECT * FROM songs WHERE id IN (\(placeholders))",
                                    arguments: StatementArguments(ids))
        }
    }

    /// 指定ブランドの非カバー楽曲IDを id 昇順で返す (今日の1曲の決定論的ピック用・軽量)。
    func fetchSongIds(brandId: String, includeCovers: Bool = false, excludeRemixes: Bool = false) throws -> [String] {
        try dbQueue.read { db in
            var sql = "SELECT id FROM songs WHERE brand_id=?"
            if !includeCovers { sql += " AND song_type<>'cover'" }
            // 今日の1曲などでリミックス変種(同名の紛らわしい重複)を避けるため除外可能に。
            if excludeRemixes { sql += " AND (parent_song_id IS NULL OR parent_song_id='')" }
            sql += " ORDER BY id"
            return try String.fetchAll(db, sql: sql, arguments: [brandId])
        }
    }

    /// 楽曲シリーズ(series_group)の一覧。ブランド指定時はそのブランドに絞る。曲数降順。
    func fetchSeriesGroups(brandIds: Set<String> = []) throws -> [String] {
        try dbQueue.read { db in
            let base = "SELECT series_group FROM songs WHERE series_group IS NOT NULL AND series_group<>''"
            if brandIds.isEmpty {
                return try String.fetchAll(db, sql: base + " GROUP BY series_group ORDER BY COUNT(*) DESC")
            }
            let ph = brandIds.map { _ in "?" }.joined(separator: ",")
            return try String.fetchAll(db, sql: base + " AND brand_id IN (\(ph)) GROUP BY series_group ORDER BY COUNT(*) DESC",
                                       arguments: StatementArguments(Array(brandIds)))
        }
    }

    /// アイドル一括取得（ID配列）— N+1 解消用
    func fetchIdols(ids: [String]) throws -> [Idol] {
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        return try dbQueue.read { db in
            try Idol.fetchAll(db, sql: "SELECT * FROM idols WHERE id IN (\(placeholders))",
                              arguments: StatementArguments(ids))
        }
    }

    /// アイドル取得（ID指定）
    func fetchIdol(id: String) throws -> Idol? {
        try dbQueue.read { db in
            try Idol.fetchOne(db, key: id)
        }
    }

    /// 公演取得（ID指定）
    func fetchShow(id: String) throws -> Show? {
        try dbQueue.read { db in
            try Show.fetchOne(db, key: id)
        }
    }

    /// イベント取得（ID指定）
    func fetchEvent(id: String) throws -> Event? {
        try dbQueue.read { db in
            try Event.fetchOne(db, key: id)
        }
    }

    /// イベントの映像円盤 (event_releases)。所有チェックUIの母集団。発売日→sort_order 順。
    func fetchEventReleases(eventId: String) throws -> [EventRelease] {
        try dbQueue.read { db in
            try EventRelease
                .filter(Column("event_id") == eventId)
                .order(Column("release_date").asc, Column("sort_order").asc)
                .fetchAll(db)
        }
    }

    /// イベント一括取得（ID配列） — 全フィールド（ticketDeadline 等）を含む完全な Event を返す。N+1防止用。
    func fetchFullEvents(ids: [String]) throws -> [Event] {
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        return try dbQueue.read { db in
            try Event.fetchAll(db, sql: "SELECT * FROM events WHERE id IN (\(placeholders))",
                               arguments: StatementArguments(ids))
        }
    }

    /// 楽曲の歌唱アイドル取得
    func fetchSongArtists(songId: String, role: String? = nil) throws -> [Idol] {
        try dbQueue.read { db in
            var sql = """
                SELECT i.* FROM idols i
                JOIN song_artists sa ON i.id = sa.idol_id
                WHERE sa.song_id = ?
                """
            var args: [DatabaseValueConvertible] = [songId]
            if let role {
                sql += " AND sa.role = ?"
                args.append(role)
            }
            sql += " ORDER BY i.sort_order"
            return try Idol.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    func fetchSongSuggestions(query: String, limit: Int = 8) throws -> [SearchSuggestionItem] {
        try dbQueue.read { db in
            let pattern = "%\(query.likeEscaped)%"

            let songSQL = """
                SELECT DISTINCT title AS text, cd_series AS subtitle FROM songs
                WHERE title LIKE ? ESCAPE '\\' OR title_kana LIKE ? ESCAPE '\\'
                ORDER BY title_kana
                LIMIT ?
                """
            var items = try Row.fetchAll(db, sql: songSQL, arguments: [pattern, pattern, limit])
                .map { SearchSuggestionItem(text: $0["text"], subtitle: $0["subtitle"], icon: "music.note") }

            let remaining = limit - items.count
            guard remaining > 0 else { return items }

            let albumSQL = """
                SELECT DISTINCT cd_series AS text FROM songs
                WHERE cd_series LIKE ? ESCAPE '\\' AND cd_series IS NOT NULL
                ORDER BY cd_series
                LIMIT ?
                """
            let existingTexts = Set(items.map(\.text))
            let albumItems = try Row.fetchAll(db, sql: albumSQL, arguments: [pattern, remaining])
                .map { SearchSuggestionItem(text: $0["text"], subtitle: "アルバム", icon: "square.grid.2x2") }
                .filter { !existingTexts.contains($0.text) }
            items += albumItems
            return items
        }
    }

    /// 楽曲の披露履歴
    func fetchSongPerformanceHistory(songId: String) throws -> [PerformanceHistoryRow] {
        try dbQueue.read { db in
            let sql = """
                SELECT sh.id AS show_id, e.id AS event_id,
                       e.name AS event_name, sh.name AS show_name, sh.date, sh.venue,
                       si.position, si.section
                FROM setlist_items si
                JOIN shows sh ON si.show_id = sh.id
                JOIN events e ON sh.event_id = e.id
                WHERE si.song_id = ?
                ORDER BY sh.date DESC
                """
            return try PerformanceHistoryRow.fetchAll(db, sql: sql, arguments: [songId])
        }
    }

    // MARK: - Idol Queries

    /// アイドル一覧 (外部ゲスト演者は除外)
    func fetchIdols(brandId: String? = nil) throws -> [Idol] {
        try dbQueue.read { db in
            if let brandId {
                let sql = """
                    SELECT DISTINCT i.* FROM idols i
                    JOIN idol_brands ib ON i.id = ib.idol_id
                    WHERE ib.brand_id = ? AND i.is_external = 0
                    ORDER BY i.sort_order
                    """
                return try Idol.fetchAll(db, sql: sql, arguments: [brandId])
            }
            return try Idol
                .filter(Column("is_external") == 0)
                .order(Column("sort_order"))
                .fetchAll(db)
        }
    }

    /// アイドル詳細のCV取得 (Cast 廃止後は idol.voice_actors から現役を返す)。
    func fetchCurrentVoiceActor(idolId: String) throws -> String? {
        try dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT voice_actors FROM idols WHERE id = ?",
                arguments: [idolId]
            )
            guard let raw: String = row?["voice_actors"], !raw.isEmpty else { return nil }
            return raw.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces)
        }
    }

    /// アイドルの所属ユニット一覧
    func fetchIdolUnits(idolId: String) throws -> [Unit] {
        try dbQueue.read { db in
            let sql = """
                SELECT u.* FROM units u
                JOIN unit_members um ON u.id = um.unit_id
                WHERE um.idol_id = ?
                ORDER BY u.name
                """
            return try Unit.fetchAll(db, sql: sql, arguments: [idolId])
        }
    }

    /// 編集フィード用: recordType + recordName から人間可読のタイトル(曲名/公演名/アイドル名 等)を引く。
    /// 解決できない recordType (コミュニティ投稿等) は nil。
    func fetchEditRecordTitle(recordType: String, recordName: String) throws -> String? {
        try dbQueue.read { db in
            func one(_ sql: String) -> String? {
                (try? String.fetchOne(db, sql: sql, arguments: [recordName])) ?? nil
            }
            switch recordType {
            case "Song":
                return one("SELECT title FROM songs WHERE id = ?")
            case "Event":
                return one("SELECT name FROM events WHERE id = ?")
            case "Show", "ShowSetlist":
                return one("SELECT name FROM shows WHERE id = ?")
            case "Idol":
                return one("SELECT name FROM idols WHERE id = ?")
            case "SetlistItem":
                // 「どのセトリ(公演)を編集したか」を示すため公演名を返す。
                return one("""
                    SELECT sh.name FROM setlist_items si
                    JOIN shows sh ON sh.id = si.show_id WHERE si.id = ?
                    """)
            case "SetlistPerformer":
                return one("""
                    SELECT sh.name FROM setlist_performers sp
                    JOIN setlist_items si ON si.id = sp.setlist_item_id
                    JOIN shows sh ON sh.id = si.show_id WHERE sp.setlist_item_id = ?
                    """)
            case "SongVideo":
                // ytref_xxx → song_videos.song_id を辿って曲名を返す。
                return one("""
                    SELECT s.title FROM song_videos sv
                    JOIN songs s ON s.id = sv.song_id WHERE sv.id = ?
                    """)
            case "SongCall":
                // call_xxx → song_calls.song_id を辿って曲名を返す。
                return one("""
                    SELECT s.title FROM song_calls sc
                    JOIN songs s ON s.id = sc.song_id WHERE sc.id = ?
                    """)
            default:
                return nil
            }
        }
    }

    /// 編集レコードが属する公演 ID を解決する (セトリ系編集 → 該当公演のセトリへ遷移するため)。
    /// Show/ShowSetlist は recordName 自体が公演 ID。SetlistItem/SetlistPerformer は親を辿る。
    func fetchEditRecordShowId(recordType: String, recordName: String) throws -> String? {
        try dbQueue.read { db in
            func one(_ sql: String) -> String? {
                (try? String.fetchOne(db, sql: sql, arguments: [recordName])) ?? nil
            }
            switch recordType {
            case "Show", "ShowSetlist":
                return one("SELECT id FROM shows WHERE id = ?")
            case "SetlistItem":
                return one("SELECT show_id FROM setlist_items WHERE id = ?")
            case "SetlistPerformer":
                return one("""
                    SELECT si.show_id FROM setlist_performers sp
                    JOIN setlist_items si ON si.id = sp.setlist_item_id
                    WHERE sp.setlist_item_id = ?
                    """)
            default:
                return nil
            }
        }
    }

    /// 編集レコードが属する曲 ID を解決する (SongVideo/SongCall 編集 → 該当曲詳細へ遷移するため)。
    func fetchEditRecordSongId(recordType: String, recordName: String) throws -> String? {
        try dbQueue.read { db in
            func one(_ sql: String) -> String? {
                (try? String.fetchOne(db, sql: sql, arguments: [recordName])) ?? nil
            }
            switch recordType {
            case "SongVideo":
                return one("SELECT song_id FROM song_videos WHERE id = ?")
            case "SongCall":
                return one("SELECT song_id FROM song_calls WHERE id = ?")
            default:
                return nil
            }
        }
    }

    /// 指定ユニット ID のうち、楽曲を 1 曲以上持つもの (songs.unit_id 参照) を返す。
    /// アイドル詳細で「曲ありユニット / 曲なしユニット」を分けるのに使う。
    func fetchUnitIdsWithSongs(unitIds: [String]) throws -> Set<String> {
        guard !unitIds.isEmpty else { return [] }
        return try dbQueue.read { db in
            let placeholders = unitIds.map { _ in "?" }.joined(separator: ",")
            let rows = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT unit_id FROM songs WHERE unit_id IN (\(placeholders))",
                arguments: StatementArguments(unitIds)
            )
            return Set(rows)
        }
    }

    /// アイドルの楽曲一覧（song_type指定可）
    func fetchIdolSongs(idolId: String, role: String? = nil) throws -> [Song] {
        try dbQueue.read { db in
            var sql = """
                SELECT s.* FROM songs s
                JOIN song_artists sa ON s.id = sa.song_id
                WHERE sa.idol_id = ?
                """
            var args: [String] = [idolId]
            if let role {
                sql += " AND sa.role = ?"
                args.append(role)
            }
            sql += " ORDER BY s.release_date DESC"
            return try Song.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// 声優名で担当アイドルを逆引き (idol.voice_actors の カンマ区切りに合致するもの)。
    func fetchIdolsByVoiceActor(name: String) throws -> [Idol] {
        try dbQueue.read { db in
            // voice_actors が "中村繪里子" 単独、もしくは "中村繪里子,旧CV" のような形式に対応。
            let sql = """
                SELECT * FROM idols
                WHERE voice_actors = ?
                   OR voice_actors LIKE ? || ',%'
                   OR voice_actors LIKE '%,' || ?
                   OR voice_actors LIKE '%,' || ? || ',%'
                ORDER BY sort_order
                """
            return try Idol.fetchAll(db, sql: sql, arguments: [name, name, name, name])
        }
    }

    /// アイドル全員のCV名マップ (idol_id → 現役 voice_actor)。
    func fetchIdolCastNames() throws -> [String: String] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, voice_actors FROM idols WHERE voice_actors IS NOT NULL"
            )
            var result: [String: String] = [:]
            for row in rows {
                let id: String = row["id"]
                let raw: String = row["voice_actors"]
                if let first = raw.split(separator: ",").first {
                    result[id] = first.trimmingCharacters(in: .whitespaces)
                }
            }
            return result
        }
    }

    /// キャストの出演公演一覧
    /// イベント内のセトリで歌唱された全 unit_id を返す。
    /// setlist_items.unit_id (席上付与) と songs.unit_id (曲属性) の両方を見る。
    /// 「ユニット名義の曲」が披露されたユニット = ライブ上「ユニットとして登場した」と解釈。
    /// この event のセトリで「ユニット単独曲として披露された」ユニット ID 集合。
    /// setlist_performers の歌唱メンバーが unit_members と完全一致する曲があるユニットだけを返す。
    /// (legacy: setlist_items.unit_id / songs.unit_id 由来は誤検出が多いので採用しない)
    func fetchPerformedUnitIds(eventId: String) throws -> Set<String> {
        try dbQueue.read { db in
            // step 1: this event's setlist_items 各曲の歌唱 idol set を取る
            let perfRows = try Row.fetchAll(db, sql: """
                SELECT si.id AS item_id, sp.idol_id AS idol_id
                FROM setlist_items si
                JOIN shows sh ON sh.id = si.show_id
                JOIN setlist_performers sp ON sp.setlist_item_id = si.id
                WHERE sh.event_id = ?
                """, arguments: [eventId])
            var perfByItem: [String: Set<String>] = [:]
            for row in perfRows {
                let itemId: String = row["item_id"]
                let idolId: String = row["idol_id"]
                perfByItem[itemId, default: []].insert(idolId)
            }
            guard !perfByItem.isEmpty else { return [] }
            // step 2: 楽曲のあるユニットの member set を取得
            let unitRows = try Row.fetchAll(db, sql: """
                SELECT um.unit_id AS uid, um.idol_id AS iid
                FROM unit_members um
                JOIN units u ON u.id = um.unit_id
                WHERE EXISTS (SELECT 1 FROM songs s WHERE s.unit_id = u.id)
                """)
            var membersByUnit: [String: Set<String>] = [:]
            for row in unitRows {
                let uid: String = row["uid"]
                let iid: String = row["iid"]
                membersByUnit[uid, default: []].insert(iid)
            }
            // step 3: 完全一致 (1-unit exact) するユニットを集める
            var matched: Set<String> = []
            for (_, perfSet) in perfByItem where perfSet.count >= 2 {
                for (uid, members) in membersByUnit where members.count >= 2 && members == perfSet {
                    matched.insert(uid)
                }
            }
            return matched
        }
    }

    /// 公演 (show) に出演している全アイドル ID のセット (show_cast)。 Cast 廃止後は idol_id 直結。
    func fetchShowIdolIds(showId: String) throws -> Set<String> {
        try dbQueue.read { db in
            let ids = try String.fetchAll(
                db,
                sql: "SELECT idol_id FROM show_cast WHERE show_id = ?",
                arguments: [showId]
            )
            return Set(ids)
        }
    }

    /// 指定公演の出演アイドル一覧 (show_cast JOIN idols)。sort_order 順。
    /// 「誰が歌う」予想の候補アイドルリストとして使う。
    func fetchShowCastIdols(showId: String) throws -> [Idol] {
        try dbQueue.read { db in
            try Idol.fetchAll(
                db,
                sql: """
                    SELECT i.* FROM idols i
                    JOIN show_cast sc ON sc.idol_id = i.id
                    WHERE sc.show_id = ?
                    ORDER BY i.sort_order
                    """,
                arguments: [showId]
            )
        }
    }

    /// 指定アイドルの出演公演一覧 (setlist_performers ∪ show_cast)。
    /// セトリ未登録の公演でも出演履歴を拾えるよう UNION で結合する。
    func fetchIdolShows(idolId: String) throws -> [CastShowRow] {
        try dbQueue.read { db in
            let sql = """
                SELECT sh.id AS show_id, e.id AS event_id,
                       e.name AS event_name, sh.name AS show_name, sh.date, sh.venue,
                       COALESCE(
                           (SELECT cast_role FROM show_cast WHERE show_id = sh.id AND idol_id = ?),
                           'member'
                       ) AS cast_role
                FROM shows sh
                JOIN events e ON sh.event_id = e.id
                WHERE sh.id IN (
                    SELECT DISTINCT si.show_id
                    FROM setlist_performers sp
                    JOIN setlist_items si ON si.id = sp.setlist_item_id
                    WHERE sp.idol_id = ?
                    UNION
                    SELECT show_id FROM show_cast WHERE idol_id = ?
                )
                ORDER BY sh.date DESC
                """
            return try CastShowRow.fetchAll(db, sql: sql, arguments: [idolId, idolId, idolId])
        }
    }

    // MARK: - Stats Queries

    /// ブランド別楽曲数
    func fetchBrandSongCounts() throws -> [BrandSongCount] {
        try dbQueue.read { db in
            let sql = """
                SELECT b.id, b.short_name, b.color, COUNT(s.id) AS song_count
                FROM brands b LEFT JOIN songs s ON b.id = s.brand_id
                GROUP BY b.id ORDER BY b.sort_order
                """
            return try BrandSongCount.fetchAll(db, sql: sql)
        }
    }

    /// brand_id が設定されている曲 ID セット。
    /// 回収率集計で分子と分母の母集合を揃えるために使う。
    func fetchBrandedSongIds() throws -> Set<String> {
        try dbQueue.read { db in
            let ids = try String.fetchAll(db, sql: "SELECT id FROM songs WHERE brand_id IS NOT NULL")
            return Set(ids)
        }
    }

    /// 全ブランド取得
    func fetchBrands() throws -> [Brand] {
        try dbQueue.read { db in
            try Brand.order(Column("sort_order")).fetchAll(db)
        }
    }

    func fetchIntroDonSongs(brandIds: Set<String>? = nil) throws -> [Song] {
        try dbQueue.read { db in
            var sql = """
                SELECT * FROM songs
                WHERE apple_music_id IS NOT NULL AND apple_music_id != ''
                  AND parent_song_id IS NULL
                """
            var args: [DatabaseValueConvertible] = []
            if let brandIds, !brandIds.isEmpty {
                sql += "\n  AND brand_id IN (\(brandIds.map { _ in "?" }.joined(separator: ",")))"
                args = Array(brandIds)
            }
            sql += "\nORDER BY RANDOM()"
            return try Song.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// ライブ披露回数ランキング
    func fetchSongPlayCountRanking(limit: Int = 20) throws -> [SongPlayCount] {
        try dbQueue.read { db in
            let sql = """
                SELECT s.id, s.title, COUNT(si.id) AS play_count, s.brand_id
                FROM songs s
                JOIN setlist_items si ON s.id = si.song_id
                GROUP BY s.id
                ORDER BY play_count DESC
                LIMIT ?
                """
            return try SongPlayCount.fetchAll(db, sql: sql, arguments: [limit])
        }
    }

    /// アイドル別出演回数ランキング (Cast 廃止後は idol 単位)。
    /// 表示名は idol.name を採用 (旧 cast.name の代わり)。
    func fetchCastShowCountRanking(limit: Int = 20) throws -> [CastShowCount] {
        try dbQueue.read { db in
            let sql = """
                SELECT i.id, i.name, COUNT(DISTINCT sc.show_id) AS show_count
                FROM idols i
                JOIN show_cast sc ON i.id = sc.idol_id
                GROUP BY i.id
                ORDER BY show_count DESC
                LIMIT ?
                """
            return try CastShowCount.fetchAll(db, sql: sql, arguments: [limit])
        }
    }

    /// 全ユニット (picker 用)。
    func fetchAllUnits() throws -> [Unit] {
        try dbQueue.read { db in
            try Unit.order(Column("brand_id"), Column("name")).fetchAll(db)
        }
    }

    /// ユニット取得
    func fetchUnit(id: String) throws -> Unit? {
        try dbQueue.read { db in
            try Unit.fetchOne(db, key: id)
        }
    }

    /// ユニットメンバー取得
    func fetchUnitMembers(unitId: String) throws -> [Idol] {
        try dbQueue.read { db in
            let sql = """
                SELECT i.* FROM idols i
                JOIN unit_members um ON i.id = um.idol_id
                WHERE um.unit_id = ?
                ORDER BY i.sort_order
                """
            return try Idol.fetchAll(db, sql: sql, arguments: [unitId])
        }
    }

    /// setlist 表示で「performer が unit 全員揃ったら unit 名を出す」ために使うインデックス。
    /// 全 unit を一度に取得して、idol_id → 属する unit 一覧のマップを構築する。
    func fetchUnitIndex() throws -> UnitIndex {
        try dbQueue.read { db in
            let units = try Unit.fetchAll(db)
            let members = try Row.fetchAll(db, sql: "SELECT unit_id, idol_id FROM unit_members")
            var memberIds: [String: Set<String>] = [:]
            var byIdol: [String: Set<String>] = [:]
            for row in members {
                let uid: String = row["unit_id"]
                let iid: String = row["idol_id"]
                memberIds[uid, default: []].insert(iid)
                byIdol[iid, default: []].insert(uid)
            }
            // 楽曲を持つ unit (songs.unit_id で参照されている) を集める。
            // セトリ表示では「楽曲あり unit」だけを逆引き候補にして、
            // 名前だけ同じ合同メンバー集合で誤検出しないようにする。
            let songUnitIds = try Row.fetchAll(db, sql: """
                SELECT DISTINCT unit_id FROM songs
                WHERE unit_id IS NOT NULL AND unit_id != ''
                """).compactMap { $0["unit_id"] as String? }
            let unitsWithSongs = Set(songUnitIds)
            return UnitIndex(
                units: units,
                memberIds: memberIds,
                byIdol: byIdol,
                unitsWithSongs: unitsWithSongs
            )
        }
    }

    /// ユニット楽曲取得
    func fetchUnitSongs(unitId: String) throws -> [Song] {
        try dbQueue.read { db in
            try Song.filter(Column("unit_id") == unitId).order(Column("release_date")).fetchAll(db)
        }
    }

    /// DB全体の統計 (外部ゲスト演者は除外)
    func fetchDatabaseStats() throws -> DatabaseStats {
        try dbQueue.read { db in
            DatabaseStats(
                songCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM songs") ?? 0,
                idolCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM idols WHERE is_external = 0") ?? 0,
                eventCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? 0,
                showCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM shows") ?? 0
            )
        }
    }

    /// 同期診断用 — recordName に '@' が入ったレコード数を集計し、ML 13thLIVE が
    /// 存在するかチェックする。@-roundtrip バグの切り分けに使う。
    func fetchSyncDiagnostics() throws -> SyncDiagnostics {
        try dbQueue.read { db in
            SyncDiagnostics(
                eventsAt: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events WHERE id LIKE '%@%'") ?? 0,
                showsAt: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM shows WHERE id LIKE '%@%'") ?? 0,
                setlistItemsAt: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM setlist_items WHERE id LIKE '%@%'") ?? 0,
                ml13thLiveExists: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events WHERE id = ?", arguments: ["ev_the_idolm@ster_million_live_13thlive"]) ?? 0 > 0,
                ml13thShowsCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM shows WHERE event_id = ?", arguments: ["ev_the_idolm@ster_million_live_13thlive"]) ?? 0,
                ml13thSetlistItemsCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM setlist_items WHERE show_id LIKE 'sh_the_idolm@ster_million_live_13thlive%'") ?? 0,
                sc8thName: try String.fetchOne(db, sql: "SELECT name FROM events WHERE id = ?", arguments: ["ev_the_idolm@ster_shiny_colors_8th_live_ito_yume"]),
                sc8thKind: try String.fetchOne(db, sql: "SELECT kind FROM events WHERE id = ?", arguments: ["ev_the_idolm@ster_shiny_colors_8th_live_ito_yume"]),
                sc8thShowsCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM shows WHERE event_id = ?", arguments: ["ev_the_idolm@ster_shiny_colors_8th_live_ito_yume"]) ?? 0
            )
        }
    }

    /// 直近公演取得
    func fetchLatestShow() throws -> Show? {
        try dbQueue.read { db in
            try Show.order(Column("date").desc).fetchOne(db)
        }
    }

    /// CDシリーズ一覧（ユニーク値）
    func fetchCdSeriesList() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT cd_series FROM songs
                WHERE cd_series IS NOT NULL AND cd_series != ''
                ORDER BY cd_series
                """)
        }
    }

    /// イベント名一覧
    func fetchEventNames() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM events ORDER BY name")
        }
    }

    /// イベント名 OR 公演会場 (shows.venue) のいずれかが query に部分一致するイベントを返す。
    /// venue は同 event 内の複数 shows をまたぐので EXISTS で結合。
    func searchEventsByNameOrVenue(query: String, limit: Int = 100) throws -> [Event] {
        try dbQueue.read { db in
            let pattern = "%\(query.lowercased())%"
            return try Event.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT e.* FROM events e
                    LEFT JOIN shows sh ON sh.event_id = e.id
                    WHERE LOWER(e.name) LIKE ?
                       OR LOWER(IFNULL(sh.venue, '')) LIKE ?
                    LIMIT ?
                    """,
                arguments: [pattern, pattern, limit]
            )
        }
    }

    /// アイドルを名前 / かな / ローマ字の部分一致で検索 (ピッカー用)。
    func searchIdols(query: String, limit: Int = 50) throws -> [Idol] {
        try dbQueue.read { db in
            let pattern = "%\(query)%"
            return try Idol.filter(
                Column("name").like(pattern) ||
                Column("name_kana").like(pattern) ||
                Column("name_romaji").like(pattern)
            )
            .order(Column("sort_order"))
            .limit(limit)
            .fetchAll(db)
        }
    }

    /// metaテーブルから値取得
    func fetchMetaValue(forKey key: String) throws -> String? {
        try dbQueue.read { db in
            try Meta.getValue(db, forKey: key)
        }
    }

    /// 年別ライブ開催数推移
    func fetchYearlyShowCounts() throws -> [YearlyShowCount] {
        try dbQueue.read { db in
            let sql = """
                SELECT strftime('%Y', date) AS year, COUNT(*) AS show_count
                FROM shows
                GROUP BY year
                ORDER BY year
                """
            return try YearlyShowCount.fetchAll(db, sql: sql)
        }
    }

    // MARK: - Search

    /// グローバル検索
    func search(query: String) throws -> SearchResults {
        try dbQueue.read { db in
            let pattern = "%\(query)%"

            let songs = try Song.filter(
                Column("title").like(pattern) ||
                Column("title_kana").like(pattern)
            ).limit(20).fetchAll(db)

            let idols = try Idol.filter(
                Column("name").like(pattern) ||
                Column("name_kana").like(pattern)
            ).limit(20).fetchAll(db)

            let events = try Event.filter(
                Column("name").like(pattern)
            ).limit(20).fetchAll(db)

            return SearchResults(songs: songs, idols: idols, events: events)
        }
    }

    // MARK: - Filtered Fetch Methods

    /// SongFilterCriterion で楽曲一覧を取得
    func fetchSongs(criterion: SongFilterCriterion) throws -> [SongWithArtists] {
        switch criterion {
        case .brand(let id, _):
            return try fetchSongs(filter: SongSearchFilter(brandId: id))
        case .cdSeries(let series):
            let songs: [Song] = try dbQueue.read { db in
                try Song.filter(Column("cd_series") == series).order(Column("release_date"), Column("title_kana")).fetchAll(db)
            }
            return songs.map { SongWithArtists(song: $0, artistNames: $0.singerLabel ?? "") }
        case .seriesGroup(let name):
            let songs: [Song] = try dbQueue.read { db in
                try Song.filter(Column("series_group") == name)
                    .order(Column("release_date"), Column("title_kana"))
                    .fetchAll(db)
            }
            return songs.map { SongWithArtists(song: $0, artistNames: $0.singerLabel ?? "") }
        case .songType(let type):
            return try fetchSongs(filter: SongSearchFilter(songType: type))
        case .releaseYear(let year):
            let songs: [Song] = try dbQueue.read { db in
                try Song.filter(Column("release_date").like("\(year)%"))
                    .order(Column("release_date"), Column("title_kana"))
                    .fetchAll(db)
            }
            return songs.map { SongWithArtists(song: $0, artistNames: $0.singerLabel ?? "") }
        case .creator(let name):
            let withRoles = try fetchSongsByCreator(name)
            return withRoles.map { SongWithArtists(song: $0.song, artistNames: $0.song.singerLabel ?? "") }
        case .songIds(let ids, _):
            guard !ids.isEmpty else { return [] }
            let songs: [Song] = try dbQueue.read { db in
                try Song.filter(ids.contains(Column("id")))
                    .order(Column("title_kana"), Column("title"))
                    .fetchAll(db)
            }
            return songs.map { SongWithArtists(song: $0, artistNames: $0.singerLabel ?? "") }
        }
    }

    /// 関連楽曲: 同じシリーズ → 同じユニット → 歌唱アイドル共有 の重み付けでスコアし、近い順に返す。
    /// マスタ (ローカル) のみで完結する関連性。コミュニティのタグ類似は別系統 (CommunityAPI.similarSongsByTags)。
    func fetchRelatedSongs(to song: Song, limit: Int = 8) throws -> [Song] {
        try dbQueue.read { db in
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
    }

    /// クリエイター名（作曲・作詞・編曲 横断）で楽曲を検索し、各曲での役割付きで返す
    func fetchSongsByCreator(_ name: String) throws -> [SongWithRoles] {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return [] }

        let candidates: [Song] = try dbQueue.read { db in
            let pattern = "%\(trimmedName)%"
            return try Song.filter(
                Column("composer").like(pattern) ||
                Column("lyricist").like(pattern) ||
                Column("arranger").like(pattern)
            ).order(Column("title_kana"), Column("title")).fetchAll(db)
        }

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
            let paddedMonth = String(format: "--%02d-", month)
            return try dbQueue.read { db in
                try Idol.filter(Column("birthday").like("\(paddedMonth)%"))
                    .order(Column("sort_order"))
                    .fetchAll(db)
            }
        case .constellation(let c):
            return try dbQueue.read { db in
                try Idol.filter(Column("constellation") == c).order(Column("sort_order")).fetchAll(db)
            }
        case .birthPlace(let p):
            return try dbQueue.read { db in
                try Idol.filter(Column("birth_place") == p).order(Column("sort_order")).fetchAll(db)
            }
        case .bloodType(let t):
            return try dbQueue.read { db in
                try Idol.filter(Column("blood_type") == t).order(Column("sort_order")).fetchAll(db)
            }
        }
    }

    /// EventFilterCriterion でイベント一覧を取得（first_date付き）
    /// `kind IN ('live','festival')` のみ含む（release_event/radio/stream は除外）。
    func fetchEventsWithDate(criterion: EventFilterCriterion, includeEmpty: Bool = true) throws -> [EventWithDate] {
        switch criterion {
        case .brand(let id, _):
            return try fetchEventsWithFirstDate(brandId: id, includeEmpty: includeEmpty)
        case .year(let year):
            return try dbQueue.read { db in
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
        }
    }

    /// 指定 event_id 集合に該当する EventWithDate を、最新公演日降順で返す。
    /// MyPage の参加ライブ一覧などで使用。 空配列を渡したら空配列を返す。
    func fetchEventsByIds(_ ids: [String]) throws -> [EventWithDate] {
        guard !ids.isEmpty else { return [] }
        return try dbQueue.read { db in
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
    }

    /// 参加したライブ(イベント)を重複なしで返す。
    /// 「イベント単位の参加マーク」と「公演(show)単位の参加マーク→所属イベント」を UNION で統合する。
    /// (参加を公演単位で付けるユーザーが多く、event マークだけ見るとリストが取りこぼすため)
    func fetchAttendedEventsWithDate() throws -> [EventWithDate] {
        try dbQueue.read { db in
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
    }

    /// 参加したイベントを「現地参加を含む」「配信参加を含む」の2集合に分類して返す。
    /// 1イベント内で現地公演と配信公演が混在する場合は両方に入る。
    /// 種別は user_marks.text_value ("live"/"stream")。旧データ(種別なし)は現地扱い。
    /// 参加ライブ一覧の現地/配信フィルタで使用。
    func fetchAttendedEventTypeSets() throws -> (live: Set<String>, stream: Set<String>, liveViewing: Set<String>) {
        try dbQueue.read { db in
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
    }

    /// ShowFilterCriterion で公演一覧を取得
    func fetchShows(criterion: ShowFilterCriterion) throws -> [Show] {
        switch criterion {
        case .venue(let venue):
            return try dbQueue.read { db in
                try Show.filter(Column("venue") == venue).order(Column("date").desc).fetchAll(db)
            }
        case .date(let date):
            return try dbQueue.read { db in
                try Show.filter(Column("date") == date).order(Column("sort_order")).fetchAll(db)
            }
        }
    }

    // MARK: - Idol Song Queries

    /// アイドルがライブで披露した曲一覧（披露回数付き）
    func fetchIdolPerformedSongs(idolId: String) throws -> [IdolPerformedSong] {
        try dbQueue.read { db in
            // setlist_performers 経由で idol_cast → idols と辿り、回数を集計
            let sql = """
                SELECT s.*, COUNT(DISTINCT si.id) AS perform_count
                FROM songs s
                JOIN setlist_items si ON s.id = si.song_id
                JOIN setlist_performers sp ON si.id = sp.setlist_item_id
                WHERE sp.idol_id = ?
                GROUP BY s.id
                ORDER BY perform_count DESC, s.title_kana
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [idolId])
            return rows.compactMap { row -> IdolPerformedSong? in
                let count: Int = row["perform_count"] ?? 0
                // Song は FetchableRecord なので Row から直接デコード
                guard let song = try? Song(row: row) else { return nil }
                return IdolPerformedSong(song: song, performCount: count)
            }
        }
    }

    /// アイドルが特定の曲を披露した公演履歴（最新順）
    func fetchIdolSongHistory(idolId: String, songId: String) throws -> [CastShowRow] {
        try dbQueue.read { db in
            let sql = """
                SELECT DISTINCT sh.id AS show_id, e.id AS event_id,
                       e.name AS event_name, sh.name AS show_name, sh.date, sh.venue
                FROM setlist_items si
                JOIN shows sh ON si.show_id = sh.id
                JOIN events e ON sh.event_id = e.id
                JOIN setlist_performers sp ON si.id = sp.setlist_item_id
                WHERE si.song_id = ? AND sp.idol_id = ?
                ORDER BY sh.date DESC
                """
            return try CastShowRow.fetchAll(db, sql: sql, arguments: [songId, idolId])
        }
    }

    // MARK: - Song Search (for OCR matching)

    /// 楽曲をタイトルで検索（完全一致優先、部分一致も含む）
    func searchSongs(query: String, limit: Int = 10) throws -> [Song] {
        try dbQueue.read { db in
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }

            // 完全一致を先に取得
            let exact = try Song
                .filter(Column("title") == trimmed)
                .fetchAll(db)

            if !exact.isEmpty { return exact }

            // 部分一致
            let pattern = "%\(trimmed)%"
            return try Song
                .filter(Column("title").like(pattern) || Column("title_kana").like(pattern))
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Calendar Queries

    /// 指定期間のカレンダーエントリを取得（公演・リリース・誕生日）
    func fetchCalendarEntries(in interval: DateInterval) throws -> [CalendarEntry] {
        let startStr = Self.calendarDateFormatter.string(from: interval.start)
        let endStr = Self.calendarDateFormatter.string(from: interval.end)

        let shows: [CalendarEntry] = try dbQueue.read { db in
            let sql = """
                SELECT s.id, s.event_id, s.name, s.date, s.venue, s.venue_city,
                       s.start_time, s.sort_order, s.performer_type,
                       e.name AS event_name, e.brand_id, e.kind AS event_kind,
                       b.color AS brand_color
                FROM shows s
                JOIN events e ON s.event_id = e.id
                LEFT JOIN brands b ON e.brand_id = b.id
                WHERE s.date >= ? AND s.date <= ?
                ORDER BY s.date, s.sort_order
                """
            return try Row.fetchAll(db, sql: sql, arguments: [startStr, endStr]).map { row in
                CalendarEntry.show(CalendarShowRow(
                    show: Show(
                        id: row["id"],
                        eventId: row["event_id"],
                        name: row["name"],
                        date: row["date"],
                        venue: row["venue"],
                        venueCity: row["venue_city"],
                        startTime: row["start_time"],
                        sortOrder: row["sort_order"],
                        performerType: row["performer_type"]
                    ),
                    eventName: row["event_name"],
                    brandId: row["brand_id"],
                    brandColor: row["brand_color"],
                    eventKind: row["event_kind"]
                ))
            }
        }

        let releases: [CalendarEntry] = try dbQueue.read { db in
            let songs = try Song
                .filter(Column("release_date") >= startStr && Column("release_date") <= endStr)
                .filter(Column("parent_song_id") == nil)
                .order(Column("release_date"), Column("title_kana"))
                .fetchAll(db)
            var byDate: [String: [Song]] = [:]
            for song in songs {
                guard let date = song.releaseDate else { continue }
                byDate[date, default: []].append(song)
            }
            return byDate.map { date, songs in CalendarEntry.release(date: date, songs: songs) }
        }

        let birthdays: [CalendarEntry] = try dbQueue.read { db in
            let allIdols = try Idol.filter(Column("birthday") != nil).fetchAll(db)
            return allIdols.compactMap { idol -> CalendarEntry? in
                guard let birthdayDate = Self.birthdayDate(for: idol, in: interval) else { return nil }
                guard birthdayDate >= interval.start && birthdayDate <= interval.end else { return nil }
                return .birthday(idol)
            }
        }

        // チケット日程。受付開始 + 締切が揃えば「受付期間」を日跨ぎ帯 (.ticketPeriod) に、
        // 開始が無ければ締切を単日点に。当落発表は常に単日点。
        // ticket_deadline は自由記述もあり得るので YYYY-MM-DD にパースできた値だけ採用する。
        let tickets: [CalendarEntry] = try dbQueue.read { db in
            let sql = """
                SELECT e.id, e.name, e.ticket_open_date, e.ticket_deadline, e.ticket_lottery_date, e.ticket_url,
                       b.color AS brand_color
                FROM events e
                LEFT JOIN brands b ON e.brand_id = b.id
                WHERE e.ticket_open_date IS NOT NULL
                   OR e.ticket_deadline IS NOT NULL
                   OR e.ticket_lottery_date IS NOT NULL
                """
            // YYYY-MM-DD としてパースできる文字列だけ返す (自由記述を弾く)。
            func validDate(_ value: String?) -> String? {
                guard let v = value, Self.calendarDateFormatter.date(from: v) != nil else { return nil }
                return v
            }
            var rows: [CalendarEntry] = []
            for row in try Row.fetchAll(db, sql: sql) {
                let eventId: String = row["id"]
                let name: String = row["name"]
                let brandColor: String? = row["brand_color"]
                let url: String? = row["ticket_url"]
                let open = validDate(row["ticket_open_date"])
                let deadline = validDate(row["ticket_deadline"])
                let lottery = validDate(row["ticket_lottery_date"])

                if let open, let deadline, open <= deadline {
                    // 受付開始 + 締切が揃う → 受付期間スパン (表示レンジと重なる場合のみ)。
                    if open <= endStr, deadline >= startStr {
                        rows.append(.ticketPeriod(TicketPeriodRow(
                            eventId: eventId, eventName: name, brandColor: brandColor,
                            start: open, end: deadline, url: url
                        )))
                    }
                } else if let deadline, deadline >= startStr, deadline <= endStr {
                    // 受付開始が無い場合は締切を単日点で。
                    rows.append(.ticket(TicketCalendarRow(
                        eventId: eventId, eventName: name, brandColor: brandColor,
                        date: deadline, kind: .deadline, url: url
                    )))
                }
                // 当落発表は常に単日点。
                if let lottery, lottery >= startStr, lottery <= endStr {
                    rows.append(.ticket(TicketCalendarRow(
                        eventId: eventId, eventName: name, brandColor: brandColor,
                        date: lottery, kind: .lottery, url: url
                    )))
                }
            }
            return rows
        }

        return (shows + releases + birthdays + tickets).sorted { lhs, rhs in
            if lhs.dateString != rhs.dateString { return lhs.dateString < rhs.dateString }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    /// "--MM-DD" 形式の誕生日を interval 内の年に展開して Date を返す
    /// 2月29日など非閏年に存在しない日付は 2月28日にフォールバック
    private static func birthdayDate(for idol: Idol, in interval: DateInterval) -> Date? {
        guard let birthday = idol.birthday, birthday.hasPrefix("--") else { return nil }
        let parts = birthday.dropFirst(2).split(separator: "-")
        guard parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]) else { return nil }

        var jstCalendar = Calendar(identifier: .gregorian)
        jstCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let year = jstCalendar.component(.year, from: interval.start)
        let comps = DateComponents(year: year, month: month, day: day)
        if let date = jstCalendar.date(from: comps) { return date }
        // 非閏年の 2/29 → 2/28 にフォールバック
        if month == 2 && day == 29 {
            return jstCalendar.date(from: DateComponents(year: year, month: 2, day: 28))
        }
        return nil
    }

    private static let calendarDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        // JST 固定: 海外渡航中でも日付がズレないようにする
        fmt.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return fmt
    }()

    static func parseDate(_ string: String) -> Date? {
        calendarDateFormatter.date(from: string)
    }

    // MARK: - CloudKit Sync Upsert Methods

    /// 全レコードを1トランザクション内に一括 upsert する。
    /// 中断時は全体ロールバックされ、FK孤立を防ぐ。メモリ節約のためチャンク単位で処理。
    private func upsertChunked<T: PersistableRecord>(_ records: [T], chunkSize: Int = 500) throws {
        try dbQueue.write { db in
            for chunk in records.chunks(ofCount: chunkSize) {
                for record in chunk {
                    try record.insert(db, onConflict: .replace)
                }
            }
        }
    }

    func upsertBrands(_ brands: [Brand]) throws { try upsertChunked(brands) }
    func upsertIdols(_ idols: [Idol]) throws { try upsertChunked(idols) }
    func upsertEvents(_ events: [Event]) throws { try upsertChunked(events) }
    func upsertShows(_ shows: [Show]) throws { try upsertChunked(shows) }
    func upsertSongs(_ songs: [Song]) throws { try upsertChunked(songs) }
    func upsertUnits(_ units: [Unit]) throws { try upsertChunked(units) }
    func upsertIdolBrands(_ idolBrands: [IdolBrand]) throws { try upsertChunked(idolBrands) }
    func upsertSongArtists(_ songArtists: [SongArtist]) throws { try upsertChunked(songArtists) }
    func upsertUnitMembers(_ unitMembers: [UnitMember]) throws { try upsertChunked(unitMembers) }
    func upsertShowCasts(_ showCasts: [ShowCast]) throws { try upsertChunked(showCasts) }
    func upsertSetlistItems(_ setlistItems: [SetlistItem]) throws { try upsertChunked(setlistItems) }
    func upsertSetlistPerformers(_ setlistPerformers: [SetlistPerformer]) throws { try upsertChunked(setlistPerformers) }

    /// 編集 UI 用: 全曲を id+title だけのコンパクト型で返す。
    func fetchAllSongsForPicker() throws -> [PickedSong] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, title FROM songs ORDER BY title")
            return rows.map { PickedSong(id: $0["id"], title: $0["title"]) }
        }
    }

    /// 編集 UI 用: 出演者 picker に出す全アイドル (sort_order 順)。
    /// Cast 廃止により idol を直接返すようになった。
    func fetchAllIdolsForPicker() throws -> [Idol] {
        try dbQueue.read { db in
            try Idol.order(Column("sort_order")).fetchAll(db)
        }
    }

    /// admin 編集: 指定 show の setlist を完全置換 (旧 items/performers 削除 → 新 items/performers 挿入)。
    /// CloudKit 側書き込み成功後にローカル DB を一致させるために呼ぶ。
    func replaceSetlist(showId: String, items: [SetlistItem], performers: [SetlistPerformer]) throws {
        try dbQueue.write { db in
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
    }

    // MARK: - SongCall / SongVideo Methods

    func upsertSongCalls(_ calls: [SongCall]) throws {
        try upsertAll(calls)
    }

    func fetchCallResponsesForSong(songId: String) throws -> [SongCall] {
        try fetchBySongId(songId)
    }

    func upsertSongVideos(_ videos: [SongVideo]) throws {
        try upsertAll(videos)
    }

    func fetchVideosForSong(songId: String) throws -> [SongVideo] {
        try fetchBySongId(songId)
    }

    private func upsertAll<T: PersistableRecord>(_ records: [T]) throws {
        try dbQueue.write { db in
            for record in records {
                try record.insert(db, onConflict: .replace)
            }
        }
    }

    private func fetchBySongId<T: FetchableRecord & TableRecord>(_ songId: String) throws -> [T] {
        try dbQueue.read { db in
            try T.filter(Column("song_id") == songId)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    // MARK: - CloudKit Sync Delete Methods

    /// recordType に対応するテーブル名を返す（単一PK テーブルのみ）
    private static func tableName(for recordType: String) -> String? {
        tableInfo(for: recordType)?.table
    }

    /// recordType ごとの (table 名, PK カラム) マップ。
    /// 複合 PK の場合 recordName は "{table}-{pk1}-{pk2}" 形式 (seed_cloudkit.py の make_record_name と一致)。
    private static func tableInfo(for recordType: String) -> (table: String, pkColumns: [String])? {
        switch recordType {
        case "Brand":            return ("brands", ["id"])
        case "Idol":             return ("idols", ["id"])
        case "Event":            return ("events", ["id"])
        case "ImasUnit":         return ("units", ["id"])
        case "Show":             return ("shows", ["id"])
        case "Song":             return ("songs", ["id"])
        case "SongCall":         return ("song_calls", ["id"])
        case "SongVideo":        return ("song_videos", ["id"])
        case "SetlistItem":      return ("setlist_items", ["id"])
        case "IdolBrand":        return ("idol_brands", ["idol_id", "brand_id"])
        case "UnitMember":       return ("unit_members", ["unit_id", "idol_id"])
        case "SongArtist":       return ("song_artists", ["song_id", "idol_id", "role"])
        case "ShowCast":         return ("show_cast", ["show_id", "idol_id"])
        case "SetlistPerformer": return ("setlist_performers", ["setlist_item_id", "idol_id"])
        // CastMember / IdolCast は廃止 (idol.voiceActors に統合)。 sync 対象外。
        default:                 return nil
        }
    }

    /// composite PK テーブルの recordName "{table}-{v1}-{v2}" をパースして PK 値配列を返す。
    /// table 名や PK 値に "-" が含まれてもよいよう、prefix と pk count から逆算する。
    private static func parseCompositeRecordName(_ recordName: String, table: String, pkCount: Int) -> [String]? {
        let prefix = "\(table)-"
        guard recordName.hasPrefix(prefix) else { return nil }
        let body = String(recordName.dropFirst(prefix.count))
        // pkCount-1 個の "-" で分割。table 名以降に最大 pkCount 個の値があるが、値内 "-" 許容のため
        // 「最初の n-1 個の '-' で前から split + 残りは最後の値」でなく、
        // 「最後の n-1 個の '-' で後ろから split」する方が安全。idol/cast id 末尾に "-" は通常ないが念のため。
        let parts = body.split(separator: "-", maxSplits: pkCount - 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == pkCount else { return nil }
        return parts
    }

    /// soft delete: CloudKit の deletedAt 付きレコードをローカルDBから物理削除する。
    /// 単一 PK は ids = [recordName] 直接、複合 PK は recordName を split して WHERE col1=? AND col2=? で削除。
    func deleteRecords(recordType: String, ids: [String]) throws {
        guard !ids.isEmpty, let info = Self.tableInfo(for: recordType) else { return }
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
                    guard let parts = Self.parseCompositeRecordName(recordName, table: info.table, pkCount: info.pkColumns.count) else { continue }
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
    func deleteOrphans(recordType: String, validIds: Set<String>) throws {
        guard !validIds.isEmpty, let table = Self.tableName(for: recordType) else { return }
        try dbQueue.write { db in
            // ローカルの全 ID を取得して差分を計算
            let localIds = try String.fetchAll(db, sql: "SELECT id FROM \(table)")
            let orphanIds = localIds.filter { !validIds.contains($0) }
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

    // MARK: - Album Queries

    /// CDシリーズ別アルバム一覧
    func fetchAlbums(brandIds: Set<String> = [], query: String?) throws -> [AlbumSummary] {
        try dbQueue.read { db in
            var sql = """
                SELECT cd_series,
                       MIN(artwork_url) AS artwork_url,
                       COUNT(*) AS song_count,
                       MIN(release_date) AS earliest_date,
                       MAX(release_date) AS latest_date,
                       GROUP_CONCAT(DISTINCT brand_id) AS brand_ids
                FROM songs
                WHERE cd_series IS NOT NULL AND cd_series != ''
                """
            var args: [DatabaseValueConvertible] = []

            if !brandIds.isEmpty {
                let placeholders = brandIds.map { _ in "?" }.joined(separator: ",")
                sql += " AND brand_id IN (\(placeholders))"
                for id in brandIds { args.append(id) }
            }
            if let query, !query.isEmpty {
                sql += " AND cd_series LIKE ? ESCAPE '\\'"
                args.append("%\(query.likeEscaped)%")
            }

            sql += " GROUP BY cd_series ORDER BY MIN(release_date) DESC"

            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { row in
                let brandIds = (row["brand_ids"] as String?)
                    .map { $0.split(separator: ",").map(String.init).filter { !$0.isEmpty } } ?? []
                return AlbumSummary(
                    cdSeries: row["cd_series"],
                    artworkUrl: row["artwork_url"],
                    songCount: row["song_count"] ?? 0,
                    earliestDate: row["earliest_date"],
                    latestDate: row["latest_date"],
                    brandIds: brandIds
                )
            }
        }
    }

    /// CDシリーズグループ別一覧 (LIVE THE@TER PERFORMANCE 等の括り)
    func fetchSeries(brandIds: Set<String> = [], query: String?) throws -> [SeriesSummary] {
        try dbQueue.read { db in
            var sql = """
                SELECT series_group AS name,
                       COUNT(*) AS song_count,
                       COUNT(DISTINCT cd_series) AS cd_count,
                       MIN(release_date) AS earliest_date,
                       MAX(release_date) AS latest_date,
                       GROUP_CONCAT(DISTINCT brand_id) AS brand_ids,
                       (SELECT s2.artwork_url FROM songs s2
                        WHERE s2.series_group = songs.series_group
                          AND s2.artwork_url IS NOT NULL AND s2.artwork_url != ''
                        ORDER BY s2.release_date LIMIT 1) AS artwork_url
                FROM songs
                WHERE series_group IS NOT NULL AND series_group != ''
                """
            var args: [DatabaseValueConvertible] = []

            if !brandIds.isEmpty {
                let placeholders = brandIds.map { _ in "?" }.joined(separator: ",")
                sql += " AND brand_id IN (\(placeholders))"
                for id in brandIds { args.append(id) }
            }
            if let query, !query.isEmpty {
                sql += " AND series_group LIKE ? ESCAPE '\\'"
                args.append("%\(query.likeEscaped)%")
            }

            sql += " GROUP BY series_group ORDER BY MIN(release_date) DESC"

            let summaries = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return summaries.map { row in
                let brandIds = (row["brand_ids"] as String?)
                    .map { $0.split(separator: ",").map(String.init).filter { !$0.isEmpty } } ?? []
                return SeriesSummary(
                    name: row["name"],
                    songCount: row["song_count"] ?? 0,
                    cdCount: row["cd_count"] ?? 0,
                    earliestDate: row["earliest_date"],
                    latestDate: row["latest_date"],
                    artworkUrl: row["artwork_url"],
                    brandIds: brandIds
                )
            }
        }
    }

    // MARK: - UserMark Methods

    func upsertUserMark(entity: UserMarkEntity, id: String, kind: UserMarkKind, boolValue: Bool) throws {
        try upsertUserMarkRow(entity: entity, id: id, kind: kind) { existing in
            existing.boolValue = boolValue
        } makeNew: {
            UserMark(entityType: entity.rawValue, entityId: id, kind: kind.rawValue,
                     boolValue: boolValue, textValue: nil,
                     updatedAt: ISO8601DateFormatter.shared.string(from: Date()))
        }
    }

    func upsertUserMarkNote(entity: UserMarkEntity, id: String, text: String?) throws {
        try upsertUserMarkText(entity: entity, id: id, kind: .note, text: text)
    }

    /// textValue を持つ mark (note / seat 等) の汎用 upsert。
    func upsertUserMarkText(entity: UserMarkEntity, id: String, kind: UserMarkKind, text: String?) throws {
        try upsertUserMarkRow(entity: entity, id: id, kind: kind) { existing in
            existing.textValue = text
        } makeNew: {
            UserMark(entityType: entity.rawValue, entityId: id, kind: kind.rawValue,
                     boolValue: false, textValue: text,
                     updatedAt: ISO8601DateFormatter.shared.string(from: Date()))
        }
    }

    private func upsertUserMarkRow(
        entity: UserMarkEntity,
        id: String,
        kind: UserMarkKind,
        update: (inout UserMark) -> Void,
        makeNew: () -> UserMark
    ) throws {
        try dbQueue.write { db in
            let now = ISO8601DateFormatter.shared.string(from: Date())
            if var existing = try UserMark.filter(
                UserMark.Columns.entityType == entity.rawValue &&
                UserMark.Columns.entityId == id &&
                UserMark.Columns.kind == kind.rawValue
            ).fetchOne(db) {
                update(&existing)
                existing.updatedAt = now
                try existing.save(db)
            } else {
                try makeNew().insert(db)
            }
        }
    }

    func fetchUserMark(entity: UserMarkEntity, id: String, kind: UserMarkKind) throws -> UserMark? {
        try dbQueue.read { db in
            try UserMark.filter(
                UserMark.Columns.entityType == entity.rawValue &&
                UserMark.Columns.entityId == id &&
                UserMark.Columns.kind == kind.rawValue
            ).fetchOne(db)
        }
    }

    func fetchUserMarks(entity: UserMarkEntity, id: String) throws -> [UserMark] {
        try dbQueue.read { db in
            try UserMark.filter(
                UserMark.Columns.entityType == entity.rawValue &&
                UserMark.Columns.entityId == id
            ).fetchAll(db)
        }
    }

    func fetchMarkedEntityIds(entity: UserMarkEntity, kind: UserMarkKind) throws -> [String] {
        try dbQueue.read { db in
            try UserMark.filter(
                UserMark.Columns.entityType == entity.rawValue &&
                UserMark.Columns.kind == kind.rawValue &&
                UserMark.Columns.boolValue == true
            ).fetchAll(db).map(\.entityId)
        }
    }

    /// entity 横断で kind に一致する全 UserMark を返す。
    /// note 種別は textValue が非空のもの、それ以外は boolValue == true のもの。
    /// 全ユーザーマーク (全 kind・bool false 行も含む) を返す。iCloud バックアップ用。
    func allUserMarks() throws -> [UserMark] {
        try dbQueue.read { db in try UserMark.fetchAll(db) }
    }

    /// バックアップからの復元 (非破壊): ローカルに無い (entity,id,kind) の行だけ追加する。
    /// 既存ローカル行は決して上書き/削除しない。戻り値は追加件数。
    @discardableResult
    func restoreUserMarksIfAbsent(_ marks: [UserMark]) throws -> Int {
        try dbQueue.write { db in
            var inserted = 0
            for m in marks {
                let exists = try UserMark
                    .filter(UserMark.Columns.entityType == m.entityType
                            && UserMark.Columns.entityId == m.entityId
                            && UserMark.Columns.kind == m.kind)
                    .fetchCount(db) > 0
                if !exists {
                    try m.insert(db)
                    inserted += 1
                }
            }
            return inserted
        }
    }

    func fetchAllUserMarks(kind: UserMarkKind) throws -> [UserMark] {
        try dbQueue.read { db in
            let base = UserMark.filter(UserMark.Columns.kind == kind.rawValue)
            let request = kind == .note
                ? base.filter(UserMark.Columns.textValue != nil && UserMark.Columns.textValue != "")
                : base.filter(UserMark.Columns.boolValue == true)
            return try request.fetchAll(db)
        }
    }

    // MARK: - Auto Collected (参加ライブから自動判定)

    /// 指定 idol_id 群のうち、 いずれかが歌唱者 (role='original') として紐付いてる song_id 集合。
    /// 「担当アイドル の曲」 など bulk 絞り込み用。
    func fetchSongIdsWithAnyArtist(idolIds: Set<String>) throws -> Set<String> {
        guard !idolIds.isEmpty else { return [] }
        return try dbQueue.read { db in
            let placeholders = idolIds.map { _ in "?" }.joined(separator: ",")
            let sql = "SELECT DISTINCT song_id FROM song_artists WHERE role='original' AND idol_id IN (\(placeholders))"
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(Array(idolIds)))
            return Set(rows.compactMap { row -> String? in row["song_id"] })
        }
    }

    /// 一覧表示用に Song を SongWithArtists 化 (artistNames + performerIdols を一括解決)。
    /// 単一 fetch クエリ + N+1 防止の performer map 結合。
    func fetchSongsWithArtists(ids: [String]) throws -> [SongWithArtists] {
        guard !ids.isEmpty else { return [] }
        let songs = try fetchSongs(ids: ids)
        let perfMap = try fetchSongPerformerIdolsMap(songIds: ids)
        return songs.map { song in
            var x = SongWithArtists(song: song, artistNames: song.singerLabel ?? "")
            x.performerIdols = perfMap[song.id] ?? []
            return x
        }
    }

    /// ユーザが参加した event/show のセトリで、 song_id ごとの回収回数 (同 show 重複は 1 と数える)。
    /// マイマーク回収済タブの「現地回収 N 回」 表示用。
    func fetchSongCollectedCounts() throws -> [String: Int] {
        try dbQueue.read { db in
            let sql = """
                SELECT si.song_id AS song_id, COUNT(DISTINCT si.show_id) AS cnt
                FROM setlist_items si
                JOIN shows sh ON sh.id = si.show_id
                JOIN events e ON e.id = sh.event_id
                WHERE e.kind IN (\(Self.realLiveKinds))
                AND (
                    si.show_id IN (
                        SELECT entity_id FROM user_marks
                        WHERE entity_type='show' AND kind='attended' AND bool_value=1
                          AND \(attendedTypeCondition)
                    ) OR si.show_id IN (
                        SELECT id FROM shows WHERE event_id IN (
                            SELECT entity_id FROM user_marks
                            WHERE entity_type='event' AND kind='attended' AND bool_value=1
                        )
                    )
                )
                GROUP BY si.song_id
                """
            let rows = try Row.fetchAll(db, sql: sql)
            var m: [String: Int] = [:]
            for row in rows {
                let sid: String = row["song_id"]
                let cnt: Int = row["cnt"] ?? 0
                m[sid] = cnt
            }
            return m
        }
    }

    /// 回収に配信参加も含めるユーザー設定 (既定=現地のみ)。地方勢など配信中心の人向け。
    static let collectionIncludeStreamKey = "collection_include_stream"
    private var collectionIncludeStream: Bool {
        UserDefaults.standard.bool(forKey: Self.collectionIncludeStreamKey)
    }
    /// 回収対象とするリアルライブの kind (歌枠/配信番組/リリイベ/ラジオ等は除外)。
    private static let realLiveKinds = "'live','festival'"

    /// 参加した公演の .attended 種別条件 (現地のみ / 設定により配信も)。
    private var attendedTypeCondition: String {
        collectionIncludeStream ? "1=1" : "(text_value IS NULL OR text_value='live')"
    }

    /// ユーザが参加した「リアルライブ」のセトリに含まれる全 song_id を返す (回収済み)。
    /// 回収はリアルライブ(live/festival)のみ・参加種別は設定に従う(既定=現地のみ)。
    func fetchAutoCollectedSongIds() throws -> Set<String> {
        try dbQueue.read { db in
            let sql = """
                SELECT DISTINCT si.song_id
                FROM setlist_items si
                JOIN shows sh ON si.show_id = sh.id
                JOIN events e ON e.id = sh.event_id
                WHERE e.kind IN (\(Self.realLiveKinds))
                AND (
                    sh.id IN (
                        SELECT entity_id FROM user_marks
                        WHERE entity_type='show' AND kind='attended' AND bool_value=1
                          AND \(attendedTypeCondition)
                    )
                    OR sh.event_id IN (
                        SELECT entity_id FROM user_marks
                        WHERE entity_type='event' AND kind='attended' AND bool_value=1
                    )
                )
                """
            let rows = try Row.fetchAll(db, sql: sql)
            return Set(rows.compactMap { row -> String? in row["song_id"] })
        }
    }

    /// その曲を披露した、ユーザが参加済みの show 一覧 (親 event 名込み)
    func fetchCollectedShows(for songId: String) throws -> [ShowWithEventName] {
        try dbQueue.read { db in
            let sql = """
                SELECT DISTINCT sh.id, sh.event_id, sh.name, sh.date, sh.venue,
                                e.name AS event_name
                FROM shows sh
                JOIN setlist_items si ON si.show_id = sh.id
                JOIN events e ON e.id = sh.event_id
                WHERE si.song_id = ?
                AND (
                    sh.id IN (
                        SELECT entity_id FROM user_marks
                        WHERE entity_type='show' AND kind='attended' AND bool_value=1
                    )
                    OR sh.event_id IN (
                        SELECT entity_id FROM user_marks
                        WHERE entity_type='event' AND kind='attended' AND bool_value=1
                    )
                )
                ORDER BY sh.date DESC
                """
            return try ShowWithEventName.fetchAll(db, sql: sql, arguments: [songId])
        }
    }

    // MARK: - Collection Dashboard

    /// ブランドごとの現地回収進捗 (回収済み曲数 / そのブランド全曲数)。
    /// 分母は brand_id を持つ全曲、分子は autoCollected ∩ そのブランドの曲。
    /// 重い全曲スキャンになるので呼び出し側で結果をキャッシュすること。
    func fetchBrandCollectionProgress(collectedIds: Set<String>) throws -> [BrandCollectionProgress] {
        try dbQueue.read { db in
            let brandRows = try Row.fetchAll(db, sql: """
                SELECT b.id AS id, b.short_name AS short_name, b.color AS color,
                       COUNT(s.id) AS total
                FROM brands b
                LEFT JOIN songs s ON b.id = s.brand_id
                GROUP BY b.id
                ORDER BY b.sort_order
                """)
            // song_id → brand_id を 1 クエリで引いて、collected を集計する。
            var collectedByBrand: [String: Int] = [:]
            if !collectedIds.isEmpty {
                let placeholders = collectedIds.map { _ in "?" }.joined(separator: ",")
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT brand_id FROM songs WHERE id IN (\(placeholders)) AND brand_id IS NOT NULL",
                    arguments: StatementArguments(Array(collectedIds))
                )
                for row in rows {
                    guard let bid: String = row["brand_id"] else { continue }
                    collectedByBrand[bid, default: 0] += 1
                }
            }
            return brandRows.map { row in
                let bid: String = row["id"]
                return BrandCollectionProgress(
                    brandId: bid,
                    shortName: row["short_name"],
                    color: row["color"],
                    collected: collectedByBrand[bid] ?? 0,
                    total: row["total"] ?? 0
                )
            }
        }
    }

    /// 指定 song_id 群 (例: 担当アイドルのオリ曲) の生涯リアルライブ披露回数マップ。
    /// 0 回の曲も結果に含める (未披露=レア表示のため)。
    func fetchLifetimePlayCounts(songIds: Set<String>) throws -> [String: Int] {
        guard !songIds.isEmpty else { return [:] }
        return try dbQueue.read { db in
            let placeholders = songIds.map { _ in "?" }.joined(separator: ",")
            let sql = """
                SELECT si.song_id AS song_id, COUNT(*) AS cnt
                FROM setlist_items si
                JOIN shows sh ON sh.id = si.show_id
                JOIN events e ON e.id = sh.event_id
                WHERE e.kind IN (\(Self.realLiveKinds))
                  AND si.song_id IN (\(placeholders))
                GROUP BY si.song_id
                """
            // 未披露 (0 回) も結果に残すため、まず全 song_id を 0 で埋めてから上書きする。
            var playCounts: [String: Int] = Dictionary(uniqueKeysWithValues: songIds.map { ($0, 0) })
            for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(Array(songIds))) {
                let sid: String = row["song_id"]
                playCounts[sid] = row["cnt"] ?? 0
            }
            return playCounts
        }
    }

    /// 未回収曲一覧。 candidateIds のうち collectedIds に無い曲を、 披露回数つきで返す。
    /// 並びは披露回数の多い順 (= まず定番から回収できるように)。
    func fetchUncollectedSongs(candidateIds: Set<String>, collectedIds: Set<String>) throws -> [UncollectedSong] {
        let targetIds = candidateIds.subtracting(collectedIds)
        guard !targetIds.isEmpty else { return [] }
        let songs = try fetchSongs(ids: Array(targetIds))
        let playCounts = try fetchLifetimePlayCounts(songIds: targetIds)
        return songs
            .map { UncollectedSong(song: $0, playCount: playCounts[$0.id] ?? 0) }
            .sorted { ($0.playCount, $1.song.titleKana ?? "") > ($1.playCount, $0.song.titleKana ?? "") }
    }

    /// 「この公演で未回収が聴けるかも」候補。
    /// 今日以降の公演について、 親ブランドが過去に「自分の未回収曲」を披露した異なり数を
    /// likelyCount として算出し、 多い順に返す。 likelyCount=0 の公演は除外する。
    func fetchUpcomingCatchChances(uncollectedIds: Set<String>, today: String, limit: Int = 8) throws -> [UpcomingCatchChance] {
        guard !uncollectedIds.isEmpty else { return [] }
        return try dbQueue.read { db in
            // 未回収曲ごとに、過去リアルライブで披露された brand_id 集合を引く。
            let placeholders = uncollectedIds.map { _ in "?" }.joined(separator: ",")
            let brandHitRows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT e.brand_id AS brand_id, si.song_id AS song_id
                FROM setlist_items si
                JOIN shows sh ON sh.id = si.show_id
                JOIN events e ON e.id = sh.event_id
                WHERE e.kind IN (\(Self.realLiveKinds))
                  AND e.brand_id IS NOT NULL
                  AND si.song_id IN (\(placeholders))
                """, arguments: StatementArguments(Array(uncollectedIds)))
            // brand_id → 過去に披露された未回収曲の異なり数
            var uncollectedByBrand: [String: Int] = [:]
            for row in brandHitRows {
                guard let bid: String = row["brand_id"] else { continue }
                uncollectedByBrand[bid, default: 0] += 1
            }
            guard !uncollectedByBrand.isEmpty else { return [] }

            // 今日以降の公演 (リアルライブのみ) を、親ブランドつきで取得。
            let showRows = try Row.fetchAll(db, sql: """
                SELECT s.id, s.event_id, s.name, s.date, s.venue, s.venue_city,
                       s.start_time, s.sort_order, s.performer_type,
                       e.name AS event_name, e.brand_id AS brand_id,
                       b.color AS brand_color
                FROM shows s
                JOIN events e ON s.event_id = e.id
                LEFT JOIN brands b ON e.brand_id = b.id
                WHERE s.date >= ? AND e.kind IN (\(Self.realLiveKinds))
                ORDER BY s.date ASC, s.sort_order ASC
                """, arguments: [today])

            return showRows.compactMap { row -> UpcomingCatchChance? in
                let bid: String? = row["brand_id"]
                guard let bid, let likely = uncollectedByBrand[bid], likely > 0 else { return nil }
                return UpcomingCatchChance(
                    show: Show(
                        id: row["id"], eventId: row["event_id"], name: row["name"],
                        date: row["date"], venue: row["venue"], venueCity: row["venue_city"],
                        startTime: row["start_time"], sortOrder: row["sort_order"],
                        performerType: row["performer_type"]
                    ),
                    eventName: row["event_name"],
                    brandId: bid,
                    brandColor: row["brand_color"],
                    likelyCount: likely
                )
            }
            .sorted { ($0.likelyCount, $1.show.date) > ($1.likelyCount, $0.show.date) }
            .prefix(limit)
            .map { $0 }
        }
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

private struct SongPerfCount: FetchableRecord, Sendable {
    let songId: String
    let cnt: Int

    init(row: Row) {
        songId = row["song_id"]
        cnt = row["cnt"]
    }
}
