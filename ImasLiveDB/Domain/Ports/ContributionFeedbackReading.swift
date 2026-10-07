import Foundation

/// データを入れた人への手応え (自分の編集に付いた Good・自分が入れたセトリの閲覧数) と、
/// 公演ページの奥付 (クレジット) のポート。
///
/// 対象はアプリからの編集 (セトリ・歌唱者・公演・曲など) だけ。歌詞の投稿は別の口
/// (`LyricSubmissionAPI`) でサーバの別の表に入るので、ここを通るどのデータにも出ない。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol ContributionFeedbackReading: Sendable {
    /// `GET /me/feedback?since=`。要ログイン。`since` (epoch ミリ秒) より後の Good を新着として数える。
    func myFeedback(since: Int64) async throws -> ContributionFeedback
    /// `POST /shows/views`。端末 ID で送る (ログイン不要)。1 端末 1 週 1 公演 1 回に畳んでから呼ぶ。
    func reportShowViews(showIds: [String]) async throws
    /// `GET /shows/:id/credits`。ログイン不要・エッジで 1 時間共有される。
    func showCredits(showId: String) async throws -> ShowCredits
    /// `POST /users/me/credit`。奥付に表示名を載せるか。
    func setCreditOptIn(_ isOn: Bool) async throws -> Bool
}

// MARK: - DTO

/// `GET /me/feedback` の応答。
struct ContributionFeedback: Decodable, Sendable, Equatable {
    /// Good が付いた自分の編集 (最後に Good が付いた順。サーバ上限 20 件)。
    let goods: [ReceivedGood]
    /// `since` より後に付いた Good の合計。
    let newGoodTotal: Int
    /// 自分が入れたセトリの公演が、先週 (JST の月曜始まり) 見られた数。
    let setlistReach: SetlistReach
}

/// Good が付いた自分の編集 1 件。
struct ReceivedGood: Decodable, Sendable, Equatable, Identifiable {
    let batchId: Int
    let summary: String?
    let recordType: String?
    let recordName: String?
    let goodCount: Int
    let newGoodCount: Int
    /// 最後に Good が付いた時刻 (epoch ミリ秒)。
    let latestGoodAt: Int64

    var id: Int { batchId }

    /// 既読にした写し (新着の数だけ 0)。
    func seen() -> ReceivedGood {
        ReceivedGood(batchId: batchId, summary: summary, recordType: recordType, recordName: recordName,
                     goodCount: goodCount, newGoodCount: 0, latestGoodAt: latestGoodAt)
    }
}

/// 自分が入れたセトリの先週の閲覧数。
struct SetlistReach: Decodable, Sendable, Equatable {
    /// 週の初日 (`yyyy-MM-dd`)。
    let week: String
    /// 見た人の数の合計 (公演ごとに 1 端末 1 回。複数の公演を見た人はその数だけ数える)。
    let viewers: Int
    /// 見られた公演の数。
    let shows: Int
}

/// `GET /shows/:id/credits` の応答。名前は本人が載せると選んだ人だけ。
struct ShowCredits: Decodable, Sendable, Equatable {
    struct Role: Decodable, Sendable, Equatable {
        let names: [String]
        let total: Int
    }
    let showId: String
    let setlist: Role
    let performers: Role
}
