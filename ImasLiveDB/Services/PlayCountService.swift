import Foundation
import UIKit
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "play_count")

/// 曲の再生回数 (試聴 / フル再生) を端末に貯めて、みんなの集計へ送る。
///
/// 何秒聴いたら 1 回か・まとめて送る間隔・送れたぶんの引き方・本文の形は imas-core (`play_log`)。
/// ここは保存 (UserDefaults) と送信 (`CommunityAPI`) だけ。お気に入りの積み残し
/// (`PendingCommunityActions`) と同じ作り。
@MainActor
final class PlayCountService {
    static let shared = PlayCountService()

    /// まとまりをサーバへ送る口。テストでは差し替える。
    typealias SendBatch = @Sendable (_ body: String) async throws -> Void

    private let key: String
    private let defaults: UserDefaults
    private let sendBatch: SendBatch
    private(set) var log: PlayLog
    private var isFlushing = false

    private convenience init() {
        self.init(defaults: .standard) { body in
            try await CommunityAPI.shared.sendPlayBatch(body: body)
        }
    }

    init(defaults: UserDefaults, key: String = "play_count_log", send: @escaping SendBatch) {
        self.defaults = defaults
        self.key = key
        self.sendBatch = send
        if let data = defaults.data(forKey: key) {
            log = playLogDecode(text: String(decoding: data, as: UTF8.self))
        } else {
            log = playLogDecode(text: "")
        }
    }

    /// 数えるまでの秒数 (試聴 / フル再生)。
    static func secondsToCount(_ kind: PlayKind) -> TimeInterval { playCountAfterSeconds(kind: kind) }

    /// 1 回聴いたと数える。
    func record(songId: String, kind: PlayKind) {
        log = playLogRecord(log: log, songId: songId, kind: kind)
        persist()
    }

    /// 送る時期なら送る。前面に来たとき・背面に回るときに呼ぶ。失敗は貯めたまま。
    func flushIfDue() {
        guard !isFlushing else { return }
        let now = Date().timeIntervalSince1970
        let batch = playLogDue(log: log, now: now)
        guard !batch.isEmpty else { return }
        isFlushing = true
        log = playLogMarkAttempt(log: log, now: now)
        persist()
        let body = playBatchBody(batch: batch)
        // 背面に回った直後でも送り切れるよう、OS に少し待ってもらう。
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "play_count_flush")
        Task {
            defer {
                isFlushing = false
                if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
            }
            do {
                try await sendBatch(body)
                // 待つ間に増えたぶんを失わないよう、今の log から送れたぶんだけ引く。
                log = playLogAfterSent(log: log, sent: batch)
                persist()
            } catch {
                logger.warning("play batch send failed: \(error.localizedDescription)")
            }
        }
    }

    private func persist() {
        defaults.set(Data(playLogEncode(log: log).utf8), forKey: key)
    }
}
