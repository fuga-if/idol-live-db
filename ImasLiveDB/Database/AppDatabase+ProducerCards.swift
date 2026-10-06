//  P名刺 (自分の名刺・名刺入れ) の読み書き。**端末ローカル唯一データ**なので、
//  user_marks / expenses と同じく破壊的な移行はしない。
//
//  名刺の組み立て・共通点・束ね方は共有コア (domain/producer_card.rs)。ここは行の出し入れだけ。

import Foundation
import GRDB

extension AppDatabase {

    // MARK: 自分の名刺

    func myProducerCard() throws -> MyProducerCard? {
        try dbQueue.read { db in try MyProducerCard.fetchOne(db, key: MyProducerCard.singletonId) }
    }

    func myProducerCardAsync() async throws -> MyProducerCard? {
        try await dbQueue.read { db in try MyProducerCard.fetchOne(db, key: MyProducerCard.singletonId) }
    }

    func saveMyProducerCard(_ card: MyProducerCard) throws {
        var row = card
        row.id = MyProducerCard.singletonId
        row.updatedAt = ISO8601DateFormatter.shared.string(from: Date())
        try dbQueue.write { db in try row.save(db) }
    }

    /// バックアップからの非破壊復元: 端末に自分の名刺が無いときだけ入れる。
    @discardableResult
    func restoreMyProducerCardsIfAbsent(_ cards: [MyProducerCard]) throws -> Int {
        try dbQueue.write { db in
            var inserted = 0
            for card in cards {
                guard try MyProducerCard.fetchCount(db) == 0 else { break }
                var row = card
                row.id = MyProducerCard.singletonId
                try row.insert(db)
                inserted += 1
            }
            return inserted
        }
    }

    // MARK: 名刺入れ

    func allReceivedProducerCards() throws -> [ReceivedProducerCard] {
        try dbQueue.read(Self.receivedQuery)
    }

    func receivedProducerCardsAsync() async throws -> [ReceivedProducerCard] {
        try await dbQueue.read(Self.receivedQuery)
    }

    private static func receivedQuery(_ db: Database) throws -> [ReceivedProducerCard] {
        try ReceivedProducerCard
            .order(ReceivedProducerCard.Columns.receivedAt.desc, ReceivedProducerCard.Columns.id)
            .fetchAll(db)
    }

    func receivedProducerCardAsync(id: String) async throws -> ReceivedProducerCard? {
        try await dbQueue.read { db in try ReceivedProducerCard.fetchOne(db, key: id) }
    }

    func receivedProducerCardAsync(payload: String) async throws -> ReceivedProducerCard? {
        try await dbQueue.read { db in
            try ReceivedProducerCard.filter(ReceivedProducerCard.Columns.payload == payload).fetchOne(db)
        }
    }

    func receivedProducerCardCountAsync() async throws -> Int {
        try await dbQueue.read { db in try ReceivedProducerCard.fetchCount(db) }
    }

    func saveReceivedProducerCard(_ card: ReceivedProducerCard) throws {
        var row = card
        row.updatedAt = ISO8601DateFormatter.shared.string(from: Date())
        try dbQueue.write { db in try row.save(db) }
    }

    /// 同じ中身の名刺が無ければ入れる。あればそれを返す (探すのと入れるのを 1 つの書き込みで行い、
    /// 同時に 2 回届いても 2 枚にしない)。
    func insertReceivedProducerCardIfNew(_ card: ReceivedProducerCard) async throws -> ReceivedProducerCard {
        try await dbQueue.write { db in
            if let existing = try ReceivedProducerCard
                .filter(ReceivedProducerCard.Columns.payload == card.payload).fetchOne(db) {
                return existing
            }
            try card.insert(db)
            return card
        }
    }

    func deleteReceivedProducerCard(id: String) throws {
        _ = try dbQueue.write { db in try ReceivedProducerCard.deleteOne(db, key: id) }
    }

    /// バックアップ用の id 一覧 (重複判定はコアが id で行う)。
    func allReceivedProducerCardIds() throws -> [String] {
        try dbQueue.read { db in try String.fetchAll(db, sql: "SELECT id FROM received_producer_cards") }
    }

    /// バックアップからの非破壊復元: ローカルに無い id の行だけ追加する (メモを古いもので上書きしない)。
    @discardableResult
    func restoreReceivedProducerCardsIfAbsent(_ cards: [ReceivedProducerCard]) throws -> Int {
        try dbQueue.write { db in
            var inserted = 0
            for card in cards {
                // id が同じもの、または同じ相手の名刺 (中身が同じ) が既にあれば入れない
                // (機種変の前後で同じ相手から受け取っていても 2 枚にしない)。
                guard try ReceivedProducerCard.fetchOne(db, key: card.id) == nil,
                      try ReceivedProducerCard.filter(ReceivedProducerCard.Columns.payload == card.payload)
                        .fetchCount(db) == 0 else { continue }
                try card.insert(db)
                inserted += 1
            }
            return inserted
        }
    }

    // MARK: 公演の表記

    /// 公演 id → 表記・日付・会場。表記はコアの `showDisplayTitle` 一本。
    /// 端末のマスタに無い公演 (相手の方が新しいデータを持っていた等) は返さない。
    func producerCardShowInfosAsync(ids: [String]) async throws -> [String: ProducerCardShowInfo] {
        let unique = Array(Set(ids.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return [:] }
        return try await dbQueue.read { db in
            let placeholders = databaseQuestionMarks(count: unique.count)
            let sql = """
                SELECT s.id AS show_id, s.event_id AS event_id, s.name AS show_name, s.date AS date,
                       s.venue AS venue, e.name AS event_name, e.brand_id AS brand_id
                FROM shows s JOIN events e ON e.id = s.event_id
                WHERE s.id IN (\(placeholders))
                """
            var out: [String: ProducerCardShowInfo] = [:]
            for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(unique)) {
                let date: String = row["date"] ?? ""
                let info = ProducerCardShowInfo(
                    id: row["show_id"],
                    eventId: row["event_id"],
                    date: date,
                    label: showDisplayTitle(eventName: row["event_name"] ?? "",
                                            showName: row["show_name"] ?? "", date: date),
                    venue: row["venue"],
                    brandId: row["brand_id"]
                )
                out[info.id] = info
            }
            return out
        }
    }
}
