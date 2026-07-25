//  AppDatabase の UserMark Methods / PersonalTag Methods / Auto Collected / Collection Dashboard を切り出したもの。
//  分割の意図と分割線の引き方は docs/ARCHITECTURE.md を参照。
//  ここにあるのは移動してきたクエリだけで、ロジックは 1 行も変えていない。

import Foundation
import GRDB

extension AppDatabase {

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
        try dbQueue.read { db in try Self.fetchMarkedEntityIdsQuery(db, entity: entity, kind: kind) }
    }

    func fetchMarkedEntityIdsAsync(entity: UserMarkEntity, kind: UserMarkKind) async throws -> [String] {
        try await dbQueue.read { db in try Self.fetchMarkedEntityIdsQuery(db, entity: entity, kind: kind) }
    }

    private static func fetchMarkedEntityIdsQuery(_ db: Database, entity: UserMarkEntity, kind: UserMarkKind) throws -> [String] {
        try UserMark.filter(
            UserMark.Columns.entityType == entity.rawValue &&
            UserMark.Columns.kind == kind.rawValue &&
            UserMark.Columns.boolValue == true
        ).fetchAll(db).map(\.entityId)
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

    // MARK: - PersonalTag Methods (個人用タグ、完全ローカル専用・サーバー非送信)

    /// 同一 (entity_type, entity_id, tag_name) の二重登録は無視する (INSERT OR IGNORE 相当)。
    func addPersonalTag(entityType: String, entityId: String, tagName: String) throws {
        try dbQueue.write { db in
            let tag = PersonalTag(entityType: entityType, entityId: entityId, tagName: tagName,
                                   createdAt: ISO8601DateFormatter.shared.string(from: Date()))
            try tag.insert(db, onConflict: .ignore)
        }
    }

    func removePersonalTag(entityType: String, entityId: String, tagName: String) throws {
        try dbQueue.write { db in
            _ = try PersonalTag.filter(
                PersonalTag.Columns.entityType == entityType &&
                PersonalTag.Columns.entityId == entityId &&
                PersonalTag.Columns.tagName == tagName
            ).deleteAll(db)
        }
    }

    func fetchPersonalTags(entityType: String, entityId: String) throws -> [PersonalTag] {
        try dbQueue.read { db in
            try PersonalTag.filter(
                PersonalTag.Columns.entityType == entityType &&
                PersonalTag.Columns.entityId == entityId
            ).order(PersonalTag.Columns.createdAt).fetchAll(db)
        }
    }

    /// 将来のバックアップ機能連携用 (現状はローカル保存のみで未使用)。
    func allPersonalTags() throws -> [PersonalTag] {
        try dbQueue.read { db in try PersonalTag.fetchAll(db) }
    }

    /// バックアップからの非破壊復元: ローカルに無い (entity,id,tagName) の行だけ追加する。
    /// UserMark の restoreUserMarksIfAbsent と同じ方針で、既存ローカル行は上書き/削除しない。
    @discardableResult
    func restorePersonalTagsIfAbsent(_ tags: [PersonalTag]) throws -> Int {
        try dbQueue.write { db in
            var inserted = 0
            for t in tags {
                let exists = try PersonalTag
                    .filter(PersonalTag.Columns.entityType == t.entityType
                            && PersonalTag.Columns.entityId == t.entityId
                            && PersonalTag.Columns.tagName == t.tagName)
                    .fetchCount(db) > 0
                if !exists {
                    try t.insert(db)
                    inserted += 1
                }
            }
            return inserted
        }
    }

    // MARK: - Auto Collected (参加ライブから自動判定)

    /// 指定 idol_id 群のうち、 いずれかが歌唱者 (role='original') として紐付いてる song_id 集合。
    /// 「担当アイドル の曲」 など bulk 絞り込み用。
    func fetchSongIdsWithAnyArtist(idolIds: Set<String>) throws -> Set<String> {
        guard !idolIds.isEmpty else { return [] }
        return try dbQueue.read { db in try Self.fetchSongIdsWithAnyArtistQuery(db, idolIds: idolIds) }
    }

    func fetchSongIdsWithAnyArtistAsync(idolIds: Set<String>) async throws -> Set<String> {
        guard !idolIds.isEmpty else { return [] }
        return try await dbQueue.read { db in try Self.fetchSongIdsWithAnyArtistQuery(db, idolIds: idolIds) }
    }

    private static func fetchSongIdsWithAnyArtistQuery(_ db: Database, idolIds: Set<String>) throws -> Set<String> {
        let placeholders = idolIds.map { _ in "?" }.joined(separator: ",")
        let sql = "SELECT DISTINCT song_id FROM song_artists WHERE role='original' AND idol_id IN (\(placeholders))"
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(Array(idolIds)))
        return Set(rows.compactMap { row -> String? in row["song_id"] })
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

    /// (async) 現地回収回数マップ取得。cooperative thread pool をブロックしない。
    func fetchSongCollectedCountsAsync() async throws -> [String: Int] {
        let condition = attendedTypeCondition
        return try await dbQueue.read { db in try Self.fetchSongCollectedCountsQuery(db, attendedTypeCondition: condition) }
    }

    private static func fetchSongCollectedCountsQuery(_ db: Database, attendedTypeCondition: String) throws -> [String: Int] {
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
        let condition = attendedTypeCondition
        return try dbQueue.read { db in try Self.fetchAutoCollectedSongIdsQuery(db, attendedTypeCondition: condition) }
    }

    /// (async) 自動回収曲ID取得。cooperative thread pool をブロックしない。
    func fetchAutoCollectedSongIdsAsync() async throws -> Set<String> {
        let condition = attendedTypeCondition
        return try await dbQueue.read { db in try Self.fetchAutoCollectedSongIdsQuery(db, attendedTypeCondition: condition) }
    }

    private static func fetchAutoCollectedSongIdsQuery(_ db: Database, attendedTypeCondition: String) throws -> Set<String> {
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

    /// その曲を披露した、ユーザが参加済みの show 一覧 (親 event 名込み)
    func fetchCollectedShowsAsync(for songId: String) async throws -> [ShowWithEventName] {
        try await dbQueue.read { db in try Self.fetchCollectedShowsQuery(db, for: songId) }
    }

    private static func fetchCollectedShowsQuery(_ db: Database, for songId: String) throws -> [ShowWithEventName] {
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

}
