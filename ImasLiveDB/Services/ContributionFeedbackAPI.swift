import Foundation

/// 手応えと公演の奥付の API クライアント (`ContributionFeedbackReading` の実装)。
actor ContributionFeedbackAPI: ContributionFeedbackReading {
    static let shared = ContributionFeedbackAPI()
    private init() {}

    func myFeedback(since: Int64) async throws -> ContributionFeedback {
        try await APIClient.shared.request(
            "GET", path: "/me/feedback", query: ["since": String(since)], authorized: true
        )
    }

    private struct ShowViewsBody: Encodable { let showIds: [String] }

    func reportShowViews(showIds: [String]) async throws {
        try await APIClient.shared.requestVoid("POST", path: "/shows/views", body: ShowViewsBody(showIds: showIds))
    }

    func showCredits(showId: String) async throws -> ShowCredits {
        try await APIClient.shared.request("GET", path: "/shows/\(showId)/credits")
    }

    private struct CreditBody: Encodable { let creditOptIn: Bool }
    private struct CreditResponse: Decodable { let creditOptIn: Bool }

    func setCreditOptIn(_ isOn: Bool) async throws -> Bool {
        let res: CreditResponse = try await APIClient.shared.request(
            "POST", path: "/users/me/credit", body: CreditBody(creditOptIn: isOn), authorized: true
        )
        return res.creditOptIn
    }
}

#if DEBUG
/// `FAKE_FEEDBACK=1` のときの見本 (Worker やログイン無しで画面を確かめる)。
struct FakeContributionFeedbackReading: ContributionFeedbackReading {
    func myFeedback(since: Int64) async throws -> ContributionFeedback {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return ContributionFeedback(
            goods: [
                ReceivedGood(batchId: 2, summary: "セトリを編集 (24 件)", recordType: "SetlistItem", recordName: nil,
                             goodCount: 5, newGoodCount: 3, latestGoodAt: now - 3_600_000),
                ReceivedGood(batchId: 1, summary: "チケット受付を追加", recordType: "TicketSale", recordName: nil,
                             goodCount: 2, newGoodCount: 0, latestGoodAt: now - 86_400_000 * 3),
            ],
            newGoodTotal: 3,
            setlistReach: SetlistReach(week: "2026-09-28", viewers: 128, shows: 4)
        )
    }
    func reportShowViews(showIds: [String]) async throws {}
    func showCredits(showId: String) async throws -> ShowCredits {
        ShowCredits(showId: showId,
                    setlist: .init(names: ["ふが", "ゆきほP"], total: 4),
                    performers: .init(names: ["ふが"], total: 1))
    }
    func setCreditOptIn(_ isOn: Bool) async throws -> Bool { isOn }
}
#endif
