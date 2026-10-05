import Foundation

/// `ProducerCardStoring` の端末 DB アダプタ。名刺は端末にしか無い。
struct GRDBProducerCardRepository: ProducerCardStoring {
    let database: AppDatabase

    func myCard() async throws -> MyProducerCard? { try await database.myProducerCardAsync() }
    func saveMyCard(_ card: MyProducerCard) async throws { try database.saveMyProducerCard(card) }

    func receivedCards() async throws -> [ReceivedProducerCard] { try await database.receivedProducerCardsAsync() }
    func receivedCard(id: String) async throws -> ReceivedProducerCard? {
        try await database.receivedProducerCardAsync(id: id)
    }
    func receivedCard(payload: String) async throws -> ReceivedProducerCard? {
        try await database.receivedProducerCardAsync(payload: payload)
    }
    func saveReceived(_ card: ReceivedProducerCard) async throws { try database.saveReceivedProducerCard(card) }
    func deleteReceived(id: String) async throws { try database.deleteReceivedProducerCard(id: id) }
    func receivedCount() async throws -> Int { try await database.receivedProducerCardCountAsync() }

    func showInfos(ids: [String]) async throws -> [String: ProducerCardShowInfo] {
        try await database.producerCardShowInfosAsync(ids: ids)
    }
    func attendedShowRefs() async throws -> [CardShowRef] {
        try await database.attendedShowOptionsAsync().map { CardShowRef(showId: $0.id, date: $0.date) }
    }
}
