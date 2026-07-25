//  AppDatabase の Event Queries / Setlist Queries / Filtered Fetch Methods / Private Helpers を切り出したもの。
//  分割の意図と分割線の引き方は docs/ARCHITECTURE.md を参照。
//  ここにあるのは移動してきたクエリだけで、ロジックは 1 行も変えていない。

import Foundation
import GRDB

extension AppDatabase {

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

    /// 会場での公演一覧。 `venue` は会場マスタの ID (`venue_...`)。
    ///
    /// 会場を ID 管理にする前は生の会場文字列 (`shows.venue`) で突き合わせていたが、
    /// 表記ゆれで同じ会場が分断されるため venue_id を正とする。 ID を持たない公演
    /// (会場が特定できなかったもの) は venue 文字列でしか辿れないので、 後方互換として
    /// 「ID 一致 または 生文字列一致」の OR にしておく。
    private static func showsByVenueQuery(_ db: Database, venue: String) throws -> [Show] {
        try Show
            .filter(Column("venue_id") == venue || Column("venue") == venue)
            .order(Column("date").desc)
            .fetchAll(db)
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
