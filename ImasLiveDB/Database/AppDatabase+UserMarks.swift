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

    /// 参加の記録 (有無と形態) を 1 トランザクションで書く。`text` が nil なら取り消し。
    /// `text` は形態の保存値 (複数は "live,stream"。組み立てはコアの `attendanceSetType`)。
    ///
    /// 有無 (bool_value) と種別 (text_value) を別々に書くと、間で失敗したときに
    /// 「参加しているのに種別が無い / 取り消したのに種別が残る」行ができる。
    func setAttendanceMark(entity: UserMarkEntity, id: String, text: String?) throws {
        try upsertUserMarkRow(entity: entity, id: id, kind: .attended) { existing in
            existing.boolValue = text != nil
            existing.textValue = text
        } makeNew: {
            UserMark(entityType: entity.rawValue, entityId: id, kind: UserMarkKind.attended.rawValue,
                     boolValue: text != nil, textValue: text,
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

    func fetchMarkedEntityIds(entity: UserMarkEntity, kind: UserMarkKind) throws -> [String] {
        try dbQueue.read { db in try Self.fetchMarkedEntityIdsQuery(db, entity: entity, kind: kind) }
    }

    func fetchMarkedEntityIdsAsync(entity: UserMarkEntity, kind: UserMarkKind) async throws -> [String] {
        try await dbQueue.read { db in try Self.fetchMarkedEntityIdsQuery(db, entity: entity, kind: kind) }
    }

    /// 付いているマークの対象 id と付けた時刻 (`updated_at`)。付いているとみなす規則は `fetchMarkedEntityIdsQuery` と同じ。
    func fetchMarkedTimesAsync(entity: UserMarkEntity, kind: UserMarkKind) async throws -> [String: String] {
        try await dbQueue.read { db in
            let rows = try UserMark.filter(
                UserMark.Columns.entityType == entity.rawValue &&
                UserMark.Columns.kind == kind.rawValue
            ).fetchAll(db)
            return Dictionary(UserMark.meaningful(rows).map { ($0.entityId, $0.updatedAt) },
                              uniquingKeysWith: { a, b in max(a, b) })
        }
    }

    /// 付いているマークの対象 id。何を付いているとみなすかはコアの規則 (`UserMark.meaningful`)。
    /// メモのように中身を文字で持つ kind もあるので、フラグで絞らない。
    private static func fetchMarkedEntityIdsQuery(_ db: Database, entity: UserMarkEntity, kind: UserMarkKind) throws -> [String] {
        let rows = try UserMark.filter(
            UserMark.Columns.entityType == entity.rawValue &&
            UserMark.Columns.kind == kind.rawValue
        ).fetchAll(db)
        return UserMark.meaningful(rows).map(\.entityId)
    }

    /// 全ユーザーマーク (全 kind・解除済みの行も含む)。バックアップ用。
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

    /// entity 横断で kind に一致する、付いているマーク (`UserMark.meaningful`)。
    func fetchAllUserMarks(kind: UserMarkKind) throws -> [UserMark] {
        let rows = try dbQueue.read { db in
            try UserMark.filter(UserMark.Columns.kind == kind.rawValue).fetchAll(db)
        }
        return UserMark.meaningful(rows)
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

    /// 回収に配信参加も含めるユーザー設定 (既定=現地のみ)。地方勢など配信中心の人向け。
    static let collectionIncludeStreamKey = "collection_include_stream"
    private var collectionIncludeStream: Bool {
        UserDefaults.standard.bool(forKey: Self.collectionIncludeStreamKey)
    }
    /// 回収対象とするリアルライブの kind (歌枠/配信番組/リリイベ/ラジオ等は除外)。
    /// **どれが対象かは imas-core が持つ** (`collectionRealLiveKinds`)。ここは IN 句にするだけ。
    private static var realLiveKinds: String { sqlList(collectionRealLiveKinds()) }
    /// 催しがライブでも回収に数えない公演 (MV 上映会・配信だけのライブ)。これも imas-core が持つ。
    private static var excludedPerformerTypes: String { sqlList(nonPerformancePerformerTypes()) }
    private static var excludedVenueModes: String { sqlList(nonPerformanceVenueModes()) }

    /// 参加した公演の .attended 種別条件 (現地のみ / 設定により配信も)。
    /// **条件そのものを imas-core が組む** (`collectionAttendanceSqlCondition`)。
    /// 形態を持たない古いマーク (NULL) は現地扱い・1 公演に複数の形態 ("live,stream") も読む
    /// ので、core の `collection_attended_show_ids` と同じ集合を選ぶ。
    private var attendedTypeCondition: String {
        collectionAttendanceSqlCondition(includeStream: collectionIncludeStream)
    }

    /// 参加マークの entity_id を引く副問い合わせ。**回収を数える SQL はここを通す。**
    ///
    /// 参加形態の条件 (現地のみ / 配信も) を掛け忘れると「配信で見た」と記録した公演が
    /// 既定でも回収に数えられる。実際イベント側のマークで掛け忘れていたので、
    /// 条件ごとこの 1 箇所に畳んで、書き写しで落ちないようにする。
    private static func attendedIdsSubquery(
        _ entity: UserMarkEntity,
        _ attendedTypeCondition: String
    ) -> String {
        """
        SELECT entity_id FROM user_marks
        WHERE entity_type='\(entity.rawValue)' AND kind='attended' AND bool_value=1
          AND \(attendedTypeCondition)
        """
    }

    /// 文字列の並びを SQL のリテラル並びにする (値は core 由来の固定語だが、素通しにしない)。
    private static func sqlList(_ values: [String]) -> String {
        values
            .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
            .joined(separator: ",")
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
            AND COALESCE(sh.performer_type, '') NOT IN (\(Self.excludedPerformerTypes))
            AND COALESCE(sh.venue_mode, '') NOT IN (\(Self.excludedVenueModes))
            AND (
                sh.id IN (\(Self.attendedIdsSubquery(.show, attendedTypeCondition)))
                OR sh.event_id IN (\(Self.attendedIdsSubquery(.event, attendedTypeCondition)))
            )
            """
        let rows = try Row.fetchAll(db, sql: sql)
        return Set(rows.compactMap { row -> String? in row["song_id"] })
    }

}
