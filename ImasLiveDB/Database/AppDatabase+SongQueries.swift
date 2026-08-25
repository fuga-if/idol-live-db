//  AppDatabase の Song Queries / Song Search (for OCR matching) / Album Queries を切り出したもの。
//  分割の意図と分割線の引き方は docs/ARCHITECTURE.md を参照。
//  ここにあるのは移動してきたクエリだけで、ロジックは 1 行も変えていない。

import Foundation
import GRDB

extension AppDatabase {

    // MARK: - Song Queries

    /// 楽曲一覧
    /// 指定 song_id のリストに対して、各 song に紐付く performer idol 配列を返す。
    /// song_artists は (song_id, idol_id) 直接マッピング。
    /// 一覧表示でアイドルアイコンを並べるため一括取得する。
    func fetchSongPerformerIdolsMap(songIds: [String]) throws -> [String: [Idol]] {
        guard !songIds.isEmpty else { return [:] }
        return try dbQueue.read { db in try Self.fetchSongPerformerIdolsMapQuery(db, songIds: songIds) }
    }

    func fetchSongPerformerIdolsMapAsync(songIds: [String]) async throws -> [String: [Idol]] {
        guard !songIds.isEmpty else { return [:] }
        return try await dbQueue.read { db in try Self.fetchSongPerformerIdolsMapQuery(db, songIds: songIds) }
    }

