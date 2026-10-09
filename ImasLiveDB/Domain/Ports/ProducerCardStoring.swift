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
    /// 名刺をしまう。同じ人の名刺があれば 1 枚にまとめて中身を新しい方に替え、会った記録を積む
    /// (しまい方はコアの `cardReceivePlan`。探すのと書くのは 1 つの書き込み)。同じ人か確かめる名刺は `choice` で
    /// (`.undecided` なら別の名刺として足す)。
    func receive(_ card: ReceivedProducerCard, matchSamePerson: Bool,
                 choice: CardSamePersonChoice) async throws -> ReceivedProducerCard
    /// 届いた名刺が名刺入れのある名刺と同じ人か確かめる必要があれば、その確認の画面 (コアの `cardSamePersonConfirm`)。
    func samePersonConfirm(payload: String) async throws -> CardSamePersonConfirm?
    /// 名刺の中身を会った記録のときの中身に戻す (詳細の「この時の名刺に戻す」)。
    func restorePayload(cardId: String, meetingId: String) async throws
    /// 会った記録 (`cardId` が nil なら全部)。
    func meetings(cardId: String?) async throws -> [ReceivedCardMeeting]
    /// 最後に会った記録の公演を変える (名刺の行にも写す)。
    func changeLatestMeetingShow(cardId: String, showId: String?, showDate: String?) async throws
    /// 同じ id があれば上書きし、無ければ足す。
    func saveReceived(_ card: ReceivedProducerCard) async throws
    func deleteReceived(id: String) async throws
    func receivedCount() async throws -> Int

    /// 公演 id → 表記・日付・会場 (受け取った公演・共通点・次の現場の表示用)。
    func showInfos(ids: [String]) async throws -> [String: ProducerCardShowInfo]
    /// 参加を付けた公演 (今後の参加予定も含む) の id と日付。名刺の記録と共通点の材料。
    func attendedShowRefs() async throws -> [CardShowRef]
}
