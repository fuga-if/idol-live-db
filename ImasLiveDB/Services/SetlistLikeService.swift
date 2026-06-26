import Foundation

/// 公演 (show) ごとの「この曲良かった」 like 状態をサーバから取得 + 投票するクライアント。
/// star toggle なので idempotent: 多重 POST しても 1 票、 DELETE は 0 票まで。
@Observable @MainActor
final class SetlistLikeService {
    static let shared = SetlistLikeService()
    private init() {}

    struct LikeEntry: Codable, Sendable {
        let songId: String
        let likeCount: Int
        let hasUserLiked: Bool
    }

    struct LikeResult: Codable, Sendable {
        let songId: String
        let likeCount: Int
        let liked: Bool
    }

    /// 公演ごとの like 集計 (/shows/:id/likes) の TTL キャッシュ。show_id 単位。
    /// レスポンスは has_user_liked (自分の like か) を含む **ユーザー固有** データなので、
    /// エッジ/CDN の共有キャッシュには絶対載せない (backend も public を付けない)。
    /// per-device のメモリキャッシュのみ。同じ公演のセトリを開き直すたびに叩くのを抑える。
    /// like 数は他人の操作でも増減するので TTL は短め (60s)。
    /// 自分の like/unlike は該当 song のエントリをその場で patch して整合を保つ。
    private var likesCache: [String: (entries: [LikeEntry], at: Date)] = [:]
    private let likesCacheTTL: TimeInterval = 60

    func fetch(showId: String) async throws -> [LikeEntry] {
        if let hit = likesCache[showId], Date().timeIntervalSince(hit.at) < likesCacheTTL {
            return hit.entries
        }
        let entries: [LikeEntry] = try await APIClient.shared.request(
            "GET",
            path: "/shows/\(showId)/likes",
            authorized: true
        )
        likesCache[showId] = (entries, Date())
        return entries
    }

    // bearerToken の事前チェックはしない。期限切れ (nil) でも isSignedIn は true のまま
    // 残ることがあり、ここで弾くと APIClient の 401 自動リフレッシュに乗らず Good が無言で
    // 失敗する (セトリ予想と同じ症状)。authorized: true で送れば未トークン→401→refresh→retry。
    func like(showId: String, songId: String) async throws -> LikeResult {
        let result: LikeResult = try await APIClient.shared.request(
            "POST",
            path: "/shows/\(showId)/songs/\(songId)/like",
            authorized: true
        )
        applyLikeResult(showId: showId, result: result)
        return result
    }

    func unlike(showId: String, songId: String) async throws -> LikeResult {
        let result: LikeResult = try await APIClient.shared.request(
            "DELETE",
            path: "/shows/\(showId)/songs/\(songId)/like",
            authorized: true
        )
        applyLikeResult(showId: showId, result: result)
        return result
    }

    /// 自分の like/unlike の結果をキャッシュに反映する。サーバが返した最新の count/liked を
    /// その曲のエントリに patch するので、古い has_user_liked が残らない。
    private func applyLikeResult(showId: String, result: LikeResult) {
        guard let cached = likesCache[showId] else { return }
        let entry = LikeEntry(songId: result.songId, likeCount: result.likeCount, hasUserLiked: result.liked)
        var entries = cached.entries
        if let idx = entries.firstIndex(where: { $0.songId == result.songId }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
        // 集計の鮮度は維持しつつ自分の操作だけ反映 (at は据え置きで TTL を延ばさない)。
        likesCache[showId] = (entries, cached.at)
    }

    /// サインアウト/アカウント切替時に呼ぶ。has_user_liked は user 依存なので、
    /// 別ユーザーの like 状態が残らないよう全公演の集計キャッシュを捨てる。
    func clearCache() {
        likesCache.removeAll()
    }
}

enum LikeError: LocalizedError {
    case unauthorized
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Like するには Apple Sign In が必要です"
        }
    }
}
