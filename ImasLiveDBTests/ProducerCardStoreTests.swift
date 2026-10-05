import GRDB
import XCTest
@testable import ImasLiveDB

/// P名刺 (自分の名刺・名刺入れ) の端末 DB とバックアップの往復のテスト。
///
/// 名刺は端末にしか無いので、復元は「無い行を足すだけ」で、既にある名刺のメモや
/// 書き直した自分の名刺を古いもので上書きしないこと。
@MainActor
final class ProducerCardStoreTests: XCTestCase {

    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(dbQueue: makeMigratedDatabase())
    }

    /// コアで組んだ本物の名刺の中身。
    private func payload(name: String) -> String {
        let input = ProducerCardInput(
            name: name, message: "", sinceYear: 2014, oshiIdolIds: ["765_haruka"],
            links: [CardLink(kind: .x, value: "fuga_p")], showCount: 3, songCount: 10,
            nextShowId: nil, attended: [], issuedOn: "2026-10-06")
        return producerCardPayload(card: encodeProducerCard(input: input).card)
    }

    private func received(_ id: String, name: String, memo: String? = nil) -> ReceivedProducerCard {
        ReceivedProducerCard(id: id, payload: payload(name: name), source: "app", showId: "sh_1",
                             showDate: "2026-10-05", memo: memo, receivedAt: "2026-10-05T21:00:00Z",
                             updatedAt: "2026-10-05T21:00:00Z")
    }

    func testMyCardRoundTripsLinksAndHiddenFields() throws {
        let db = try makeDatabase()
        XCTAssertNil(try db.myProducerCard())
        var card = MyProducerCard.empty()
        card.name = "ふがP"
        card.sinceYear = 2014
        card.links = [CardLink(kind: .x, value: "fuga_p"), CardLink(kind: .bluesky, value: "fuga.bsky.social")]
        card.hidden = [.attended, .songCount]
        try db.saveMyProducerCard(card)

        let loaded = try XCTUnwrap(db.myProducerCard())
        XCTAssertEqual(loaded.name, "ふがP")
        XCTAssertEqual(loaded.links, card.links)
        XCTAssertEqual(loaded.hidden, [.attended, .songCount])
        XCTAssertTrue(loaded.shows(.oshi))
        XCTAssertFalse(loaded.shows(.attended))
    }

    func testReceivedCardsSaveFindByPayloadAndDelete() async throws {
        let db = try makeDatabase()
        let a = received("c1", name: "しろくまP")
        try db.saveReceivedProducerCard(a)
        try db.saveReceivedProducerCard(received("c2", name: "あおいP"))

        XCTAssertEqual(try db.allReceivedProducerCards().count, 2)
        let found = try await db.receivedProducerCardAsync(payload: a.payload)
        XCTAssertEqual(found?.id, "c1")
        XCTAssertEqual(found?.card?.name, "しろくまP")

        var edited = a
        edited.memo = "物販列で隣"
        try db.saveReceivedProducerCard(edited)
        XCTAssertEqual(try db.allReceivedProducerCards().count, 2, "同じ id は上書き")

        try db.deleteReceivedProducerCard(id: "c1")
        XCTAssertEqual(try db.allReceivedProducerCardIds(), ["c2"])
    }

    func testRestoreAddsOnlyMissingCardsAndKeepsMyCard() throws {
        let db = try makeDatabase()
        try db.saveReceivedProducerCard(received("c1", name: "しろくまP", memo: "新しいメモ"))
        let added = try db.restoreReceivedProducerCardsIfAbsent([
            received("c1", name: "しろくまP", memo: "古いメモ"),
            received("c2", name: "あおいP"),
        ])
        XCTAssertEqual(added, 1)
        let memos = Dictionary(uniqueKeysWithValues: try db.allReceivedProducerCards().map { ($0.id, $0.memo) })
        XCTAssertEqual(memos["c1"], "新しいメモ", "既にある名刺のメモを古いもので上書きしない")

        var mine = MyProducerCard.empty()
        mine.name = "書き直した名前"
        try db.saveMyProducerCard(mine)
        var old = MyProducerCard.empty()
        old.name = "古い名前"
        XCTAssertEqual(try db.restoreMyProducerCardsIfAbsent([old]), 0)
        XCTAssertEqual(try db.myProducerCard()?.name, "書き直した名前")
    }

    /// 書き出したバックアップを空の端末に取り込むと、名刺入れと自分の名刺が戻る。
    func testBackupRoundTripRestoresProducerCards() throws {
        let source = try makeDatabase()
        var mine = MyProducerCard.empty()
        mine.name = "ふがP"
        mine.message = "現地派"
        mine.sinceYear = 2014
        mine.links = [CardLink(kind: .x, value: "fuga_p")]
        mine.hidden = [.attended]
        try source.saveMyProducerCard(mine)
        try source.saveReceivedProducerCard(received("c1", name: "しろくまP", memo: "物販列で隣"))

        let json = try BackupExportImportService.buildEnvelopeJSON(database: source)

        let target = try makeDatabase()
        let result = try BackupExportImportService.importEnvelopeJSON(json, database: target, restoreDeviceId: false)
        XCTAssertEqual(result.addedProducerCards, 1)
        let card = try XCTUnwrap(target.allReceivedProducerCards().first)
        XCTAssertEqual(card.id, "c1")
        XCTAssertEqual(card.memo, "物販列で隣")
        XCTAssertEqual(card.card?.name, "しろくまP")
        let restored = try XCTUnwrap(target.myProducerCard())
        XCTAssertEqual(restored.name, "ふがP")
        XCTAssertEqual(restored.sinceYear, 2014)
        XCTAssertEqual(restored.links, mine.links)
        XCTAssertEqual(restored.hidden, [.attended])

        // 2 回目は何も増えない (id で重複を弾く)。
        let again = try BackupExportImportService.importEnvelopeJSON(json, database: target, restoreDeviceId: false)
        XCTAssertEqual(again.addedProducerCards, 0)
        XCTAssertEqual(try target.allReceivedProducerCards().count, 1)
    }

    /// 名刺のリンク・名刺ファイルの判定はコアの規則で、Deeplink に載る。
    func testDeeplinkParsesCardUrlsAndFiles() throws {
        let p = payload(name: "ふがP")
        let https = try XCTUnwrap(URL(string: producerCardUrlFromPayload(payload: p)))
        XCTAssertEqual(DeeplinkRouter.parse(https), .producerCard(payload: p))
        let custom = try XCTUnwrap(URL(string: "imaslivedb://p#\(p)"))
        XCTAssertEqual(DeeplinkRouter.parse(custom), .producerCard(payload: p))
        let file = URL(fileURLWithPath: "/tmp/ふがPのP名刺.imascard")
        XCTAssertEqual(DeeplinkRouter.parse(file), .producerCardFile(file))
        XCTAssertNil(DeeplinkRouter.parse(URL(fileURLWithPath: "/tmp/a.json")))
    }
}
