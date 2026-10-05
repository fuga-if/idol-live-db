import Foundation

/// P名刺 (自分の名刺と名刺入れ) の読み書きポート (driven port)。
///
/// 名刺は端末にしか無い (クラウドにもサーバにも上げない)。実装は端末の DB
/// (`Adapters/Persistence/GRDBProducerCardRepository`)。名刺の組み立て・共通点・束ね方はコア。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol ProducerCardStoring: Sendable {
    /// 自分の名刺。まだ作っていなければ nil。
    func myCard() async throws -> MyProducerCard?
    func saveMyCard(_ card: MyProducerCard) async throws

    /// 受け取った名刺 (新しく受け取った順)。
    func receivedCards() async throws -> [ReceivedProducerCard]
    func receivedCard(id: String) async throws -> ReceivedProducerCard?
    /// 同じ中身の名刺が既にあればそれを返す (同じ相手を 2 回読んでも 2 枚にしない)。
    func receivedCard(payload: String) async throws -> ReceivedProducerCard?
    /// 同じ中身の名刺が無ければ足し、あればそれを返す (探すのと足すのは 1 つの書き込み)。
    func insertReceivedIfNew(_ card: ReceivedProducerCard) async throws -> ReceivedProducerCard
    /// 同じ id があれば上書きし、無ければ足す。
    func saveReceived(_ card: ReceivedProducerCard) async throws
    func deleteReceived(id: String) async throws
    func receivedCount() async throws -> Int

    /// 公演 id → 表記・日付・会場 (受け取った公演・共通点・次の現場の表示用)。
    func showInfos(ids: [String]) async throws -> [String: ProducerCardShowInfo]
    /// 参加を付けた公演 (今後の参加予定も含む) の id と日付。名刺の記録と共通点の材料。
    func attendedShowRefs() async throws -> [CardShowRef]
}
