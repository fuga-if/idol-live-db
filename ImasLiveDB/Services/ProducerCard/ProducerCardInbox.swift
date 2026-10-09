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

    /// 名刺をしまう。同じ人の名刺 (名刺 id が同じ、無ければ中身が同じ) が既にあれば新しく足さず、1 枚にまとめて
    /// 中身を新しい方に替え、会った記録を積む (同じ相手の QR を同じ公演で 2 回読んでも記録は 1 つ)。
    /// 届いた画像 (写真・担当の画像) は新しいものに差し替える。`dedupe: false` は QR の無い紙の名刺
    /// (名前だけで中身を作るので、同じ名前の別人と重ならないように常に新しく足す)。
    /// 画像を書けなくても名刺はしまえているので、失敗は記録だけにする。
    @discardableResult
    static func store(payload: String, images: [CardFileImage], source: ReceivedProducerCard.Source,
                      via: CardReceiveVia, show: ProducerCardShowInfo?,
                      dedupe: Bool = true) async throws -> ReceivedProducerCard {
        let store = AppContainer.shared.producerCards
        let fresh = ReceivedProducerCard.make(payload: payload, source: source,
                                              showId: show?.id, showDate: show?.date, via: via)
        let saved = try await store.receive(fresh, matchSamePerson: dedupe)
        attachImages(cardId: saved.id, images: images)
        NotificationCenter.default.post(name: .producerCardsChanged, object: nil)
        return saved
    }

    /// 後から届いた画像 (担当の画像・名刺の写真) を、しまった名刺に足す。
    static func attachImages(cardId: String, images: [CardFileImage]) {
        guard !images.isEmpty else { return }
        do {
            try ProducerCardFiles.saveImages(cardId: cardId, images: images)
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
