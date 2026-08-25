//  AppDatabase の Stats Queries / Search を切り出したもの。
//  分割の意図と分割線の引き方は docs/ARCHITECTURE.md を参照。
//  ここにあるのは移動してきたクエリだけで、ロジックは 1 行も変えていない。

import Foundation
import GRDB

extension AppDatabase {

    // MARK: - Stats Queries

    /// ブランド別楽曲数
    func fetchBrandSongCountsAsync() async throws -> [BrandSongCount] {
        try await dbQueue.read { db in try Self.fetchBrandSongCountsQuery(db) }
    }

    private static func fetchBrandSongCountsQuery(_ db: Database) throws -> [BrandSongCount] {
        let sql = """
            SELECT b.id, b.short_name, b.color, COUNT(s.id) AS song_count
            FROM brands b LEFT JOIN songs s ON b.id = s.brand_id
            GROUP BY b.id ORDER BY b.sort_order
            """
        return try BrandSongCount.fetchAll(db, sql: sql)
    }

    /// brand_id が設定されている曲 ID セット。
    /// 回収率集計で分子と分母の母集合を揃えるために使う。
    func fetchBrandedSongIds() throws -> Set<String> {
        try dbQueue.read { db in try Self.fetchBrandedSongIdsQuery(db) }
    }

    func fetchBrandedSongIdsAsync() async throws -> Set<String> {
        try await dbQueue.read { db in try Self.fetchBrandedSongIdsQuery(db) }
    }

    private static func fetchBrandedSongIdsQuery(_ db: Database) throws -> Set<String> {
        let ids = try String.fetchAll(db, sql: "SELECT id FROM songs WHERE brand_id IS NOT NULL")
        return Set(ids)
    }

    /// 全ブランド取得
    func fetchBrands() throws -> [Brand] {
        try dbQueue.read { db in try Self.fetchBrandsQuery(db) }
    }

    func fetchBrandsAsync() async throws -> [Brand] {
        try await dbQueue.read { db in try Self.fetchBrandsQuery(db) }
    }

