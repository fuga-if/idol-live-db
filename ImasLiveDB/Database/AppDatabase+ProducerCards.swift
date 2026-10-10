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
        var row = card.withCardId()
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
                var row = card.withCardId()
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

    /// 名刺をしまう。同じ人の名刺があれば 1 枚にまとめて中身を新しい方に替え、会った記録を積む
    /// (同じ機会にもう一度読んだときは最後の記録を新しい方に書き換える)。しまい方はコアの `cardReceivePlan`
    /// (中身が同じ・名刺 id と名前が同じなら黙って、名刺 id が同じで名前が違う・名前と担当が同じなら `choice` で)。
    /// 確かめる名刺を `.undecided` のまま渡すと別の名刺として足す (黙って中身を差し替えない)。
    /// `matchSamePerson: false` は QR の無い紙の名刺 (常に新しく足す)。探すのと書くのを 1 つの書き込みで行い、
    /// 同時に 2 回届いても 2 枚にしない。書いた後、名刺の行に最後の会った記録を写す。
    func receiveProducerCard(_ fresh: ReceivedProducerCard, matchSamePerson: Bool,
                             choice: CardSamePersonChoice = .undecided) async throws -> ReceivedProducerCard {
        try await dbQueue.write { db in
            let plan = cardReceivePlan(incoming: Self.incoming(fresh), stored: try Self.storedRefs(db),
                                       meetings: try ReceivedCardMeeting.fetchAll(db).map(\.record),
                                       matchSamePerson: matchSamePerson, choice: choice)
            var row = fresh
            if let existingId = plan.existingCardId, let existing = try ReceivedProducerCard.fetchOne(db, key: existingId) {
                row = existing
                row.payload = fresh.payload
                row.source = fresh.source
                row.updatedAt = fresh.updatedAt
                try row.update(db)
            } else {
                try row.insert(db)
            }
            if let update = plan.lastMeetingUpdate {
                try ReceivedCardMeeting(update).update(db)
            }
            if plan.addMeeting {
                let id = plan.existingCardId == nil ? cardFirstMeetingId(cardId: row.id) : UUID().uuidString
                try ReceivedCardMeeting(id: id, cardId: row.id, showId: fresh.showId, showDate: fresh.showDate,
                                        via: fresh.via, metAt: fresh.receivedAt, payload: fresh.payload).insert(db)
            }
            try Self.copyLatestMeeting(db, cardId: row.id)
            return try ReceivedProducerCard.fetchOne(db, key: row.id) ?? row
        }
    }

    /// 届いた名刺が、名刺入れのある名刺と同じ人か確かめる必要があれば、その確認の画面 (コアの `cardSamePersonConfirm`)。
    func receivedCardSamePersonConfirm(payload: String) async throws -> CardSamePersonConfirm? {
        try await dbQueue.read { db in
            let probe = ReceivedProducerCard.make(payload: payload, source: .app, showId: nil, showDate: nil)
            let plan = cardReceivePlan(incoming: Self.incoming(probe), stored: try Self.storedRefs(db),
                                       meetings: try ReceivedCardMeeting.fetchAll(db).map(\.record),
                                       matchSamePerson: true, choice: .undecided)
            guard let id = plan.confirmCardId, let existing = try ReceivedProducerCard.fetchOne(db, key: id) else {
                return nil
            }
            return cardSamePersonConfirm(existingPayload: existing.payload, incomingPayload: payload)
        }
    }

    /// 詳細の「この時の名刺に戻す」: 名刺の中身を会った記録のときの中身に戻す (戻せるかはコアの `cardMeetingRestorable`)。
    /// 写真・担当の画像は今のまま。
    func restoreReceivedCardPayload(cardId: String, meetingId: String) async throws {
        try await dbQueue.write { db in
            guard var row = try ReceivedProducerCard.fetchOne(db, key: cardId),
                  let meeting = try ReceivedCardMeeting.fetchOne(db, key: meetingId), meeting.cardId == cardId,
                  cardMeetingRestorable(meetingPayload: meeting.payload, currentPayload: row.payload),
                  let payload = meeting.payload else { return }
            row.payload = payload
            row.updatedAt = ISO8601DateFormatter.shared.string(from: Date())
            try row.update(db)
        }
    }

    private static func incoming(_ card: ReceivedProducerCard) -> CardIncoming {
        CardIncoming(payload: card.payload, showId: card.showId, showDate: card.showDate, via: card.receiveVia,
                     metAt: card.receivedAt)
    }

    private static func storedRefs(_ db: Database) throws -> [CardStoredRef] {
        try Row.fetchAll(db, sql: "SELECT id, payload FROM received_producer_cards")
            .map { CardStoredRef(id: $0["id"], payload: $0["payload"]) }
    }

    /// 名刺の行に最後の会った記録 (コアの `cardLatestMeeting`) の公演・受け取り方・日時・中身を写す。
    private static func copyLatestMeeting(_ db: Database, cardId: String) throws {
        guard var row = try ReceivedProducerCard.fetchOne(db, key: cardId) else { return }
        let meetings = try ReceivedCardMeeting.filter(ReceivedCardMeeting.Columns.cardId == cardId).fetchAll(db)
        guard let latest = cardLatestMeeting(meetings: meetings.map(\.record), cardId: cardId) else { return }
        let before = row
        row.showId = latest.showId
        row.showDate = latest.showDate
        row.via = latest.via
        row.receivedAt = latest.metAt
        if let payload = latest.payload { row.payload = payload }
        if row != before { try row.update(db) }
    }

    /// 名刺の会った記録 (並びは問わない。並べ方・何回目かはコアの `cardMeetingViews`)。`cardId` が nil なら全部。
    func receivedCardMeetingsAsync(cardId: String? = nil) async throws -> [ReceivedCardMeeting] {
        try await dbQueue.read { db in
            if let cardId {
                return try ReceivedCardMeeting.filter(ReceivedCardMeeting.Columns.cardId == cardId).fetchAll(db)
            }
            return try ReceivedCardMeeting.fetchAll(db)
        }
    }

    func allReceivedCardMeetings() throws -> [ReceivedCardMeeting] {
        try dbQueue.read { db in try ReceivedCardMeeting.fetchAll(db) }
    }

    /// 最後に会った記録の公演を変え、名刺の行にも写す (詳細の「受け取った公演を変える」)。
    func changeLatestMeetingShow(cardId: String, showId: String?, showDate: String?) async throws {
        try await dbQueue.write { db in
            guard var row = try ReceivedProducerCard.fetchOne(db, key: cardId) else { return }
            // 最後の記録はコアの `cardLatestMeeting` と同じ並び (日時、同じ時刻は id の大きい方)。
            let latest = try ReceivedCardMeeting
                .filter(ReceivedCardMeeting.Columns.cardId == cardId)
                .order(ReceivedCardMeeting.Columns.metAt.desc, ReceivedCardMeeting.Columns.id.desc)
                .fetchOne(db)
            if var latest {
                latest.showId = showId
                latest.showDate = showDate
                try latest.update(db)
            } else {
                try ReceivedCardMeeting(id: cardFirstMeetingId(cardId: cardId), cardId: cardId, showId: showId,
                                        showDate: showDate, via: row.via, metAt: row.receivedAt,
                                        payload: row.payload).insert(db)
            }
            row.showId = showId
            row.showDate = showDate
            row.updatedAt = ISO8601DateFormatter.shared.string(from: Date())
            try row.update(db)
        }
    }

    /// バックアップからの非破壊復元: 無い id の会った記録だけ足す (名刺が端末に無い記録は飛ばす)。
    /// 中身が同じ別 id の名刺の記録は、コアの計画 (`planBackupImport`) で端末の名刺に付け替えてある。
    /// 足した名刺の行には最後の会った記録を写す。
    @discardableResult
    func restoreReceivedCardMeetingsIfAbsent(_ meetings: [ReceivedCardMeeting]) throws -> Int {
        try dbQueue.write { db in
            var inserted = 0
            var touched: Set<String> = []
            for meeting in meetings {
                guard try ReceivedCardMeeting.fetchOne(db, key: meeting.id) == nil,
                      try ReceivedProducerCard.fetchOne(db, key: meeting.cardId) != nil else { continue }
                try meeting.insert(db)
                touched.insert(meeting.cardId)
                inserted += 1
            }
            for cardId in touched { try Self.copyLatestMeeting(db, cardId: cardId) }
            return inserted
        }
    }

    /// バックアップの取り込みの材料 (名刺の id と中身)。
    func allReceivedCardRefs() throws -> [CardStoredRef] {
        try dbQueue.read { db in try Self.storedRefs(db) }
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
