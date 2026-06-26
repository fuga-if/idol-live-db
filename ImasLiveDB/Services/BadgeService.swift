import Foundation
import Observation

// MARK: - Result type

enum BadgeFetchResult: Sendable {
    case loading
    case success(UserBadges)
    case failure(Error)
}

// MARK: - BadgeAPIError (alias for compatibility)

typealias BadgeAPIError = APIClientError

@MainActor
@Observable
final class BadgeService {
    static let shared = BadgeService()

    private var cache: [String: (badges: UserBadges, fetchedAt: Date)] = [:]
    private let cacheDuration: TimeInterval = 300 // 5 minutes

    private init() {}

    // MARK: - Fetch by User ID

    func fetchBadges(userId: String, forceReload: Bool = false) async throws -> UserBadges {
        if !forceReload,
           let entry = cache[userId],
           Date().timeIntervalSince(entry.fetchedAt) < cacheDuration {
            return entry.badges
        }

        let badges: UserBadges = try await APIClient.shared.request(
            "GET",
            path: "/users/\(userId)/badges",
            authorized: true
        )
        cache[userId] = (badges, Date())
        return badges
    }

    /// ローディング/成功/失敗の3状態で返す非throws版。UI の skeleton 切替に使う。
    func fetchBadgesResult(userId: String, forceReload: Bool = false) async -> BadgeFetchResult {
        do {
            let badges = try await fetchBadges(userId: userId, forceReload: forceReload)
            return .success(badges)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Current User

    func currentUserBadges(forceReload: Bool = false) async -> UserBadges? {
        guard let userId = AuthService.shared.userId else { return nil }
        return try? await fetchBadges(userId: userId, forceReload: forceReload)
    }

    // MARK: - Cache Invalidation

    func invalidate(userId: String) {
        cache.removeValue(forKey: userId)
    }

    func invalidateAll() {
        cache.removeAll()
    }
}