    private static func fetchBrandsQuery(_ db: Database) throws -> [Brand] {
        try Brand.order(Column("sort_order")).fetchAll(db)
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
    func fetchSongPlayCountRankingAsync(limit: Int = 20) async throws -> [SongPlayCount] {
        try await dbQueue.read { db in try Self.fetchSongPlayCountRankingQuery(db, limit: limit) }
    }

    private static func fetchSongPlayCountRankingQuery(_ db: Database, limit: Int) throws -> [SongPlayCount] {
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

    /// アイドル別出演回数ランキング (Cast 廃止後は idol 単位)。
    /// 表示名は idol.name を採用 (旧 cast.name の代わり)。
    func fetchCastShowCountRankingAsync(limit: Int = 20) async throws -> [CastShowCount] {
        try await dbQueue.read { db in try Self.fetchCastShowCountRankingQuery(db, limit: limit) }
    }

    private static func fetchCastShowCountRankingQuery(_ db: Database, limit: Int) throws -> [CastShowCount] {
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

    /// 全ユニット (picker 用)。
    func fetchAllUnits() throws -> [Unit] {
        try dbQueue.read { db in try Self.fetchAllUnitsQuery(db) }
    }

    func fetchAllUnitsAsync() async throws -> [Unit] {
        try await dbQueue.read { db in try Self.fetchAllUnitsQuery(db) }
    }

    private static func fetchAllUnitsQuery(_ db: Database) throws -> [Unit] {
        try Unit.order(Column("brand_id"), Column("name")).fetchAll(db)
    }

    /// ユニット取得
    func fetchUnitAsync(id: String) async throws -> Unit? {
        try await dbQueue.read { db in try Self.fetchUnitQuery(db, id: id) }
    }

    private static func fetchUnitQuery(_ db: Database, id: String) throws -> Unit? {
        try Unit.fetchOne(db, key: id)
    }

    /// ユニットメンバー取得
    func fetchUnitMembersAsync(unitId: String) async throws -> [Idol] {
        try await dbQueue.read { db in try Self.fetchUnitMembersQuery(db, unitId: unitId) }
    }

    private static func fetchUnitMembersQuery(_ db: Database, unitId: String) throws -> [Idol] {
        let sql = """
            SELECT i.* FROM idols i
            JOIN unit_members um ON i.id = um.idol_id
            WHERE um.unit_id = ?
            ORDER BY i.sort_order
            """
        return try Idol.fetchAll(db, sql: sql, arguments: [unitId])
    }

    /// setlist 表示で「performer が unit 全員揃ったら unit 名を出す」ために使うインデックス。
    /// 全 unit を一度に取得して、idol_id → 属する unit 一覧のマップを構築する。
    func fetchUnitIndex() throws -> UnitIndex {
        try dbQueue.read { db in try Self.fetchUnitIndexQuery(db) }
    }

    func fetchUnitIndexAsync() async throws -> UnitIndex {
        try await dbQueue.read { db in try Self.fetchUnitIndexQuery(db) }
    }

    private static func fetchUnitIndexQuery(_ db: Database) throws -> UnitIndex {
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

    /// ユニット楽曲取得
    func fetchUnitSongsAsync(unitId: String) async throws -> [Song] {
        try await dbQueue.read { db in try Self.fetchUnitSongsQuery(db, unitId: unitId) }
    }

    private static func fetchUnitSongsQuery(_ db: Database, unitId: String) throws -> [Song] {
        try Song.filter(Column("unit_id") == unitId).order(Column("release_date")).fetchAll(db)
    }

    /// DB全体の統計 (外部ゲスト演者は除外)
    func fetchDatabaseStatsAsync() async throws -> DatabaseStats {
        try await dbQueue.read { db in try Self.fetchDatabaseStatsQuery(db) }
    }

    private static func fetchDatabaseStatsQuery(_ db: Database) throws -> DatabaseStats {
        DatabaseStats(
            songCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM songs") ?? 0,
            idolCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM idols WHERE is_external = 0") ?? 0,
            eventCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? 0,
            showCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM shows") ?? 0
        )
    }

    /// 同期診断用 — recordName に '@' が入ったレコード数を集計し、ML 13thLIVE が
    /// 存在するかチェックする。@-roundtrip バグの切り分けに使う。
    func fetchSyncDiagnosticsAsync() async throws -> SyncDiagnostics {
        try await dbQueue.read { db in try Self.fetchSyncDiagnosticsQuery(db) }
    }

    private static func fetchSyncDiagnosticsQuery(_ db: Database) throws -> SyncDiagnostics {
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

    /// 直近公演取得
    func fetchLatestShowAsync() async throws -> Show? {
        try await dbQueue.read { db in try Self.fetchLatestShowQuery(db) }
    }

    private static func fetchLatestShowQuery(_ db: Database) throws -> Show? {
        try Show.order(Column("date").desc).fetchOne(db)
    }

    /// CDシリーズ一覧（ユニーク値）
    func fetchCdSeriesListAsync() async throws -> [String] {
        try await dbQueue.read { db in try Self.fetchCdSeriesListQuery(db) }
    }

    private static func fetchCdSeriesListQuery(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT DISTINCT cd_series FROM songs
            WHERE cd_series IS NOT NULL AND cd_series != ''
            ORDER BY cd_series
            """)
    }

    /// イベント名一覧
    func fetchEventNamesAsync() async throws -> [String] {
        try await dbQueue.read { db in try Self.fetchEventNamesQuery(db) }
    }

    private static func fetchEventNamesQuery(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT name FROM events ORDER BY name")
    }

    /// イベント名 OR 公演会場 (shows.venue) のいずれかが query に部分一致するイベントを返す。
    /// venue は同 event 内の複数 shows をまたぐので EXISTS で結合。
    func searchEventsByNameOrVenue(query: String, limit: Int = 100) throws -> [Event] {
        try dbQueue.read { db in try Self.searchEventsByNameOrVenueQuery(db, query: query, limit: limit) }
    }

    func searchEventsByNameOrVenueAsync(query: String, limit: Int = 100) async throws -> [Event] {
        try await dbQueue.read { db in try Self.searchEventsByNameOrVenueQuery(db, query: query, limit: limit) }
    }

    private static func searchEventsByNameOrVenueQuery(_ db: Database, query: String, limit: Int) throws -> [Event] {
        let pattern = "%\(query.lowercased().likeEscaped)%"
        return try Event.fetchAll(
            db,
            sql: """
                SELECT DISTINCT e.* FROM events e
                LEFT JOIN shows sh ON sh.event_id = e.id
                WHERE LOWER(e.name) LIKE ? ESCAPE '\\'
                   OR LOWER(IFNULL(sh.venue, '')) LIKE ? ESCAPE '\\'
                LIMIT ?
                """,
            arguments: [pattern, pattern, limit]
        )
    }

    /// アイドルを名前 / かな / ローマ字の部分一致で検索 (ピッカー用)。
    func searchIdols(query: String, limit: Int = 50) throws -> [Idol] {
        try dbQueue.read { db in try Self.searchIdolsQuery(db, query: query, limit: limit) }
    }

    func searchIdolsAsync(query: String, limit: Int = 50) async throws -> [Idol] {
        try await dbQueue.read { db in try Self.searchIdolsQuery(db, query: query, limit: limit) }
    }

    private static func searchIdolsQuery(_ db: Database, query: String, limit: Int) throws -> [Idol] {
        let pattern = "%\(query.likeEscaped)%"
        // CV 名と別名 (aliases) も対象にする。声優名でアイドルを引くのは
        // このアプリでは主要な探し方なので、名前系カラムだけだと取りこぼす。
        //
        // CV は idol_voice_actors (期間つき履歴) にあり、**歴代すべて**を対象にする。
        // 前任者の名前で引いても担当アイドルに辿り着けた方が、「この人が昔やっていた役」
        // を探す用途に合う。
        // 相関サブクエリは GRDB の式ビルダーでは組めないので素の SQL で書く。
        return try Idol.fetchAll(db, sql: """
            SELECT * FROM idols
             WHERE name        LIKE :p ESCAPE '\\'
                OR name_kana   LIKE :p ESCAPE '\\'
                OR name_romaji LIKE :p ESCAPE '\\'
                OR aliases     LIKE :p ESCAPE '\\'
                OR EXISTS (SELECT 1 FROM idol_voice_actors v
                            WHERE v.idol_id = idols.id AND v.name LIKE :p ESCAPE '\\')
             ORDER BY sort_order
             LIMIT :limit
            """, arguments: ["p": pattern, "limit": limit])
    }

    /// metaテーブルから値取得
    func fetchMetaValue(forKey key: String) throws -> String? {
        try dbQueue.read { db in try Self.fetchMetaValueQuery(db, forKey: key) }
    }

    func fetchMetaValueAsync(forKey key: String) async throws -> String? {
        try await dbQueue.read { db in try Self.fetchMetaValueQuery(db, forKey: key) }
    }

    private static func fetchMetaValueQuery(_ db: Database, forKey key: String) throws -> String? {
        try Meta.getValue(db, forKey: key)
    }

    /// 年別ライブ開催数推移
    func fetchYearlyShowCountsAsync() async throws -> [YearlyShowCount] {
        try await dbQueue.read { db in try Self.fetchYearlyShowCountsQuery(db) }
    }

    private static func fetchYearlyShowCountsQuery(_ db: Database) throws -> [YearlyShowCount] {
        let sql = """
            SELECT strftime('%Y', date) AS year, COUNT(*) AS show_count
            FROM shows
            GROUP BY year
            ORDER BY year
            """
        return try YearlyShowCount.fetchAll(db, sql: sql)
    }

    // MARK: - Search

    /// グローバル検索
    func search(query: String) throws -> SearchResults {
        try dbQueue.read { db in try Self.searchQuery(db, query: query) }
    }

    func searchAsync(query: String) async throws -> SearchResults {
        try await dbQueue.read { db in try Self.searchQuery(db, query: query) }
    }

    private static func searchQuery(_ db: Database, query: String) throws -> SearchResults {
        let pattern = "%\(query.likeEscaped)%"

        let songs = try Song.filter(
            Column("title").like(pattern, escape: "\\") ||
            Column("title_kana").like(pattern, escape: "\\")
        ).limit(20).fetchAll(db)

        let idols = try Idol.filter(
            Column("name").like(pattern, escape: "\\") ||
            Column("name_kana").like(pattern, escape: "\\")
        ).limit(20).fetchAll(db)

        let events = try Event.filter(
            Column("name").like(pattern, escape: "\\")
        ).limit(20).fetchAll(db)

        return SearchResults(songs: songs, idols: idols, events: events)
    }

}
