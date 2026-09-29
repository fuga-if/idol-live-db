import Foundation
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "pending_actions")

/// お気に入りのコミュニティAPI送信に失敗した場合の軽量永続キュー。
/// UserDefaults に置き、再起動後もリトライできる。積む・置き換える・待つ・諦めるの規則と
/// 保存形式は imas-core (`pending_favorites`)。ここは保存と送信だけ。
@MainActor
final class PendingCommunityActions {
    static let shared = PendingCommunityActions()

    /// お気に入りをサーバへ送る口。テストでは差し替える。
    typealias SendFavorite = @Sendable (_ songId: String, _ value: Bool) async throws -> Void

    private let key: String
    private let defaults: UserDefaults
    private let sendFavorite: SendFavorite
    private(set) var actions: [PendingFavorite] = []
    private var isFlushing = false

    private convenience init() {
        self.init(defaults: .standard) { songId, value in
            try await CommunityAPI.shared.toggleFavorite(songId: songId, value: value)
        }
    }

    init(defaults: UserDefaults, key: String = "pending_favorite_actions", send: @escaping SendFavorite) {
        self.defaults = defaults
        self.key = key
        self.sendFavorite = send
        load()
    }

    // MARK: - Queue Management

    /// お気に入りの状態をコミュニティ集計へ送る。送れなければ積んで、後で送り直す。
    func send(songId: String, value: Bool) async {
        do {
            try await sendFavorite(songId, value)
            // 送れた値がこの曲の最新の意思。前に積んだ別の値を送り直すと集計が巻き戻る。
            discard(songId: songId)
        } catch {
            logger.warning("toggleFavorite failed, enqueuing: songId=\(songId) error=\(error.localizedDescription)")
            enqueue(songId: songId, value: value)
        }
    }

    func enqueue(songId: String, value: Bool) {
        actions = pendingFavoritesEnqueue(queue: actions, songId: songId, value: value,
                                          now: Date().timeIntervalSinceReferenceDate)
        persist()
        logger.info("Enqueued pending favorite: songId=\(songId) value=\(value)")
    }

    func flushPendingFavorites() {
        guard !isFlushing, !actions.isEmpty else { return }
        isFlushing = true
        Task { await flush() }
    }

    /// 積み残しを送り直す (テストからは完了を待てる形で呼ぶ)。
    func flush() async {
        isFlushing = true
        defer { isFlushing = false }
        await performFlush()
    }

    // MARK: - Private

    /// この曲の積み残しを捨てる。
    private func discard(songId: String) {
        let next = pendingFavoritesDiscard(queue: actions, songId: songId)
        if next.count != actions.count {
            actions = next
            persist()
        }
    }

    /// 送り直しは、始めた時点の列を順に回す。送信を待つ間に積まれた・捨てられたものを
    /// 失わないよう、結果は 1 件ずつ今の列に反映する。
    private func performFlush() async {
        for action in actions {
            guard pendingFavoriteIsStillQueued(queue: actions, item: action) else { continue }

            let delay = pendingFavoriteRetryDelaySeconds(retryCount: action.retryCount)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard pendingFavoriteIsStillQueued(queue: actions, item: action) else { continue }
            }

            let outcome: SendOutcome
            do {
                try await sendFavorite(action.songId, action.value)
                logger.info("Flushed pending favorite: songId=\(action.songId) retryCount=\(action.retryCount)")
                outcome = .sent
            } catch {
                logger.warning("Pending favorite retry failed: songId=\(action.songId) retryCount=\(action.retryCount) error=\(error.localizedDescription)")
                outcome = .failed
            }
            actions = pendingFavoritesAfterAttempt(queue: actions, item: action, outcome: outcome)
        }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: key) else {
            actions = []
            return
        }
        actions = pendingFavoritesDecode(text: String(decoding: data, as: UTF8.self))
        if !actions.isEmpty {
            let count = actions.count
            logger.info("Loaded \(count) pending favorite actions from UserDefaults")
        }
    }

    private func persist() {
        defaults.set(Data(pendingFavoritesEncode(queue: actions).utf8), forKey: key)
    }
}
