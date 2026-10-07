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
