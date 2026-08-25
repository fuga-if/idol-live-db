//  AppDatabase の Idol Queries / Idol Song Queries を切り出したもの。
//  分割の意図と分割線の引き方は docs/ARCHITECTURE.md を参照。
//  ここにあるのは移動してきたクエリだけで、ロジックは 1 行も変えていない。

import Foundation
import GRDB

extension AppDatabase {

    // MARK: - Idol Queries

    /// アイドル一覧 (外部ゲスト演者は除外)
    func fetchIdols(brandId: String? = nil) throws -> [Idol] {
        try dbQueue.read { db in try Self.fetchIdolsByBrandQuery(db, brandId: brandId) }
    }

    func fetchIdolsAsync(brandId: String? = nil) async throws -> [Idol] {
        try await dbQueue.read { db in try Self.fetchIdolsByBrandQuery(db, brandId: brandId) }
    }

    private static func fetchIdolsByBrandQuery(_ db: Database, brandId: String?) throws -> [Idol] {
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

    /// アイドル詳細のCV取得。現任 (`valid_to IS NULL`) を返す。
    ///
    /// 声優は `idol_voice_actors` に期間つきで持つ (旧 `idols.voice_actors` は廃止)。
    /// 交代しても前任者が残るので、過去の楽曲やライブが誰の声だったか辿れる。
    /// 交代が発表されて後任が未定の間は現任が居ないので nil になる。
    func fetchCurrentVoiceActor(idolId: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: """
                    SELECT name FROM idol_voice_actors
                     WHERE idol_id = ? AND valid_to IS NULL
                     ORDER BY IFNULL(valid_from, '') DESC
                     LIMIT 1
                    """,
                arguments: [idolId]
            )
        }
    }

    /// アイドルの歴代声優 (新しい順)。交代の履歴を出す画面用。
    func fetchVoiceActorHistory(idolId: String) throws -> [IdolVoiceActor] {
        try dbQueue.read { db in
            try IdolVoiceActor.fetchAll(
                db,
                sql: """
                    SELECT * FROM idol_voice_actors
                     WHERE idol_id = ?
                     ORDER BY IFNULL(valid_from, '') DESC
                    """,
                arguments: [idolId]
            )
        }
    }

    /// アイドルの所属ユニット一覧
    func fetchIdolUnitsAsync(idolId: String) async throws -> [Unit] {
        try await dbQueue.read { db in try Self.fetchIdolUnitsQuery(db, idolId: idolId) }
    }

    private static func fetchIdolUnitsQuery(_ db: Database, idolId: String) throws -> [Unit] {
        let sql = """
            SELECT u.* FROM units u
            JOIN unit_members um ON u.id = um.unit_id
            WHERE um.idol_id = ?
            ORDER BY u.name
            """
        return try Unit.fetchAll(db, sql: sql, arguments: [idolId])
    }

    /// 編集フィード用: recordType + recordName から人間可読のタイトル(曲名/公演名/アイドル名 等)を引く。
    /// 解決できない recordType (コミュニティ投稿等) は nil。
    func fetchEditRecordTitleAsync(recordType: String, recordName: String) async throws -> String? {
        try await dbQueue.read { db in try Self.fetchEditRecordTitleQuery(db, recordType: recordType, recordName: recordName) }
    }

    private static func fetchEditRecordTitleQuery(_ db: Database, recordType: String, recordName: String) throws -> String? {
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

    /// 編集レコードが属する公演 ID を解決する (セトリ系編集 → 該当公演のセトリへ遷移するため)。
    /// Show/ShowSetlist は recordName 自体が公演 ID。SetlistItem/SetlistPerformer は親を辿る。
    func fetchEditRecordShowIdAsync(recordType: String, recordName: String) async throws -> String? {
        try await dbQueue.read { db in try Self.fetchEditRecordShowIdQuery(db, recordType: recordType, recordName: recordName) }
    }

    private static func fetchEditRecordShowIdQuery(_ db: Database, recordType: String, recordName: String) throws -> String? {
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

    /// 編集レコードが属する曲 ID を解決する (SongVideo/SongCall 編集 → 該当曲詳細へ遷移するため)。
    func fetchEditRecordSongIdAsync(recordType: String, recordName: String) async throws -> String? {
        try await dbQueue.read { db in try Self.fetchEditRecordSongIdQuery(db, recordType: recordType, recordName: recordName) }
    }

    private static func fetchEditRecordSongIdQuery(_ db: Database, recordType: String, recordName: String) throws -> String? {
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

    /// 指定ユニット ID のうち、楽曲を 1 曲以上持つもの (songs.unit_id 参照) を返す。
    /// アイドル詳細で「曲ありユニット / 曲なしユニット」を分けるのに使う。
    func fetchUnitIdsWithSongsAsync(unitIds: [String]) async throws -> Set<String> {
        guard !unitIds.isEmpty else { return [] }
        return try await dbQueue.read { db in try Self.fetchUnitIdsWithSongsQuery(db, unitIds: unitIds) }
    }

    private static func fetchUnitIdsWithSongsQuery(_ db: Database, unitIds: [String]) throws -> Set<String> {
        let placeholders = unitIds.map { _ in "?" }.joined(separator: ",")
        let rows = try String.fetchAll(
            db,
            sql: "SELECT DISTINCT unit_id FROM songs WHERE unit_id IN (\(placeholders))",
            arguments: StatementArguments(unitIds)
        )
        return Set(rows)
    }

    /// アイドルの楽曲一覧（song_type指定可）
    func fetchIdolSongsAsync(idolId: String, role: String? = nil) async throws -> [Song] {
        try await dbQueue.read { db in try Self.fetchIdolSongsQuery(db, idolId: idolId, role: role) }
    }

    private static func fetchIdolSongsQuery(_ db: Database, idolId: String, role: String?) throws -> [Song] {
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

    /// 声優名で担当アイドルを逆引き (idol.voice_actors の カンマ区切りに合致するもの)。
    func fetchIdolsByVoiceActorAsync(name: String) async throws -> [Idol] {
        try await dbQueue.read { db in try Self.fetchIdolsByVoiceActorQuery(db, name: name) }
    }

    private static func fetchIdolsByVoiceActorQuery(_ db: Database, name: String) throws -> [Idol] {
        // 歴代すべてを対象にする。前任者の名前で引いても担当アイドルに辿り着けた方が、
        // 「この人が昔やっていた役」を探す用途に合う。
        let sql = """
            SELECT DISTINCT i.* FROM idols i
              JOIN idol_voice_actors v ON v.idol_id = i.id
             WHERE v.name = ?
             ORDER BY i.sort_order
            """
        return try Idol.fetchAll(db, sql: sql, arguments: [name])
    }

    /// アイドル全員のCV名マップ (idol_id → 現役 voice_actor)。
    func fetchIdolCastNamesAsync() async throws -> [String: String] {
        try await dbQueue.read { db in try Self.fetchIdolCastNamesQuery(db) }
    }

    private static func fetchIdolCastNamesQuery(_ db: Database) throws -> [String: String] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT idol_id, name FROM idol_voice_actors
                 WHERE valid_to IS NULL
                 ORDER BY IFNULL(valid_from, '')
                """
        )
        // 同じアイドルに現任が複数居る場合 (同時に複数人が担当) は後勝ちで1人にする。
        // 表示は1名ぶんの想定なので、より新しい方を採る。
        var result: [String: String] = [:]
        for row in rows {
            result[row["idol_id"] as String] = row["name"] as String
        }
        return result
    }

    /// キャストの出演公演一覧
    /// イベント内のセトリで歌唱された全 unit_id を返す。
    /// setlist_items.unit_id (席上付与) と songs.unit_id (曲属性) の両方を見る。
    /// 「ユニット名義の曲」が披露されたユニット = ライブ上「ユニットとして登場した」と解釈。
    /// この event のセトリで「ユニット単独曲として披露された」ユニット ID 集合。
    /// setlist_performers の歌唱メンバーが unit_members と完全一致する曲があるユニットだけを返す。
    /// (legacy: setlist_items.unit_id / songs.unit_id 由来は誤検出が多いので採用しない)
    func fetchPerformedUnitIdsAsync(eventId: String) async throws -> Set<String> {
        try await dbQueue.read { db in try Self.fetchPerformedUnitIdsQuery(db, eventId: eventId) }
    }

    private static func fetchPerformedUnitIdsQuery(_ db: Database, eventId: String) throws -> Set<String> {
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

    /// 公演 (show) に出演している全アイドル ID のセット (show_cast)。 Cast 廃止後は idol_id 直結。
    func fetchShowIdolIdsAsync(showId: String) async throws -> Set<String> {
        try await dbQueue.read { db in try Self.fetchShowIdolIdsQuery(db, showId: showId) }
    }

    private static func fetchShowIdolIdsQuery(_ db: Database, showId: String) throws -> Set<String> {
        let ids = try String.fetchAll(
            db,
            sql: "SELECT idol_id FROM show_cast WHERE show_id = ?",
            arguments: [showId]
        )
        return Set(ids)
    }

    /// 指定公演の出演アイドル一覧 (show_cast JOIN idols)。sort_order 順。
    /// 「誰が歌う」予想の候補アイドルリストとして使う。
    func fetchShowCastIdolsAsync(showId: String) async throws -> [Idol] {
        try await dbQueue.read { db in try Self.fetchShowCastIdolsQuery(db, showId: showId) }
    }

    private static func fetchShowCastIdolsQuery(_ db: Database, showId: String) throws -> [Idol] {
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

    /// 指定アイドルの出演公演一覧 (setlist_performers ∪ show_cast)。
    /// セトリ未登録の公演でも出演履歴を拾えるよう UNION で結合する。
    func fetchIdolShowsAsync(idolId: String) async throws -> [CastShowRow] {
        try await dbQueue.read { db in try Self.fetchIdolShowsQuery(db, idolId: idolId) }
    }

    private static func fetchIdolShowsQuery(_ db: Database, idolId: String) throws -> [CastShowRow] {
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

    // MARK: - Idol Song Queries

    /// アイドルがライブで披露した曲一覧（披露回数付き）
    func fetchIdolPerformedSongsAsync(idolId: String) async throws -> [IdolPerformedSong] {
        try await dbQueue.read { db in try Self.fetchIdolPerformedSongsQuery(db, idolId: idolId) }
    }

    private static func fetchIdolPerformedSongsQuery(_ db: Database, idolId: String) throws -> [IdolPerformedSong] {
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

    /// アイドルが特定の曲を披露した公演履歴（最新順）
    func fetchIdolSongHistoryAsync(idolId: String, songId: String) async throws -> [CastShowRow] {
        try await dbQueue.read { db in try Self.fetchIdolSongHistoryQuery(db, idolId: idolId, songId: songId) }
    }

    private static func fetchIdolSongHistoryQuery(_ db: Database, idolId: String, songId: String) throws -> [CastShowRow] {
        // CastShowRow.castRole は非 Optional (既定値 .member) だが、GRDB の FetchableRecord は
        // Codable 合成デコード時に列自体が無いとキー不在で decode 失敗する (Swift のプロパティ
        // 既定値は synthesized Decodable には効かない)。cast_role を SELECT しないと
        // CastShowRow.fetchAll が毎回 throw し、呼び出し元 (IdolSongHistoryView) がそれを
        // 握りつぶして常に「披露記録はありません」になっていた。fetchIdolShows と同じ
        // COALESCE で明示的に補う。
        let sql = """
            SELECT DISTINCT sh.id AS show_id, e.id AS event_id,
                   e.name AS event_name, sh.name AS show_name, sh.date, sh.venue,
                   COALESCE(
                       (SELECT cast_role FROM show_cast WHERE show_id = sh.id AND idol_id = ?),
                       'member'
                   ) AS cast_role
            FROM setlist_items si
            JOIN shows sh ON si.show_id = sh.id
            JOIN events e ON sh.event_id = e.id
            JOIN setlist_performers sp ON si.id = sp.setlist_item_id
            WHERE si.song_id = ? AND sp.idol_id = ?
            ORDER BY sh.date DESC
            """
        return try CastShowRow.fetchAll(db, sql: sql, arguments: [idolId, songId, idolId])
    }

}
