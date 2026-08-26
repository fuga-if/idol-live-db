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
            // 空 DB からの生成は必ず移行に先に作らせる。コアが先に同じ表を作ると
            // v1_create_tables の ifNotExists 無し CREATE TABLE が「already exists」で
            // 落ち、起動不能になる。
            applyCoreMasterSchema(at: dbURL.path)
            return pool
        }

        let pool = try DatabasePool(path: dbURL.path, configuration: config)
        try seedMigrationHistoryIfNeeded(pool)
        try DatabaseMigrations.migrator.migrate(pool)
        // コアが持つマスタスキーマの正本は、GRDB の移行を流し**終えてから**当てる。
        //
        // 逆順にすると壊れる。seedMigrationHistoryIfNeeded は「列があるなら適用済み」と
        // 印を付けるだけなので、コアが先に列を足すと、その列を足す移行が抱えている
        // **データ側の仕事まで丸ごと飛ぶ**。v21 (show_cast.cast_role) で実際に起きる:
        // コアが cast_role を足す → seed が v21 を適用済みと誤認 → 後から走る v19_drop_cast が
        // show_cast を (show_id, idol_id) で作り直して cast_role ごと落とす → v21 は印済みなので
        // 二度と走らず、列も主演 10 行も戻らない (以後 cast_role を読む詳細画面が全部 throw する)。
        // GRDB の DatabaseMigrator は未適用の移行を登録順に流すだけで、後ろの印が前の移行を
        // 止めることはない。だから「先に印を付ける」= 「その移行を永久に捨てる」になる。
        //
        // 後ろに置けば seed は誰も触っていない実物を見るので印が嘘にならず、移行が作り切った
        // 形に対して正本の不足分だけを足す形になる。索引も同じで、列が揃った後なら
        // idx_setlist_performers_idol (v19 前は setlist_performers に idol_id が無い) が失敗しない。
        applyCoreMasterSchema(at: dbURL.path)
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

    /// 共有コア (imas-core) が持つマスタスキーマの正本を DB へ寄せる。追加しかしない。
    ///
    /// 出すのは `CREATE TABLE` と `ALTER TABLE ADD COLUMN` だけで、DROP も作り直しもデータ
    /// 書き換えも無い。正本に `user_marks` / `personal_tags` を含めていないので、端末にしか
    /// 無いユーザーデータ (担当・お気に入り・メモ) には構造的に届かない。
    ///
    /// **必ず GRDB の移行の後に呼ぶこと。** 理由は `openDatabase` 側の呼び出しコメントに書いた
    /// (先に呼ぶと seedMigrationHistoryIfNeeded の印が嘘になり、移行が持つデータ投入が飛ぶ)。
    ///
    /// **失敗しても投げない。** ここが throw すると `openDatabase` 経由で `init` の `fatalError`
    /// に直結して起動不能になる (マスタ削除で FK 孤児 → 起動クラッシュ → 審査 reject の実例がある)。
    /// 移行の後に呼ぶ以上、表と列は既に揃っている。ここで落ちて欠けるのは「正本にしか無い分」
    /// = `song_units` と、v20_ensure_indexes が持たない索引 (idx_song_units_song /
    /// idx_song_units_unit / idx_songs_series_group) だけで、遅くなっても壊れはしない。
    private static func applyCoreMasterSchema(at path: String) {
        do {
            let result = try ensureMasterSchema(dbPath: path)
            Logger.database.info(
                "[core-schema] applied=\(result.applied, privacy: .public) untouched=\(result.untouchedTables.joined(separator: ","), privacy: .public)"
            )
            // deferred = 追加だけでは埋められず人の移行を待つ項目。黙って消すと気付けないので必ず出す。
            for reason in result.deferred {
                Logger.database.error("[core-schema] deferred: \(reason, privacy: .public)")
            }
        } catch {
            // コア側の適用はトランザクションを張らず、最初の失敗でそれ以降の手を捨てる。
            // 「どこで止まったか」だけが手掛かりになるので、失敗した手の理由を含む本文をそのまま出す。
            Logger.database.error(
                "[core-schema] failed (以降の手は流れていない): \(String(describing: error), privacy: .public)"
            )
        }
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

            // v19: cast テーブルの不在**だけ**で判定する。
            // Bundle DB は cast/idol_cast 廃止済なので、ここで pre-populate しないと
            // 新規インストール時に v19 migration が「cast テーブル無し」で SQL エラー →
            // アプリ起動クラッシュ (Apple 審査 reject の原因)。
            //
            // ⚠️ 判定に**列の有無**を混ぜないこと。以前は `idols.voice_actors` の存在も
            // 見ていたが、声優履歴 (`idol_voice_actors`) への移行でその列を落とした瞬間に
            // 条件が成立しなくなり、新規インストールが全部起動クラッシュする状態になった。
            // ここで見るべきは「その migration が対象とするテーブルが既に無いか」だけ。
            let hasCastTable = try Row.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='cast'") != nil
            if !hasCastTable {
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

}
