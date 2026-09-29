import Foundation
import GRDB
import Observation
import os

@Observable
final class AppDatabase: Sendable {
    /// 起動時に `DatabaseBoot` が `prepare()` で開いた DB。
    ///
    /// 起動の流れを通らずに先に触られたときは、その場で開く (開けなければ止める。以前の起動と同じ)。
    /// 起動画面の後の経路では、開き終えたものが返るだけで待つことは無い。
    static var shared: AppDatabase {
        do {
            return try prepare()
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }

    /// 開き終えた DB。失敗は覚えない (復旧画面の「もう一度試す」で開き直せるように)。
    private static let preparedDatabase = OSAllocatedUnfairLock<AppDatabase?>(initialState: nil)

    /// 端末の DB (Documents/master.sqlite) を開く。無ければ同梱 DB を置き、移行・コアのスキーマ・
    /// reseed まで済ませる。1 度開けたら、以後は同じものを返す。
    ///
    /// 重い (初回は同梱 DB のコピーと移行、アプデ後は reseed) ので main thread から呼ばない。
    /// 起動時は `DatabaseBoot` が detached で呼ぶ。
    static func prepare() throws -> AppDatabase {
        try preparedDatabase.withLock { prepared in
            if let prepared { return prepared }
            let documents = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let pool = try openDatabase(
                at: documents.appendingPathComponent("master.sqlite"),
                bundleURL: Bundle.main.url(forResource: "master", withExtension: "sqlite"))
            let database = AppDatabase(writer: pool, reseedFailureMessage: lastReseedFailure)
            prepared = database
            return database
        }
    }

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

    /// 起動時 reseed が失敗した場合のユーザー可視メッセージ (起動アラートに出す)。開いた時点で決まる。
    let reseedFailureMessage: String?

    private init(writer: any DatabaseWriter, reseedFailureMessage: String?) {
        self.dbQueue = writer
        self.reseedFailureMessage = reseedFailureMessage
    }

    /// テスト用イニシャライザ
    convenience init(dbQueue: any DatabaseWriter) throws {
        self.init(writer: dbQueue, reseedFailureMessage: nil)
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

    /// `dbURL` の DB を開いて最新の形にする。無ければ `bundleURL` (同梱 DB) を置いてから。
    ///
    /// 同梱 DB → seedMigrationHistoryIfNeeded → 移行 → コアのスキーマ → reseed の順。
    /// テストは一時ファイルと同梱 DB を渡して、実機と同じ経路を通す。
    static func openDatabase(at dbURL: URL, bundleURL: URL?) throws -> DatabasePool {
        let fileManager = FileManager.default

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

        if let bundleURL {
            if !fileManager.fileExists(atPath: dbURL.path) {
                try fileManager.copyItem(at: bundleURL, to: dbURL)
                // 万一 Bundle DB が破損していたら検知して削除し、開くのをやめる (復旧画面になる)。
                // コード署名で起こり得ない前提だが、破損したまま使い始めるより安全。
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
        guard let bundleURL else { return pool }
        // reseedMasterTablesIfNeeded は破壊的 (DELETE + INSERT) なので失敗時はアプリ
        // 起動自体を止めないように吸収する。 失敗してもローカル DB の旧値で動作継続。
        do {
            try reseedMasterTablesIfNeeded(pool, bundleURL: bundleURL)
        } catch {
            let detail = "\(error.localizedDescription) | \(String(describing: error))"
            reseedState.withLock {
                $0.summary = "失敗: \(detail)"
                // ユーザーには「マスタ更新が反映されず旧データで動作している」ことを伝える。
                // 再インストールは勧めない。マイタグと家計簿は iCloud に無く、消えると戻せない。
                $0.failureDetail = "最新のデータ更新を取り込めませんでした。これまでのデータのまま使えます (次に起動したときにもう一度試します)。\n(詳細: \(error.localizedDescription))"
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
    /// **失敗しても投げない。** ここが throw すると DB を開けず、起動が復旧画面で止まる
    /// (マスタ削除で FK 孤児 → 起動クラッシュ → 審査 reject の実例がある)。
    /// 移行の後に呼ぶ以上、表と列は既に揃っている。ここで落ちて欠けるのは「正本にしか無い分」
    /// = `song_units` と、v20_ensure_indexes が持たない索引 (idx_song_units_song /
    /// idx_song_units_unit / idx_songs_series_group) だけで、遅くなっても壊れはしない。
    /// reseed はこの結果に頼らない (入れ直す表はコアの台帳から決まる)。
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
    ///
    /// 入れ直すのは**コアの台帳にあるマスタ表だけ** (allow-list)。端末にしか無い表
    /// (担当・マイタグ・家計簿) は台帳に無いので、同梱 DB に同名の表が入っても触らない。
    private static func reseedMasterTablesIfNeeded(_ dbQueue: any DatabaseWriter, bundleURL: URL) throws {
        // Bundle 内は read-only 領域なので GRDB/SQLite の open 試行 (WAL sidecar 等) で
        // SQLITE_CANTOPEN になる。 一旦 tmp に複製してそちらを ATTACH する。
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bundle_master_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        try FileManager.default.copyItem(at: bundleURL, to: tmpURL)

        // 判定は ATTACH 前に軽量な read で済ませる。
        var roConfig = Configuration()
        roConfig.readonly = true
        let bundleMeta = try DatabaseQueue(path: tmpURL.path, configuration: roConfig).read(Self.readReseedMeta)
        let localMeta = try dbQueue.read(Self.readReseedMeta)
        Logger.database.info("""
            [reseed] bundle=v\(bundleMeta.version, privacy: .public)/\(bundleMeta.shortHash, privacy: .public) \
            local=v\(localMeta.version, privacy: .public)/\(localMeta.shortHash, privacy: .public)
            """)
        guard reseedNeeded(bundleVersion: bundleMeta.version,
                           localVersion: localMeta.version,
                           bundleHash: bundleMeta.contentHash,
                           localHash: localMeta.contentHash) else { return }

        // コピー本体は純処理として分離 (テスト可能性 + 責務分離)。
        let (ok, skipped) = try Self.copyMasterTables(
            into: dbQueue,
            fromBundleAt: tmpURL.path,
            newVersion: bundleMeta.version,
            newContentHash: bundleMeta.contentHash
        )
        let summary = reseedSummaryLabel(
            localVersion: localMeta.version, bundleVersion: bundleMeta.version,
            ok: UInt32(ok), skipped: UInt32(skipped))
        reseedState.withLock {
            $0.summary = summary
            $0.failureDetail = nil
        }
        Logger.database.info("[reseed] done \(summary, privacy: .public)")
    }

    /// reseed の判定に使う meta 一式。
    private struct ReseedMeta {
        let version: Int64
        /// 同梱データの指紋。判定の主軸。古い DB には無いので optional。
        let contentHash: String?
        /// ログ用の短縮形。指紋が無い DB では "-"。
        var shortHash: String { contentHash.map { String($0.prefix(8)) } ?? "-" }
    }

    private static func readReseedMeta(_ db: Database) throws -> ReseedMeta {
        ReseedMeta(
            version: reseedParseDataVersion(
                value: try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key='data_version'")),
            contentHash: try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key='content_hash'")
        )
    }

    /// Bundle DB (`bundlePath`) の内容で `writer` 側マスタテーブルを一括コピーする純処理。
    /// 入れ直すのは、コアの台帳にあるマスタ表のうち両方の DB にあるもの (決めるのはコア)。
    /// `newVersion` を `meta.data_version` に書き、`(ok, skipped)` を返す。
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
        newVersion: Int64,
        newContentHash: String?
    ) throws -> (ok: Int, skipped: Int) {
        var ok = 0
        var skipped = 0
        try writer.writeWithoutTransaction { db in
            try db.execute(sql: "ATTACH DATABASE ? AS bundle", arguments: [bundlePath])
            defer { try? db.execute(sql: "DETACH DATABASE bundle") }

            let bundleTables = try String.fetchAll(db, sql: "SELECT name FROM bundle.sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
            let localTables = try String.fetchAll(db, sql: "SELECT name FROM main.sqlite_master WHERE type='table'")
            // 台帳にあるマスタ表のうち、Bundle 側にもローカルにもあるものだけを再投入する (判定はコア)。
            let targets = reseedMasterTargetTables(bundleTables: bundleTables, localTables: localTables)

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
                    let mainCols = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info(?, 'main')", arguments: [table])
                    let bundleCols = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info(?, 'bundle')", arguments: [table])
                    let safeCols = reseedCommonColumns(bundleColumns: bundleCols, mainColumns: mainCols)
                    guard !safeCols.isEmpty else { skipped += 1; continue }
                    let colList = safeCols.map { "\"\($0)\"" }.joined(separator: ",")
                    try db.execute(sql: "INSERT INTO main.\"\(table)\" (\(colList)) SELECT \(colList) FROM bundle.\"\(table)\"")
                    ok += 1
                }
                try db.execute(sql: "UPDATE main.meta SET value = ? WHERE key = 'data_version'", arguments: [String(newVersion)])
                // 「最後に取り込んだ同梱データ」を指紋で記録する。次回の判定はこれと突き合わせる。
                // meta は台帳に無いので一括コピーの対象外。ここで自分で書く。
                if let newContentHash {
                    try db.execute(sql: """
                        INSERT INTO main.meta (key, value) VALUES ('content_hash', ?)
                        ON CONFLICT(key) DO UPDATE SET value = excluded.value
                        """, arguments: [newContentHash])
                }
                return .commit
            }
        }
        return (ok, skipped)
    }

    /// Bundle 由来の master.sqlite には grdb_migrations が無いため、
    /// スキーマ実体（カラム・テーブル）を直接検査して「適用済み」識別子を pre-populate する。
    /// インデックス存在だけでは「カラムが追加されたがインデックスがない」ケースでALTER重複が起きるため、
    /// 各マイグレーションの特徴的なスキーマ変更を直接確認する。
    ///
    /// ⚠️ **この関数は「誰も触っていない実物の形」を見なければならない。** 判定材料は列と表の
    /// 有無だけなので、この前に何かがスキーマを変えていると印がそのまま嘘になる。嘘の印は
    /// 「列を足しつつデータも入れる」移行を丸ごと捨てる (列だけ他所で足され、データが永久に入らない)。
    /// だから `applyCoreMasterSchema` はこの後、GRDB の移行のさらに後で呼ぶ。
    private static func seedMigrationHistoryIfNeeded(_ dbQueue: any DatabaseWriter) throws {
        try dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")

            /// 列の有無に合わせて「適用済み」の印を**付けもし剥がしもする**。
            ///
            /// 剥がす側を持つのは、印と実物がずれた DB を自分で治すため。実際に一度ずれた:
            /// コア適用を移行より前に置いた版では、コアが足した `show_cast.cast_role` を根拠に
            /// v21 の印が付き、その後 v19_drop_cast が show_cast を作り直して列ごと消した。
            /// 印だけ残るので v21 は二度と走らず、列も主演データも戻らなかった。剥がせば移行が
            /// もう一度走り、列とセットのデータ投入までやり直される。
            ///
            /// 使ってよいのは「その列を足すのが当の移行自身」かつ「何度走らせても同じ結果になる」
            /// 移行だけ。v19 のように**列や表が無いこと**を根拠に印を付けるものに使ってはいけない
            /// (剥がすと再実行で「no such table」に当たって起動不能になる)。
            ///
            /// `columns` が空 = その表自体が無い。根拠が取れないので何もしない (同じ理由)。
            func alignMark(_ identifier: String, column: String, in columns: [String?]) throws {
                guard !columns.isEmpty else { return }
                if columns.contains(column) {
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES (?)",
                        arguments: [identifier]
                    )
                } else {
                    try db.execute(
                        sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                        arguments: [identifier]
                    )
                }
            }

            // v1: brands テーブルが存在すれば基本スキーマ作成済み
            let hasBrands = try Row.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='brands'") != nil
            guard hasBrands else { return }
            try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v1_create_tables')")

            // v2: songs テーブルの composer カラムで判定（インデックスではなくカラム存在）
            let songsColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(songs)").map { $0["name"] as String? }
            if songsColumns.contains("composer") {
                try db.execute(sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES ('v2_add_indexes')")
            }

            // v3: song_videos テーブルの存在で判定。
            // v3 は song_calls / song_videos を対で作るが、song_calls は v29 で落とすので、
            // 落とした後の起動でも揺れない残る側の song_videos を根拠にする。
            let hasSongVideos = try Row.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='song_videos'") != nil
            if hasSongVideos {
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

            // v7: events.kind カラム存在で判定。
            // 列に加えて 463 件の分類 UPDATE を持つので、印がずれると分類が丸ごと入らない。
            try alignMark("v7_event_kind", column: "kind", in: eventsColumns)

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
            // 列に加えて既知の主演 10 行を持つので、印がずれると主演/ゲスト表示が消える。
            let showCastColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(show_cast)").map { $0["name"] as String? }
            try alignMark("v21_show_cast_cast_role", column: "cast_role", in: showCastColumns)

            // v22: events.ticket_open_date カラム存在で判定 (Bundle DB が既に持つなら skip)。
            // 列に加えて既知の受付開始日を持つので、v7/v21 と同じく印を実物に合わせる。
            try alignMark("v22_event_ticket_open_date", column: "ticket_open_date", in: eventsColumns)
        }
    }

}
