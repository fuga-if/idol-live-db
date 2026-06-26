import Foundation
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "pending_actions")

/// お気に入りのコミュニティAPI送信に失敗した場合の軽量永続キュー。
/// UserDefaults ベース・JSON 配列で保持し、再起動後もリトライできる。
struct PendingFavoriteAction: Codable, Sendable {
    let songId: String
    let value: Bool
    let enqueuedAt: Date
    var retryCount: Int
}

@MainActor
final class PendingCommunityActions {
    static let shared = PendingCommunityActions()

    private let key = "pending_favorite_actions"
    private var actions: [PendingFavoriteAction] = []
    private var isFlushing = false
    private static let maxRetries = 3

    private init() {
        load()
    }

    // MARK: - Queue Management

    func enqueue(songId: String, value: Bool) {
        // 同じ songId が既にあれば上書き
        actions.removeAll { $0.songId == songId }
        let action = PendingFavoriteAction(songId: songId, value: value, enqueuedAt: Date(), retryCount: 0)
        actions.append(action)
        persist()
        logger.info("Enqueued pending favorite: songId=\(songId) value=\(value)")
    }

    func flushPendingFavorites() {
        guard !isFlushing, !actions.isEmpty else { return }
        isFlushing = true
        Task {
            await performFlush()
            isFlushing = false
        }
    }

    // MARK: - Private

    private func performFlush() async {
        var remaining: [PendingFavoriteAction] = []

        for var action in actions {
            // 指数バックオフ: 最大3回
            if action.retryCount >= Self.maxRetries {
                logger.error("Giving up on pending favorite: songId=\(action.songId) after \(action.retryCount) retries")
                continue
            }

            let delay = pow(2.0, Double(action.retryCount))
            if action.retryCount > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            do {
                try await CommunityAPI.shared.toggleFavorite(songId: action.songId, value: action.value)
                logger.info("Flushed pending favorite: songId=\(action.songId) retryCount=\(action.retryCount)")
            } catch {
                action.retryCount += 1
                if action.retryCount < Self.maxRetries {
                    remaining.append(action)
                    logger.warning("Pending favorite retry \(action.retryCount)/\(Self.maxRetries): songId=\(action.songId) error=\(error.localizedDescription)")
                } else {
                    logger.error("Giving up on pending favorite: songId=\(action.songId) error=\(error.localizedDescription)")
                }
            }
        }

        actions = remaining
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PendingFavoriteAction].self, from: data) else {
            actions = []
            return
        }
        actions = decoded
        if !actions.isEmpty {
            let count = actions.count
            logger.info("Loaded \(count) pending favorite actions from UserDefaults")
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