    private static func fetchSongPerformerIdolsMapQuery(_ db: Database, songIds: [String]) throws -> [String: [Idol]] {
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

    func fetchSongs(
        filter: SongSearchFilter = SongSearchFilter(),
        sortOrder: SongSortOrder = .titleKana,
        ascending: Bool? = nil
    ) throws -> [SongWithArtists] {
        try dbQueue.read { db in try Self.fetchSongsByFilterQuery(db, filter: filter, sortOrder: sortOrder, ascending: ascending) }
    }

    func fetchSongsAsync(filter: SongSearchFilter = SongSearchFilter(), sortOrder: SongSortOrder = .titleKana, ascending: Bool? = nil) async throws -> [SongWithArtists] {
        try await dbQueue.read { db in try Self.fetchSongsByFilterQuery(db, filter: filter, sortOrder: sortOrder, ascending: ascending) }
    }

    private static func fetchSongsByFilterQuery(_ db: Database, filter: SongSearchFilter, sortOrder: SongSortOrder, ascending: Bool?) throws -> [SongWithArtists] {
        let asc = ascending ?? sortOrder.defaultAscending
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
            // 持ち曲 (role='original') だけに絞る。role を見ないと 'performer'
            // (そのアイドルがライブで一度歌っただけの曲) まで拾ってしまい、
            // 「このアイドルの曲」を見たいのに他人の持ち曲がずらりと並ぶ。
            // 担当アイドル絞り込み (fetchSongIdsWithAnyArtistQuery) 側は元から original 限定で、
            // ここだけ条件が抜けていた。
            sql += " JOIN song_artists sa ON s.id = sa.song_id AND sa.role = 'original'"
            sql += " JOIN idols i ON sa.idol_id = i.id"
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

    /// song_id → 全公演での披露回数。並び替えだけでなく、一覧行に数値を出すのにも使う。
    func fetchSongPerformanceCountsAsync() async throws -> [String: Int] {
        try await dbQueue.read { db in try Self.totalSongPerformanceCountMap(db) }
    }

    /// song_id → 全公演での披露回数。
    private static func totalSongPerformanceCountMap(_ db: Database) throws -> [String: Int] {
        let rows = try SongPerfCount.fetchAll(
            db, sql: "SELECT song_id, COUNT(*) as cnt FROM setlist_items GROUP BY song_id"
        )
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.songId, $0.cnt) })
    }

    /// ユーザが参加した show (event 単位の attended も配下 show を含む) 経由の
    /// song_id → 回収回数。 楽曲一覧の「現地回収回数順 / 回収率順」で使用。
    private static func attendedSongCountMap(_ db: Database) throws -> [String: Int] {
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
        try dbQueue.read { db in try Self.fetchSongQuery(db, id: id) }
    }

    func fetchSongAsync(id: String) async throws -> Song? {
        try await dbQueue.read { db in try Self.fetchSongQuery(db, id: id) }
    }

    private static func fetchSongQuery(_ db: Database, id: String) throws -> Song? {
        try Song.fetchOne(db, key: id)
    }

    /// 楽曲一括取得（複数ID指定・IN句1回）。N+1防止用。
    func fetchSongs(ids: [String]) throws -> [Song] {
        guard !ids.isEmpty else { return [] }
        return try dbQueue.read { db in try Self.fetchSongsByIdsQuery(db, ids: ids) }
    }

    func fetchSongsAsync(ids: [String]) async throws -> [Song] {
        guard !ids.isEmpty else { return [] }
        return try await dbQueue.read { db in try Self.fetchSongsByIdsQuery(db, ids: ids) }
    }

    private static func fetchSongsByIdsQuery(_ db: Database, ids: [String]) throws -> [Song] {
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        return try Song.fetchAll(db, sql: "SELECT * FROM songs WHERE id IN (\(placeholders))",
                                arguments: StatementArguments(ids))
    }

    /// 一覧に出す資格のある曲だけを id で引く。
    ///
    /// 一覧が既定で隠しているもの (`SongSearchFilter` と同じ規則) をここでも落とす:
    /// - 派生曲 (`parent_song_id` あり)。ソロ Ver. や Remix は親に代表させる。
    /// - その他ブランド (`brand_id = 'other'`、歌枠カバー等)。
    ///
    /// 歌詞検索はサーバ (D1) 側でヒットを出すが、D1 はマスタを持っていないので
    /// ブランドも派生関係も判定できない。絞り込みはここでやる。
    /// 判断をビューに書くと一覧の規則と二重管理になるため、SQL 側に置く。
    func fetchListableSongsAsync(ids: [String]) async throws -> [Song] {
        guard !ids.isEmpty else { return [] }
        return try await dbQueue.read { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            return try Song.fetchAll(db, sql: """
                SELECT * FROM songs
                 WHERE id IN (\(placeholders))
                   AND parent_song_id IS NULL
                   AND brand_id IS NOT 'other'
                """, arguments: StatementArguments(ids))
        }
    }

    /// 指定ブランドの非カバー楽曲IDを id 昇順で返す (今日の1曲の決定論的ピック用・軽量)。
    func fetchSongIds(brandId: String, includeCovers: Bool = false, excludeRemixes: Bool = false) throws -> [String] {
        try dbQueue.read { db in try Self.fetchSongIdsQuery(db, brandId: brandId, includeCovers: includeCovers, excludeRemixes: excludeRemixes) }
    }

    func fetchSongIdsAsync(brandId: String, includeCovers: Bool = false, excludeRemixes: Bool = false) async throws -> [String] {
        try await dbQueue.read { db in try Self.fetchSongIdsQuery(db, brandId: brandId, includeCovers: includeCovers, excludeRemixes: excludeRemixes) }
    }

    private static func fetchSongIdsQuery(_ db: Database, brandId: String, includeCovers: Bool, excludeRemixes: Bool) throws -> [String] {
        var sql = "SELECT id FROM songs WHERE brand_id=?"
        if !includeCovers { sql += " AND song_type<>'cover'" }
        // 今日の1曲などでリミックス変種(同名の紛らわしい重複)を避けるため除外可能に。
        if excludeRemixes { sql += " AND (parent_song_id IS NULL OR parent_song_id='')" }
        sql += " ORDER BY id"
        return try String.fetchAll(db, sql: sql, arguments: [brandId])
    }

    /// 楽曲シリーズ(series_group)の一覧。ブランド指定時はそのブランドに絞る。曲数降順。
    func fetchSeriesGroupsAsync(brandIds: Set<String> = []) async throws -> [String] {
        try await dbQueue.read { db in try Self.fetchSeriesGroupsQuery(db, brandIds: brandIds) }
    }

    private static func fetchSeriesGroupsQuery(_ db: Database, brandIds: Set<String>) throws -> [String] {
        let base = "SELECT series_group FROM songs WHERE series_group IS NOT NULL AND series_group<>''"
        if brandIds.isEmpty {
            return try String.fetchAll(db, sql: base + " GROUP BY series_group ORDER BY COUNT(*) DESC")
        }
        let ph = brandIds.map { _ in "?" }.joined(separator: ",")
        return try String.fetchAll(db, sql: base + " AND brand_id IN (\(ph)) GROUP BY series_group ORDER BY COUNT(*) DESC",
                                   arguments: StatementArguments(Array(brandIds)))
    }

    /// アイドル一括取得（ID配列）— N+1 解消用
    func fetchIdols(ids: [String]) throws -> [Idol] {
        guard !ids.isEmpty else { return [] }
        return try dbQueue.read { db in try Self.fetchIdolsByIdsQuery(db, ids: ids) }
    }

    func fetchIdolsAsync(ids: [String]) async throws -> [Idol] {
        guard !ids.isEmpty else { return [] }
        return try await dbQueue.read { db in try Self.fetchIdolsByIdsQuery(db, ids: ids) }
    }

    private static func fetchIdolsByIdsQuery(_ db: Database, ids: [String]) throws -> [Idol] {
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        return try Idol.fetchAll(db, sql: "SELECT * FROM idols WHERE id IN (\(placeholders))",
                                 arguments: StatementArguments(ids))
    }

    /// アイドル取得（ID指定）
    func fetchIdolAsync(id: String) async throws -> Idol? {
        try await dbQueue.read { db in try Self.fetchIdolQuery(db, id: id) }
    }

    private static func fetchIdolQuery(_ db: Database, id: String) throws -> Idol? {
        try Idol.fetchOne(db, key: id)
    }

    /// 公演取得（ID指定）
    func fetchShow(id: String) throws -> Show? {
        try dbQueue.read { db in try Self.fetchShowQuery(db, id: id) }
    }

    func fetchShowAsync(id: String) async throws -> Show? {
        try await dbQueue.read { db in try Self.fetchShowQuery(db, id: id) }
    }

    private static func fetchShowQuery(_ db: Database, id: String) throws -> Show? {
        try Show.fetchOne(db, key: id)
    }

    /// 公演 id 群 → 所属イベント id 集合を 1 クエリで解決する。
    /// 参加記録 (show 単位) から event 単位の絞り込みを作るのに使う。
    /// 1 件ずつ引くと参加数ぶん往復するので、必ずこの一括版を通すこと。
    func fetchEventIdsForShowsAsync(showIds: [String]) async throws -> Set<String> {
        guard !showIds.isEmpty else { return [] }
        return try await dbQueue.read { db in
            let placeholders = showIds.map { _ in "?" }.joined(separator: ", ")
            let ids = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT event_id FROM shows WHERE id IN (\(placeholders))",
                arguments: StatementArguments(showIds))
            return Set(ids)
        }
    }

    /// イベント取得（ID指定）
    func fetchEvent(id: String) throws -> Event? {
        try dbQueue.read { db in try Self.fetchEventQuery(db, id: id) }
    }

    func fetchEventAsync(id: String) async throws -> Event? {
        try await dbQueue.read { db in try Self.fetchEventQuery(db, id: id) }
    }

    private static func fetchEventQuery(_ db: Database, id: String) throws -> Event? {
        try Event.fetchOne(db, key: id)
    }

    /// イベントの映像円盤 (event_releases)。所有チェックUIの母集団。発売日→sort_order 順。
    func fetchEventReleasesAsync(eventId: String) async throws -> [EventRelease] {
        try await dbQueue.read { db in try Self.fetchEventReleasesQuery(db, eventId: eventId) }
    }

    private static func fetchEventReleasesQuery(_ db: Database, eventId: String) throws -> [EventRelease] {
        try EventRelease
            .filter(Column("event_id") == eventId)
            .order(Column("release_date").asc, Column("sort_order").asc)
            .fetchAll(db)
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
    func fetchSongArtistsAsync(songId: String, role: String? = nil) async throws -> [Idol] {
        try await dbQueue.read { db in try Self.fetchSongArtistsQuery(db, songId: songId, role: role) }
    }

    private static func fetchSongArtistsQuery(_ db: Database, songId: String, role: String?) throws -> [Idol] {
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

    /// 楽曲の披露履歴
    func fetchSongPerformanceHistoryAsync(songId: String) async throws -> [PerformanceHistoryRow] {
        try await dbQueue.read { db in try Self.fetchSongPerformanceHistoryQuery(db, songId: songId) }
    }

    private static func fetchSongPerformanceHistoryQuery(_ db: Database, songId: String) throws -> [PerformanceHistoryRow] {
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

    // MARK: - Song Search (for OCR matching)

    /// 楽曲をタイトルで検索（完全一致優先、部分一致も含む）
    func searchSongs(query: String, limit: Int = 10) throws -> [Song] {
        try dbQueue.read { db in try Self.searchSongsQuery(db, query: query, limit: limit) }
    }

    func searchSongsAsync(query: String, limit: Int = 10) async throws -> [Song] {
        try await dbQueue.read { db in try Self.searchSongsQuery(db, query: query, limit: limit) }
    }

    private static func searchSongsQuery(_ db: Database, query: String, limit: Int) throws -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 完全一致を先に取得
        let exact = try Song
            .filter(Column("title") == trimmed)
            .fetchAll(db)

        if !exact.isEmpty { return exact }

        // 部分一致
        let pattern = "%\(trimmed.likeEscaped)%"
        return try Song
            .filter(Column("title").like(pattern, escape: "\\") || Column("title_kana").like(pattern, escape: "\\"))
            .limit(limit)
            .fetchAll(db)
    }

    // MARK: - Album Queries

    /// CDシリーズ別アルバム一覧
    func fetchAlbumsAsync(brandIds: Set<String> = [], query: String?) async throws -> [AlbumSummary] {
        try await dbQueue.read { db in try Self.fetchAlbumsQuery(db, brandIds: brandIds, query: query) }
    }

    private static func fetchAlbumsQuery(_ db: Database, brandIds: Set<String>, query: String?) throws -> [AlbumSummary] {
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

    /// CDシリーズグループ別一覧 (LIVE THE@TER PERFORMANCE 等の括り)
    func fetchSeriesAsync(brandIds: Set<String> = [], query: String?) async throws -> [SeriesSummary] {
        try await dbQueue.read { db in try Self.fetchSeriesQuery(db, brandIds: brandIds, query: query) }
    }

    private static func fetchSeriesQuery(_ db: Database, brandIds: Set<String>, query: String?) throws -> [SeriesSummary] {
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

    // MARK: - 別バージョン

    /// 同じ曲の別バージョン (`parent_song_id` で束ねた一族) を、自分を除いて返す。
    ///
    /// 一覧・カレンダー・統計・クイズは `parent_song_id IS NULL` で派生曲を隠している。
    /// 隠しっぱなしだと「Crossing! のソロ 15 種」に**どこからも辿り着けない**ので、
    /// 詳細画面からここを通して見せる。
    ///
    /// 自分が派生側でも親側でも同じ一族が返るよう、まず根 (parent_song_id ?? id) を
    /// 求めてから、根と根を親に持つ曲を集める。
    func fetchVariantSongsAsync(of song: Song) async throws -> [Song] {
        try await dbQueue.read { db in
            let root = song.parentSongId ?? song.id
            return try Song.fetchAll(db, sql: """
                SELECT * FROM songs
                 WHERE (id = ? OR parent_song_id = ?) AND id != ?
                 ORDER BY CASE WHEN parent_song_id IS NULL THEN 0 ELSE 1 END,
                          title_kana, title
                """, arguments: [root, root, song.id])
        }
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
