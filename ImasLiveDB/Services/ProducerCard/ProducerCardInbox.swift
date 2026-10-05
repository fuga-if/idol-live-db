import Foundation
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "producer_card")

extension Notification.Name {
    /// 名刺入れが変わった (受け取った・消した・メモを書いた)。名刺入れの画面と数の札が読み直す。
    static let producerCardsChanged = Notification.Name("producerCardsChanged")
}

/// 受け取った名刺を名刺入れにしまう。入口 (QR・リンク・名刺ファイル・近くの端末) が
/// 複数あるので、しまい方はここ 1 か所にまとめる。
@MainActor
enum ProducerCardInbox {
    /// 受け取った公演の候補 (今日 → 昨日の参加公演)。先頭が既定。選び方はコア。
    static func exchangeShowCandidates(record: ProducerCardMyRecord) -> [String] {
        cardExchangeShowCandidates(today: JSTDay.today(), myAttended: record.attended)
    }

    /// 名刺をしまう。同じ中身の名刺が既にあれば新しく足さず、その名刺に画像だけ足して返す
    /// (同じ相手の QR を 2 回読んでも 2 枚にしない)。`dedupe: false` は QR の無い紙の名刺
    /// (名前だけで中身を作るので、同じ名前の別人と重ならないように常に新しく足す)。
    /// 画像を書けなくても名刺はしまえているので、失敗は記録だけにする。
    @discardableResult
    static func store(payload: String, images: [CardFileImage], source: ReceivedProducerCard.Source,
                      show: ProducerCardShowInfo?, dedupe: Bool = true) async throws -> ReceivedProducerCard {
        let store = AppContainer.shared.producerCards
        let fresh = ReceivedProducerCard.make(payload: payload, source: source,
                                              showId: show?.id, showDate: show?.date)
        let saved: ReceivedProducerCard
        if dedupe {
            saved = try await store.insertReceivedIfNew(fresh)
        } else {
            try await store.saveReceived(fresh)
            saved = fresh
        }
        attachImages(cardId: saved.id, images: images)
        NotificationCenter.default.post(name: .producerCardsChanged, object: nil)
        return saved
    }

    /// 後から届いた担当の画像を、しまった名刺に足す。
    static func attachImages(cardId: String, images: [CardFileImage]) {
        guard !images.isEmpty else { return }
        do {
            try ProducerCardFiles.saveOshiImages(cardId: cardId, images: images)
        } catch {
            logger.error("producer_card_image_save_failed: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: .producerCardsChanged, object: nil)
    }

    static func delete(_ card: ReceivedProducerCard) async throws {
        try await AppContainer.shared.producerCards.deleteReceived(id: card.id)
        ProducerCardFiles.deleteAll(cardId: card.id)
        NotificationCenter.default.post(name: .producerCardsChanged, object: nil)
    }

    static func update(_ card: ReceivedProducerCard) async throws {
        try await AppContainer.shared.producerCards.saveReceived(card)
        NotificationCenter.default.post(name: .producerCardsChanged, object: nil)
    }
}
