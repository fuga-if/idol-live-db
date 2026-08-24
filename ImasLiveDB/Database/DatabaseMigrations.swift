import Foundation
import GRDB
import os

/// GRDB マイグレーション定義。
///
/// ## マイグレーションを追加する時の規約 (重要)
///
/// **v23 以降は「マイグレーション本体を冪等に書く」。**
/// 追加するカラム/テーブルが既にあるかを `PRAGMA table_info` や `ifNotExists:` で
/// 確かめてから実行する (v23_event_show_formats や v27_venues が手本)。
/// この方式なら、同梱 master.sqlite が既にそのスキーマを持っていても安全に空振りする。
///
/// **`AppDatabase.seedMigrationHistoryIfNeeded` への追記は不要。**
/// あちらは v1〜v22 で使っていた旧方式 (同梱 DB のスキーマを嗅ぎつけて
/// `grdb_migrations` に識別子を事前挿入し、マイグレーションを丸ごとスキップさせる) で、
/// 互換のため残してあるだけ。新規マイグレーションで旧方式を選ぶと、事前挿入の条件を
/// 書き忘れた時に**新規インストールが起動時にクラッシュする** (v19 で実際に起き、
/// Apple 審査 reject の原因になった)。
///
/// ## 共通の絶対ルール
///
/// - **破壊的マイグレーション (DB 削除・作り直し) は使わない。**
///   `user_marks` (担当/お気に入り/メモ/参加済み) はクラウドに無い端末ローカル唯一
///   データで、消すと復旧手段が無い。
/// - マスタテーブルは drop+recreate して CloudKit 再同期に委ねてよいが、
///   ローカル唯一データは必ず保全する。
/// - **スキーマを変えたら Android (Room `Migration`) にも対で書く。**
///   詳細は docs/ARCHITECTURE.md「データの所在・同期・マイグレーション」。
enum DatabaseMigrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator = migrator.disablingDeferredForeignKeyChecks()
        #endif

        migrator.registerMigration("v1_create_tables") { db in
            // brands
            try db.create(table: "brands") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("short_name", .text).notNull()
                t.column("color", .text)
                t.column("sort_order", .integer).notNull()
            }

            // idols
            try db.create(table: "idols") { t in
                t.primaryKey("id", .text)
                t.belongsTo("brand", inTable: "brands").notNull()
                t.column("name", .text).notNull()
                t.column("name_kana", .text)
                t.column("name_romaji", .text)
                t.column("color", .text)
                t.column("sort_order", .integer).notNull()
            }

            // cast
            try db.create(table: "cast") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("name_kana", .text)
                t.column("name_romaji", .text)
            }

            // idol_cast
            try db.create(table: "idol_cast") { t in
                t.column("idol_id", .text).notNull().references("idols", onDelete: .cascade)
                t.column("cast_id", .text).notNull().references("cast", onDelete: .cascade)
                t.column("is_current", .boolean).notNull().defaults(to: true)
                t.primaryKey(["idol_id", "cast_id"])
            }

            // songs
            try db.create(table: "songs") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("title_kana", .text)
                t.column("brand_id", .text).references("brands")
                t.column("song_type", .text).notNull()
                t.column("release_date", .text)
                t.column("duration_sec", .integer)
                t.column("composer", .text)
                t.column("lyricist", .text)
                t.column("arranger", .text)
                t.column("cd_series", .text)
                t.column("cd_title", .text)
                t.column("artwork_url", .text)
                t.column("preview_url", .text)
                t.column("apple_music_id", .text)
                t.column("apple_music_album_id", .text)
                t.column("isrc", .text)
                t.column("lyrics_url", .text)
            }

            // song_artists
            try db.create(table: "song_artists") { t in
                t.column("song_id", .text).notNull().references("songs", onDelete: .cascade)
                t.column("idol_id", .text).notNull().references("idols", onDelete: .cascade)
                t.column("role", .text).notNull().defaults(to: "original")
                t.primaryKey(["song_id", "idol_id", "role"])
            }

            // units
            try db.create(table: "units") { t in
                t.primaryKey("id", .text)
                t.belongsTo("brand", inTable: "brands").notNull()
                t.column("name", .text).notNull()
                t.column("is_permanent", .boolean).notNull().defaults(to: true)
            }

            // unit_members
            try db.create(table: "unit_members") { t in
                t.column("unit_id", .text).notNull().references("units", onDelete: .cascade)
                t.column("idol_id", .text).notNull().references("idols", onDelete: .cascade)
                t.primaryKey(["unit_id", "idol_id"])
            }

            // events
            try db.create(table: "events") { t in
                t.primaryKey("id", .text)
                t.column("brand_id", .text).references("brands")
                t.column("name", .text).notNull()
                t.column("event_type", .text).notNull()
            }

            // shows
            try db.create(table: "shows") { t in
                t.primaryKey("id", .text)
                t.belongsTo("event", inTable: "events").notNull()
                t.column("name", .text).notNull()
                t.column("date", .text).notNull()
                t.column("venue", .text)
                t.column("venue_city", .text)
                t.column("start_time", .text)
                t.column("sort_order", .integer).notNull()
            }

            // show_cast
            try db.create(table: "show_cast") { t in
                t.column("show_id", .text).notNull().references("shows", onDelete: .cascade)
                t.column("cast_id", .text).notNull().references("cast", onDelete: .cascade)
                t.primaryKey(["show_id", "cast_id"])
            }

            // setlist_items
            try db.create(table: "setlist_items") { t in
                t.primaryKey("id", .text)
                t.column("show_id", .text).notNull().references("shows", onDelete: .cascade)
                t.column("song_id", .text).notNull().references("songs", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("section", .text)
                t.column("notes", .text)
                t.uniqueKey(["show_id", "position"])
            }

            // setlist_performers
            try db.create(table: "setlist_performers") { t in
                t.column("setlist_item_id", .text).notNull().references("setlist_items", onDelete: .cascade)
                t.column("cast_id", .text).notNull().references("cast", onDelete: .cascade)
                t.primaryKey(["setlist_item_id", "cast_id"])
            }

            // meta
            try db.create(table: "meta") { t in
                t.primaryKey("key", .text)
                t.column("value", .text)
            }

            // Indexes
            try db.create(index: "idx_songs_brand", on: "songs", columns: ["brand_id"])
            try db.create(index: "idx_songs_title_kana", on: "songs", columns: ["title_kana"])
            try db.create(index: "idx_songs_type", on: "songs", columns: ["song_type"])
            try db.create(index: "idx_idols_brand", on: "idols", columns: ["brand_id"])
            try db.create(index: "idx_idols_name_kana", on: "idols", columns: ["name_kana"])
            try db.create(index: "idx_shows_event", on: "shows", columns: ["event_id"])
            try db.create(index: "idx_shows_date", on: "shows", columns: ["date"])
            try db.create(index: "idx_setlist_items_show", on: "setlist_items", columns: ["show_id"])
            try db.create(index: "idx_setlist_items_song", on: "setlist_items", columns: ["song_id"])
            try db.create(index: "idx_setlist_performers_item", on: "setlist_performers", columns: ["setlist_item_id"])
            try db.create(index: "idx_setlist_performers_cast", on: "setlist_performers", columns: ["cast_id"])
            try db.create(index: "idx_song_artists_song", on: "song_artists", columns: ["song_id"])
            try db.create(index: "idx_song_artists_idol", on: "song_artists", columns: ["idol_id"])
            try db.create(index: "idx_idol_cast_idol", on: "idol_cast", columns: ["idol_id"])
            try db.create(index: "idx_idol_cast_cast", on: "idol_cast", columns: ["cast_id"])
            try db.create(index: "idx_show_cast_show", on: "show_cast", columns: ["show_id"])
            try db.create(index: "idx_show_cast_cast", on: "show_cast", columns: ["cast_id"])
            try db.create(index: "idx_unit_members_unit", on: "unit_members", columns: ["unit_id"])
            try db.create(index: "idx_unit_members_idol", on: "unit_members", columns: ["idol_id"])

            // Initial meta values
            try Meta(key: "schema_version", value: "1").insert(db)
            try Meta(key: "data_version", value: "0").insert(db)
            try Meta(key: "baseline_version", value: "0").insert(db)
            try Meta(key: "last_sync_at", value: "").insert(db)
        }

        migrator.registerMigration("v2_add_indexes") { db in
            // 作曲者検索用
            try db.create(index: "idx_songs_composer", on: "songs", columns: ["composer"], ifNotExists: true)
            try db.create(index: "idx_songs_lyricist", on: "songs", columns: ["lyricist"], ifNotExists: true)
            try db.create(index: "idx_songs_arranger", on: "songs", columns: ["arranger"], ifNotExists: true)
            // イベントブランドフィルタ用
            try db.create(index: "idx_events_brand", on: "events", columns: ["brand_id"], ifNotExists: true)
            // fetchEventsWithFirstDate の MIN(date) JOIN 高速化
            try db.create(index: "idx_shows_event_date", on: "shows", columns: ["event_id", "date"], ifNotExists: true)
        }

        migrator.registerMigration("v3_song_calls_and_videos") { db in
            // コーレス投稿テーブル
            try db.create(table: "song_calls", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("song_id", .text).notNull()
                t.column("call_text", .text).notNull()
                t.column("source_url", .text)
                t.column("created_at", .text).notNull()
                t.column("author_display_name", .text)
            }
            try db.create(index: "idx_song_calls_song", on: "song_calls", columns: ["song_id"], ifNotExists: true)

            // 参考動画テーブル
            try db.create(table: "song_videos", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("song_id", .text).notNull()
                t.column("youtube_url", .text).notNull()
                t.column("video_title", .text)
                t.column("note", .text)
                t.column("created_at", .text).notNull()
                t.column("author_display_name", .text)
            }
            try db.create(index: "idx_song_videos_song", on: "song_videos", columns: ["song_id"], ifNotExists: true)
        }

        migrator.registerMigration("v4_user_marks") { db in
            // ユーザーマーク（フラグ・メモ）テーブル
            try db.create(table: "user_marks", ifNotExists: true) { t in
                t.column("entity_type", .text).notNull()
                t.column("entity_id", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("bool_value", .integer).notNull().defaults(to: 0)
                t.column("text_value", .text)
                t.column("updated_at", .text).notNull()
                t.primaryKey(["entity_type", "entity_id", "kind"])
            }
            try db.create(
                index: "idx_user_marks_entity",
                on: "user_marks",
                columns: ["entity_type", "entity_id"],
                ifNotExists: true
            )
        }

        migrator.registerMigration("v5_event_solo_flag") { db in
            try db.alter(table: "events") { t in
                t.add(column: "is_solo", .boolean).notNull().defaults(to: true)
            }
            try db.create(index: "idx_events_is_solo", on: "events", columns: ["is_solo"], ifNotExists: true)
        }

        migrator.registerMigration("v6_sync_bundle_schema") { db in
            // idol_brands junction table（Bundle DBに存在するがv1に未定義）
            let hasIdolBrands = try Row.fetchOne(
                db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='idol_brands'"
            ) != nil
            if !hasIdolBrands {
                try db.execute(sql: """
                    CREATE TABLE idol_brands (
                        idol_id TEXT NOT NULL,
                        brand_id TEXT NOT NULL,
                        is_primary INTEGER NOT NULL DEFAULT 0,
                        PRIMARY KEY (idol_id, brand_id)
                    )
                    """)
                try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_idol_brands_brand ON idol_brands(brand_id)")
            }

            // events.is_streaming
            let eventsColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(events)").map { $0["name"] as String? }
            if !eventsColumns.contains("is_streaming") {
                try db.execute(sql: "ALTER TABLE events ADD COLUMN is_streaming INTEGER NOT NULL DEFAULT 0")
            }

            // songs: parent_song_id, singer_label, unit_name, unit_id, series_group
            let songsColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(songs)").map { $0["name"] as String? }
            if !songsColumns.contains("parent_song_id") {
                try db.execute(sql: "ALTER TABLE songs ADD COLUMN parent_song_id TEXT")
            }
            if !songsColumns.contains("singer_label") {
                try db.execute(sql: "ALTER TABLE songs ADD COLUMN singer_label TEXT")
            }
            if !songsColumns.contains("unit_name") {
                try db.execute(sql: "ALTER TABLE songs ADD COLUMN unit_name TEXT")
            }
            if !songsColumns.contains("unit_id") {
                try db.execute(sql: "ALTER TABLE songs ADD COLUMN unit_id TEXT")
            }
            if !songsColumns.contains("series_group") {
                try db.execute(sql: "ALTER TABLE songs ADD COLUMN series_group TEXT")
            }

            // shows.performer_type
            let showsColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(shows)").map { $0["name"] as String? }
            if !showsColumns.contains("performer_type") {
                try db.execute(sql: "ALTER TABLE shows ADD COLUMN performer_type TEXT")
            }

            // setlist_items.unit_name
            let setlistColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(setlist_items)").map { $0["name"] as String? }
            if !setlistColumns.contains("unit_name") {
                try db.execute(sql: "ALTER TABLE setlist_items ADD COLUMN unit_name TEXT")
            }

            // units.name_alt
            let unitsColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(units)").map { $0["name"] as String? }
            if !unitsColumns.contains("name_alt") {
                try db.execute(sql: "ALTER TABLE units ADD COLUMN name_alt TEXT")
            }
        }

        migrator.registerMigration("v7_event_kind") { db in
            // events.kind: 5カテゴリ分類 (live / festival / release_event / radio / stream)
            // is_solo / is_streaming は互換のため残置。新コードは kind のみ参照。
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(events)").map { $0["name"] as String? }
            if !columns.contains("kind") {
                try db.execute(sql: "ALTER TABLE events ADD COLUMN kind TEXT NOT NULL DEFAULT 'live'")
            }
            try db.create(index: "idx_events_kind", on: "events", columns: ["kind"], ifNotExists: true)

            // 既存ユーザー (Documents 配下に旧 master.sqlite) 向けに、
            // Bundle 同梱の v7_event_kind_data.sql から AI 分類済み UPDATE 文を流し込む。
            // (live 以外の 463件のみ含む。それ以外は default 'live'。)
            if let url = Bundle.main.url(forResource: "v7_event_kind_data", withExtension: "sql"),
               let sql = try? String(contentsOf: url, encoding: .utf8) {
                try db.execute(sql: sql)
            }
        }

        migrator.registerMigration("v8_idol_name_parts_brand_icon") { db in
            // idols.family_name / given_name / nickname と brands.icon_url を追加。
            // 既存 DB 向け ALTER のみ。値は CloudKit pull で反映される想定。
            let idolCols = try Row.fetchAll(db, sql: "PRAGMA table_info(idols)").map { $0["name"] as String? }
            if !idolCols.contains("family_name") {
                try db.execute(sql: "ALTER TABLE idols ADD COLUMN family_name TEXT")
            }
            if !idolCols.contains("given_name") {
                try db.execute(sql: "ALTER TABLE idols ADD COLUMN given_name TEXT")
            }
            if !idolCols.contains("nickname") {
                try db.execute(sql: "ALTER TABLE idols ADD COLUMN nickname TEXT")
            }

            let brandCols = try Row.fetchAll(db, sql: "PRAGMA table_info(brands)").map { $0["name"] as String? }
            if !brandCols.contains("icon_url") {
                try db.execute(sql: "ALTER TABLE brands ADD COLUMN icon_url TEXT")
            }
        }

        migrator.registerMigration("v9_song_type_group_to_unit") { db in
            // songs.song_type = 'group' は廃止し 'unit' に統合。
            // 既存 Documents DB の旧 'group' 値を一括で 'unit' に書き換える。
            try db.execute(sql: "UPDATE songs SET song_type = 'unit' WHERE song_type = 'group'")
        }

        migrator.registerMigration("v11_reseed_song_type_from_bundle") { db in
            // v9 で旧 'group' を一律 'unit' に畳んでしまい、本来 solo/all/unknown
            // であるべき曲まで unit 表示になる症状が出た。CloudKit pull が差分を
            // 拾わないケースの最終保険として、Bundle 同梱 master.sqlite の
            // songs.song_type を ID 一致で UPDATE で流し込む。
            // (GRDB migration は transaction 内なので ATTACH DATABASE は不可。
            //  Bundle 直開きは WAL/権限まわりで失敗するので tmp に丸ごとコピーしてから開く。)
            guard let bundleURL = Bundle.main.url(forResource: "master", withExtension: "sqlite") else { return }
            let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("v11_bundle_master.sqlite")
            let fm = FileManager.default
            if fm.fileExists(atPath: tmpURL.path) {
                try? fm.removeItem(at: tmpURL)
            }
            try fm.copyItem(at: bundleURL, to: tmpURL)
            defer { try? fm.removeItem(at: tmpURL) }

            let bundleQueue = try DatabaseQueue(path: tmpURL.path)
            let rows: [(String, String)] = try bundleQueue.read { bdb in
                try Row.fetchAll(bdb, sql: "SELECT id, song_type FROM songs").map {
                    ($0["id"] as String, $0["song_type"] as String)
                }
            }
            for (id, type) in rows {
                try db.execute(
                    sql: "UPDATE songs SET song_type = ? WHERE id = ? AND song_type != ?",
                    arguments: [type, id, type]
                )
            }
        }

        migrator.registerMigration("v12_idol_debut_date") { db in
            let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(idols)").map { $0["name"] as String? }
            if !cols.contains("debut_date") {
                try db.execute(sql: "ALTER TABLE idols ADD COLUMN debut_date TEXT")
            }
        }

        migrator.registerMigration("v13_idol_attribute") { db in
            let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(idols)").map { $0["name"] as String? }
            if !cols.contains("attribute") {
                try db.execute(sql: "ALTER TABLE idols ADD COLUMN attribute TEXT")
            }
            try db.create(index: "idx_idols_attribute", on: "idols", columns: ["attribute"], ifNotExists: true)
        }

        // v14: 外部ゲスト演者フラグ。アイラブ歌合戦のラブライブ側のように
        // セトリ表示には出すが、アイドル一覧・検索・統計からは除外したいキャラ用。
        migrator.registerMigration("v14_idol_is_external") { db in
            let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(idols)").map { $0["name"] as String? }
            if !cols.contains("is_external") {
                try db.execute(sql: "ALTER TABLE idols ADD COLUMN is_external INTEGER NOT NULL DEFAULT 0")
            }
            try db.create(index: "idx_idols_is_external", on: "idols", columns: ["is_external"], ifNotExists: true)
        }

        // v15: イベントのチケット情報。コミュニティ投稿で埋めていくため
        // 全カラム optional で追加。
        migrator.registerMigration("v15_event_ticket_info") { db in
            let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(events)").map { $0["name"] as String? }
            if !cols.contains("ticket_deadline") {
                try db.execute(sql: "ALTER TABLE events ADD COLUMN ticket_deadline TEXT")
            }
            if !cols.contains("ticket_lottery_date") {
                try db.execute(sql: "ALTER TABLE events ADD COLUMN ticket_lottery_date TEXT")
            }
            if !cols.contains("ticket_url") {
                try db.execute(sql: "ALTER TABLE events ADD COLUMN ticket_url TEXT")
            }
        }

        // v17: idols.aliases カラム追加 (ステージ名・通称のカンマ区切り)。
        migrator.registerMigration("v17_idol_aliases") { db in
            let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(idols)").map { $0["name"] as String? }
            if !cols.contains("aliases") {
                try db.execute(sql: "ALTER TABLE idols ADD COLUMN aliases TEXT")
            }
        }

        // v18: events.joint_brand_ids カラム追加 (合同ライブの追加ブランド CSV)。
        // 通常イベントは NULL。 ハッチポッチ等 765AS×ML 合同なら "ml" などを指定。
        // 欠席判定の母集団 = primary brand のアイドル + joint_brand_ids 各ブランドのアイドル。
        migrator.registerMigration("v18_event_joint_brands") { db in
            let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(events)").map { $0["name"] as String? }
            if !cols.contains("joint_brand_ids") {
                try db.execute(sql: "ALTER TABLE events ADD COLUMN joint_brand_ids TEXT")
            }
        }

        // v16: SHINY COLORS ∞th LIVE iと夢 を ASCII id にリネームしたため、
        // 旧 id (recordName 非ASCII) で local DB に残っている orphan 行を物理削除する。
        // CloudKit 側は forceDelete 済み・Bundle DB は新 id 済みだが、既存ユーザーの
        // Documents DB には旧 row が残るためここで掃除。
        migrator.registerMigration("v16_remove_legacy_infinity_event") { db in
            let legacyEventId = "ev_the_idolm@ster_shiny_colors_∞th_live_iと夢"
            let legacyShowIds = [
                "sh_the_idolm@ster_shiny_colors_∞th_live_iと夢_1",
                "sh_the_idolm@ster_shiny_colors_∞th_live_iと夢_2",
            ]
            try db.execute(
                sql: "DELETE FROM setlist_performers WHERE setlist_item_id IN (SELECT id FROM setlist_items WHERE show_id IN (?, ?))",
                arguments: StatementArguments(legacyShowIds)
            )
            try db.execute(
                sql: "DELETE FROM setlist_items WHERE show_id IN (?, ?)",
                arguments: StatementArguments(legacyShowIds)
            )
            try db.execute(
                sql: "DELETE FROM show_cast WHERE show_id IN (?, ?)",
                arguments: StatementArguments(legacyShowIds)
            )
            try db.execute(
                sql: "DELETE FROM shows WHERE id IN (?, ?)",
                arguments: StatementArguments(legacyShowIds)
            )
            try db.execute(
                sql: "DELETE FROM events WHERE id = ?",
                arguments: [legacyEventId]
            )
        }

        // v19: Cast テーブル廃止 + idol.voiceActors 追加。
        // - idols に voice_actors カラムを追加し、 idol_cast から CV 名を集約する
        // - setlist_performers / show_cast の cast_id → idol_id に置換 (旧 cast 紐付け無いものは drop)
        // - 双海亜美/真美 のように 1 cast → 複数 idol の場合は行を複製
        // - cast / idol_cast テーブルを DROP
        // Bundle DB は seed 時に reseed されるのでこの migration は既存ユーザの Documents DB のみ対象。
        migrator.registerMigration("v19_drop_cast") { db in
            // ⚠️ ここで「テーブルがある」前提を置かないこと。
            // Bundle DB は cast/idol_cast を持たないので、`AppDatabase` 側の pre-populate が
            // この migration を「適用済み」に印を付けて飛ばしている。その判定が一度壊れて
            // (idols.voice_actors 列の有無を見ていたが、声優履歴テーブルへの移行でその列を
            // 落としたため成立しなくなった)、新規インストールが全部
            // 「no such table: idol_cast」で起動クラッシュした。
            // 起動クラッシュは審査 reject に直結するので、印の付け忘れだけを頼りにしない。
            let hasLegacyCast = try db.tableExists("idol_cast") && db.tableExists("cast")
            guard hasLegacyCast else { return }

            if try !db.columns(in: "idols").contains(where: { $0.name == "voice_actors" }) {
                try db.execute(sql: "ALTER TABLE idols ADD COLUMN voice_actors TEXT")
            }

            // idol_cast / cast から voice_actors を集計 (現役を先頭、過去はその後)
            let rows = try Row.fetchAll(db, sql: """
                SELECT i.id AS idol_id, c.name AS cast_name, ic.is_current
                FROM idols i
                JOIN idol_cast ic ON ic.idol_id = i.id
                JOIN cast c ON c.id = ic.cast_id
            """)
            var byIdol: [String: (current: [String], past: [String])] = [:]
            for row in rows {
                let iid: String = row["idol_id"]
                let cname: String = row["cast_name"]
                let isCurrent: Int = row["is_current"] ?? 0
                var entry = byIdol[iid] ?? ([], [])
                if isCurrent == 1 { entry.current.append(cname) } else { entry.past.append(cname) }
                byIdol[iid] = entry
            }
            for (iid, names) in byIdol {
                var seen = Set<String>()
                var ordered: [String] = []
                for n in names.current + names.past where !seen.contains(n) {
                    seen.insert(n); ordered.append(n)
                }
                try db.execute(
                    sql: "UPDATE idols SET voice_actors = ? WHERE id = ?",
                    arguments: [ordered.joined(separator: ","), iid]
                )
            }

            // cast_id → [idol_id] マッピング (現役 idol_cast のみ採用)
            var castToIdols: [String: [String]] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT cast_id, idol_id FROM idol_cast WHERE is_current = 1
            """) {
                let cid: String = row["cast_id"]
                let iid: String = row["idol_id"]
                castToIdols[cid, default: []].append(iid)
            }

            // setlist_performers を再構築 (cast_id → idol_id)
            try db.execute(sql: """
                CREATE TABLE setlist_performers_new (
                    setlist_item_id TEXT NOT NULL,
                    idol_id TEXT NOT NULL,
                    PRIMARY KEY (setlist_item_id, idol_id)
                )
            """)
            for row in try Row.fetchAll(db, sql: "SELECT setlist_item_id, cast_id FROM setlist_performers") {
                let itemId: String = row["setlist_item_id"]
                let cid: String = row["cast_id"]
                for iid in castToIdols[cid] ?? [] {
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO setlist_performers_new (setlist_item_id, idol_id) VALUES (?, ?)",
                        arguments: [itemId, iid]
                    )
                }
            }
            try db.execute(sql: "DROP TABLE setlist_performers")
            try db.execute(sql: "ALTER TABLE setlist_performers_new RENAME TO setlist_performers")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_setlist_performers_idol ON setlist_performers(idol_id)")

            // show_cast を再構築
            try db.execute(sql: """
                CREATE TABLE show_cast_new (
                    show_id TEXT NOT NULL,
                    idol_id TEXT NOT NULL,
                    PRIMARY KEY (show_id, idol_id)
                )
            """)
            for row in try Row.fetchAll(db, sql: "SELECT show_id, cast_id FROM show_cast") {
                let showId: String = row["show_id"]
                let cid: String = row["cast_id"]
                for iid in castToIdols[cid] ?? [] {
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO show_cast_new (show_id, idol_id) VALUES (?, ?)",
                        arguments: [showId, iid]
                    )
                }
            }
            try db.execute(sql: "DROP TABLE show_cast")
            try db.execute(sql: "ALTER TABLE show_cast_new RENAME TO show_cast")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_show_cast_idol ON show_cast(idol_id)")

            // cast / idol_cast を DROP
            try db.execute(sql: "DROP TABLE IF EXISTS idol_cast")
            try db.execute(sql: "DROP TABLE IF EXISTS cast")
        }

        // v20: 索引網羅性の回復 + クエリ用索引の追加。
        // seedMigrationHistoryIfNeeded で pre-mark しない (= Bundle インストールでも必ず実行) ことで、
        // v1/v2 で宣言されたが Bundle DB に焼かれず欠落していた索引も含めて確実に張り直す。
        // テーブル・列の存在を確認してから張るため、スキーマドリフトがあっても起動をクラッシュさせない。
        migrator.registerMigration("v20_ensure_indexes") { db in
            func ensureIndex(_ name: String, on table: String, columns: [String]) {
                do {
                    let tableExists = try Row.fetchOne(
                        db, sql: "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", arguments: [table]
                    ) != nil
                    guard tableExists else { return }
                    let cols = Set(try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info(?)", arguments: [table]))
                    guard columns.allSatisfy({ cols.contains($0) }) else { return }
                    try db.create(index: name, on: table, columns: columns, ifNotExists: true)
                } catch {
                    // 索引は最適化目的のみ。失敗しても「索引なし=低速だが正しい」にフォールバックし、
                    // 起動は継続させる (migration 全体を throw させない)。
                    Logger.database.error(
                        "[v20] ensureIndex \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }

            // --- 既存宣言ぶんの取りこぼし回復 (Bundle install で v1/v2 が pre-mark され未作成のもの) ---
            ensureIndex("idx_songs_brand", on: "songs", columns: ["brand_id"])
            ensureIndex("idx_songs_title_kana", on: "songs", columns: ["title_kana"])
            ensureIndex("idx_songs_type", on: "songs", columns: ["song_type"])
            ensureIndex("idx_idols_brand", on: "idols", columns: ["brand_id"])
            ensureIndex("idx_idols_name_kana", on: "idols", columns: ["name_kana"])
            ensureIndex("idx_shows_event", on: "shows", columns: ["event_id"])
            ensureIndex("idx_shows_date", on: "shows", columns: ["date"])
            ensureIndex("idx_shows_event_date", on: "shows", columns: ["event_id", "date"])
            ensureIndex("idx_setlist_items_show", on: "setlist_items", columns: ["show_id"])
            ensureIndex("idx_setlist_items_song", on: "setlist_items", columns: ["song_id"])
            ensureIndex("idx_setlist_performers_item", on: "setlist_performers", columns: ["setlist_item_id"])
            ensureIndex("idx_setlist_performers_idol", on: "setlist_performers", columns: ["idol_id"])
            ensureIndex("idx_song_artists_song", on: "song_artists", columns: ["song_id"])
            ensureIndex("idx_show_cast_idol", on: "show_cast", columns: ["idol_id"])
            ensureIndex("idx_unit_members_unit", on: "unit_members", columns: ["unit_id"])
            ensureIndex("idx_unit_members_idol", on: "unit_members", columns: ["idol_id"])
            ensureIndex("idx_events_brand", on: "events", columns: ["brand_id"])

            // --- 追加索引 (監査で特定したクエリパス) ---
            // idol→曲の逆引き / role='original' 絞り込み (PK 先頭が song_id のため idol_id 単独/先頭が効かない)
            ensureIndex("idx_song_artists_idol_role", on: "song_artists", columns: ["idol_id", "role"])
            // ブランド別アイドル一覧の covering 化 (既存 idx_idol_brands_brand は単一列なので別名で複合を追加)
            ensureIndex("idx_idol_brands_brand_idol", on: "idol_brands", columns: ["brand_id", "idol_id"])
            // イベント種別 + ブランド絞り込み (既存 idx_events_kind は単一列なので別名で複合を追加)
            ensureIndex("idx_events_kind_brand", on: "events", columns: ["kind", "brand_id"])
            // 楽曲リリース年絞り込み
            ensureIndex("idx_songs_release_date", on: "songs", columns: ["release_date"])
            // 会場別公演一覧
            ensureIndex("idx_shows_venue", on: "shows", columns: ["venue"])
        }

        // v21: show_cast.cast_role (公演での役割 member/lead/guest) を追加。
        // 主演とゲストは排他なので真偽値ではなく enum 1 列で表す。
        // 既存ユーザの Documents DB に列を足し、 既知の主演データを cast_role='lead' にする。
        // Bundle DB は既に cast_role 列 + データを持つので seedMigrationHistoryIfNeeded で
        // pre-mark され、 新規インストール時はこの migration を skip する
        // (ALTER の重複や CloudKit pull 前の上書きを避ける)。
        migrator.registerMigration("v21_show_cast_cast_role") { db in
            let showCastColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(show_cast)")
                .map { $0["name"] as String? }
            if !showCastColumns.contains("cast_role") {
                try db.execute(sql: "ALTER TABLE show_cast ADD COLUMN cast_role TEXT NOT NULL DEFAULT 'member'")
            }

            // 既知の主演 (show_id, idol_id) ペア。 該当行が無ければ INSERT、 あれば cast_role='lead' に更新。
            let leads: [(show: String, idol: String)] = [
                ("sh_L_ml_11th_day1", "ml_伴田路子"),
                ("sh_L_ml_11th_day2", "ml_七尾百合子"),
                ("sh_L1173", "ml_北上麗花"),
                ("sh_L1174", "ml_桜守歌織"),
                ("sh_the_idolm@ster_million_live_13thlive_1", "ml_高山紗代子"),
                ("sh_the_idolm@ster_million_live_13thlive_2", "ml_二階堂千鶴"),
                ("sh_the_idolm@ster_million_live_14thlive_1", "ml_徳川まつり"),
                ("sh_the_idolm@ster_million_live_14thlive_1", "ml_エミリースチュアート"),
                ("sh_the_idolm@ster_million_live_14thlive_2", "ml_馬場このみ"),
                ("sh_the_idolm@ster_million_live_14thlive_2", "ml_百瀬莉緒"),
            ]
            for lead in leads {
                try db.execute(
                    sql: """
                        INSERT INTO show_cast (show_id, idol_id, cast_role) VALUES (?, ?, 'lead')
                        ON CONFLICT(show_id, idol_id) DO UPDATE SET cast_role = 'lead'
                        """,
                    arguments: [lead.show, lead.idol]
                )
            }
        }

        // v22: チケット受付開始日。締切とセットで「受付期間」をカレンダーに帯表示する。
        migrator.registerMigration("v22_event_ticket_open_date") { db in
            let eventsColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(events)")
                .map { $0["name"] as String? }
            if !eventsColumns.contains("ticket_open_date") {
                try db.execute(sql: "ALTER TABLE events ADD COLUMN ticket_open_date TEXT")
            }
            // 既知の受付開始日 (CloudKit 同期前でも帯が出るよう migration でも入れておく)。
            let opens: [(id: String, date: String)] = [
                ("ev_the_idolm@ster_million_live_14thlive", "2026-06-13"),
            ]
            for o in opens {
                try db.execute(
                    sql: """
                        UPDATE events SET ticket_open_date = ?
                        WHERE id = ? AND (ticket_open_date IS NULL OR ticket_open_date = '')
                        """,
                    arguments: [o.date, o.id]
                )
            }
        }

        // v23: 開催形態フラグ (配信有無/ライブビューイング有無)。
        // 参加形態UIで「そのライブに実在した形態だけ」選択肢に出すためのデータ駆動の根拠。
        // show単位 + eventフォールバック。nullable (null=未設定→上位/現地にフォールバック)。
        migrator.registerMigration("v23_event_show_formats") { db in
            let eventCols = try Row.fetchAll(db, sql: "PRAGMA table_info(events)")
                .map { $0["name"] as String? }
            if !eventCols.contains("has_streaming") {
                try db.execute(sql: "ALTER TABLE events ADD COLUMN has_streaming INTEGER")
                // 既存の is_streaming (廃止予定だが配信有無の最良データ) から初期移行。
                try db.execute(sql: "UPDATE events SET has_streaming = is_streaming")
            }
            if !eventCols.contains("has_live_viewing") {
                try db.execute(sql: "ALTER TABLE events ADD COLUMN has_live_viewing INTEGER")
            }

            let showCols = try Row.fetchAll(db, sql: "PRAGMA table_info(shows)")
                .map { $0["name"] as String? }
            if !showCols.contains("has_streaming") {
                try db.execute(sql: "ALTER TABLE shows ADD COLUMN has_streaming INTEGER")
            }
            if !showCols.contains("has_live_viewing") {
                try db.execute(sql: "ALTER TABLE shows ADD COLUMN has_live_viewing INTEGER")
            }
        }

        // v24: イベント映像円盤 (ライブBD/DVD)。所有チェックの母集団。
        // レコードがあるライブだけ所有UIを出す (データ駆動)。所有フラグ自体は user_marks(kind=owned)。
        migrator.registerMigration("v24_event_releases") { db in
            try db.create(table: "event_releases", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                // モデルの CodingKeys (event_id/show_id) と一致させるため列名を明示する。
                t.column("event_id", .text).notNull().indexed().references("events")
                // 公演単位の円盤なら show_id を持つ。イベント全体BOXなら null。
                t.column("show_id", .text).references("shows")
                t.column("product_type", .text).notNull()   // blu_ray / dvd / dvd_box
                t.column("title", .text).notNull()
                t.column("catalog_number", .text)            // 品番 (例: EYXA-13123)
                t.column("release_date", .text)              // YYYY-MM-DD
                t.column("jacket_url", .text)
                t.column("purchase_url", .text)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
            }
        }

        // v25: 事務員 (staff) + ブランド記念日 (anniversaries)。カレンダー機能の拡充。
        // staff: 音無小鳥・高木社長等の「アイドル本人ではない関係者」の誕生日を持つ。
        // anniversaries: ブランド/アプリの service_start/app_start/anime_start/movie_release/cd_debut。
        // 中身は bundle master.sqlite から reseed で投入される (Documents DB 側はスキーマだけ作る)。
        migrator.registerMigration("v25_staff_and_anniversaries") { db in
            try db.create(table: "staff", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("brand_id", .text).notNull().references("brands")
                t.column("name", .text).notNull()
                t.column("name_kana", .text)
                t.column("name_romaji", .text)
                t.column("role", .text)
                t.column("birthday", .text)  // '--MM-DD'
                t.column("sort_order", .integer).notNull().defaults(to: 0)
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_staff_brand ON staff(brand_id)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_staff_birthday ON staff(birthday)")

            try db.create(table: "anniversaries", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("brand_id", .text).notNull().references("brands")
                t.column("label", .text).notNull()
                t.column("date", .text).notNull()  // 'YYYY-MM-DD' (年あり、N周年計算用)
                t.column("kind", .text).notNull()  // service_start / app_start / anime_start / movie_release / cd_debut
                t.column("sort_order", .integer).notNull().defaults(to: 0)
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_anniversaries_brand ON anniversaries(brand_id)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_anniversaries_date ON anniversaries(date)")
        }

        // v26: 個人用タグ (personal_tags)。コミュニティタグ (共有マスタ・サーバー同期・投票制) とは別に、
        // ユーザーが自由入力で付ける私用の分類 (例:「聞いた」) を完全ローカル専用で保存する。
        // サーバー(Worker)には一切送信しない。同一 (entity_type, entity_id, tag_name) は複合PKで重複排除。
        migrator.registerMigration("v26_personal_tags") { db in
            try db.create(table: "personal_tags", ifNotExists: true) { t in
                t.column("entity_type", .text).notNull()
                t.column("entity_id", .text).notNull()
                t.column("tag_name", .text).notNull()
                t.column("created_at", .text).notNull()
                t.primaryKey(["entity_type", "entity_id", "tag_name"])
            }
            try db.create(
                index: "idx_personal_tags_entity",
                on: "personal_tags",
                columns: ["entity_type", "entity_id"],
                ifNotExists: true
            )
        }

        // 会場を ID で管理する。
        //
        // それまで `shows.venue` は自由文字列で、同じ会場が最大 14 通りに割れていた
        // (幕張メッセ = `千葉・幕張メッセイベントホール` / `幕張イベントホール` / `幕張メッセ` …)。
        // 名前が変わる会場もある (武蔵野の森総合スポーツプラザ → 京王アリーナTOKYO) ため、
        // 名前ではなく ID で同一性を持たせて履歴が分断されないようにする。
        migrator.registerMigration("v27_venues") { db in
            // 施設。ホールは venue_halls 側に分けるので、ここは「建物」の単位。
            try db.create(table: "venues", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                /// 現行名。過去公演の表示には venue_names の当時名を使う。
                t.column("name", .text).notNull()
                t.column("name_kana", .text)
                t.column("prefecture", .text)
                t.column("city", .text)
                /// 検索用の別名 (改行区切り)。旧名・通称を入れる。
                t.column("aliases", .text)
                /// 施設の代表キャパ (最大構成)。構成で変わる場合は venue_halls が優先。
                t.column("capacity", .integer)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
            }

            // 改名履歴。表示は「公演日時点の名前」なので有効期間で引く。
            // valid_from が NULL = 開業時から / valid_to が NULL = 現在も。
            try db.create(table: "venue_names", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("venue_id", .text).notNull().references("venues", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("valid_from", .text)
                t.column("valid_to", .text)
            }
            try db.create(index: "idx_venue_names_venue", on: "venue_names",
                          columns: ["venue_id"], ifNotExists: true)

            // ホール/構成。キャパは構成で変わる
            // (さいたまスーパーアリーナ: スタジアム37,000 / アリーナ22,500) ため施設と分ける。
            try db.create(table: "venue_halls", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("venue_id", .text).notNull().references("venues", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("capacity", .integer)
            }
            try db.create(index: "idx_venue_halls_venue", on: "venue_halls",
                          columns: ["venue_id"], ifNotExists: true)

            // shows 側。venue (生文字列) は当時名のフォールバックとして残す
            // (venue_id が未解決の公演でも表示が壊れないようにするため)。
            //
            // バンドルの master.sqlite は「この migration 適用後の DB」を dump して作るので、
            // 新規インストールではカラムが既に存在する。無条件 ALTER だと duplicate column で
            // 起動時に落ちるため、他の migration と同じくカラム存在チェックで挟む。
            let showCols = try Row.fetchAll(db, sql: "PRAGMA table_info(shows)").map { $0["name"] as String? }
            if !showCols.contains("venue_id") {
                try db.execute(sql: "ALTER TABLE shows ADD COLUMN venue_id TEXT")
            }
            // ホール名。venue_halls.name と突き合わせてキャパを引く。
            if !showCols.contains("hall") {
                try db.execute(sql: "ALTER TABLE shows ADD COLUMN hall TEXT")
            }
            // 配信プラットフォーム (ASOBI STAGE 等)。配信は会場ではないのでここへ逃がす。
            if !showCols.contains("stream_platform") {
                try db.execute(sql: "ALTER TABLE shows ADD COLUMN stream_platform TEXT")
            }
            try db.create(index: "idx_shows_venue_id", on: "shows",
                          columns: ["venue_id"], ifNotExists: true)
        }

        // v28: 声優を期間つきの履歴テーブルへ移す。
        //
        // 旧 idols.voice_actors は "現役,過去CV" のカンマ区切りで期間を持てず、交代すると
        // 前任者が消えていた (九十九一希の初代 徳武竜也が実際に消えていた)。
        // さらに「同時に複数」「改名」「表記ゆれ」「舞台版キャスト」が同居していた。
        //
        // ⚠️ 旧列はここでは**消さない**。消すと、まだ新しい bundle を受け取っていない
        //    端末で backfill の材料が無くなる。列は空のまま放置され、次の reseed で
        //    テーブルごと入れ替わる。
        migrator.registerMigration("v28_idol_voice_actors") { db in
            try db.create(table: "idol_voice_actors", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("idol_id", .text).notNull().references("idols", onDelete: .cascade)
                t.column("name", .text).notNull()
                /// 担当開始日。初代はキャラの実装日 (idols.debut_date)。
                t.column("valid_from", .text)
                /// 担当終了日。NULL なら現任。
                t.column("valid_to", .text)
            }
            try db.create(index: "idx_idol_voice_actors_idol", on: "idol_voice_actors",
                          columns: ["idol_id"], ifNotExists: true)

            // 既存端末を空にしないための繋ぎ。旧列の先頭 (= 現役) だけを現任として写す。
            // 正確な履歴は bundle の reseed で上書きされる。
            let idolCols = try db.columns(in: "idols").map(\.name)
            guard idolCols.contains("voice_actors") else { return }
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, voice_actors, debut_date FROM idols
                 WHERE IFNULL(voice_actors,'') != ''
                """)
            for row in rows {
                let idolId: String = row["id"]
                let raw: String = row["voice_actors"]
                guard let first = raw.split(separator: ",").first else { continue }
                let name = first.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                try db.execute(sql: """
                    INSERT OR IGNORE INTO idol_voice_actors (id, idol_id, name, valid_from, valid_to)
                    VALUES (?, ?, ?, ?, NULL)
                    """, arguments: ["\(idolId)__\(name)", idolId, name, row["debut_date"] as String?])
            }
        }

        return migrator
    }
}
