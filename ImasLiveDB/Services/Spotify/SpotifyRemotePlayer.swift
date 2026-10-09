import Foundation
import os

/// Spotify アプリを Web API で操作して鳴らす (Spotify Connect)。音を出すのは利用者の Spotify アプリで、
/// このアプリは「この曲を鳴らして」「今どこ？」を頼むだけ。SDK は使わない (Client ID の登録だけで済む)。
///
/// 再生位置は周期で聞きに行き、間はコア (`spotifyPositionNow`) が経過を足して埋める。
/// 曲と再生状態の付け替え (どの曲が鳴っているか) は `MusicKitService` が `onChange` で受けて行う。
///
/// 鳴らし始めは Spotify 側の切り替わりが遅れる (頼んでから 1〜2 秒は前の曲が返る)。
/// そこで鳴らし始めごとに番号 (`session`) を振り、頼んだ曲が一度返ってくるまでの状態は渡さない。
/// その間の位置の指定 (歌詞の行のタップ) も、頼んだ曲が鳴り始めてから送る。
@MainActor
final class SpotifyRemotePlayer {
    /// 最後に聞いた状態と、聞いた時刻。
    struct Snapshot {
        let trackId: String?
        let progressMs: Int
        let durationMs: Int?
        let isPlaying: Bool
        let fetchedAt: Date
    }

    private(set) var last: Snapshot?
    /// 聞きに行くたびに呼ぶ (頼んだ曲が鳴り始めてから)。nil は Spotify が何も鳴らしていない。
    var onChange: ((Snapshot?) -> Void)?
    /// 鍵が切れた・許可が無い・鳴らす先が消えたなど、利用者に伝える失敗。
    var onFailure: ((SpotifyFailure) -> Void)?

    private var pollTask: Task<Void, Never>?
    private var spotify: SpotifyService { .shared }
    /// 鳴らし始めの番号。古い頼みの結果 (前の再生のぶん) を捨てるのに使う。
    private var session = 0
    /// 頼んだ曲が鳴り始めたのを確かめたか。確かめるまでは状態を渡さない。
    private var isConfirmed = false
    private var startedAt = Date()
    private var expectedTrackIds: Set<String> = []
    /// 鳴り始める前に頼まれた位置。鳴り始めたら送る。
    private var pendingSeekMs: Int?

    /// 頼んだ曲が鳴り始めるのを待つ長さ。過ぎたら、返ってくる状態をそのまま信じる。
    private static let confirmTimeout: TimeInterval = 8

    // MARK: - 操作

    /// 曲を並べて、`offset` 番目から鳴らし始める。鳴らす先 (Spotify アプリ) を選ぶのはコア (`spotifyPickDevice`)。
    func play(uris: [String], offset: Int) async throws {
        session += 1
        let mine = session
        let token = try await spotify.accessToken()
        let devices = try await SpotifyWebAPI.devices(accessToken: token)
        guard let index = spotifyPickDevice(devices: devices), let deviceId = devices[Int(index)].id else {
            throw SpotifyWebAPI.Failure(kind: .noDevice)
        }
        try await SpotifyWebAPI.play(uris: uris, offset: offset, deviceId: deviceId, accessToken: token)
        guard mine == session else { return }
        expectedTrackIds = Set(uris.compactMap(Self.trackId(fromURI:)))
        isConfirmed = false
        startedAt = Date()
        pendingSeekMs = nil
        // 次に聞きに行くまでの間も位置が進むように、頭から鳴り始めたことにしておく。
        last = Snapshot(trackId: Self.trackId(fromURI: uris[offset]), progressMs: 0,
                        durationMs: nil, isPlaying: true, fetchedAt: Date())
        startPolling()
    }

    func pause() {
        if let last { self.last = Snapshot(trackId: last.trackId, progressMs: positionMs ?? last.progressMs,
                                           durationMs: last.durationMs, isPlaying: false, fetchedAt: Date()) }
        send { try await SpotifyWebAPI.pause(accessToken: $0) }
    }

    func resume() {
        if let last { self.last = Snapshot(trackId: last.trackId, progressMs: last.progressMs,
                                           durationMs: last.durationMs, isPlaying: true, fetchedAt: Date()) }
        send { try await SpotifyWebAPI.resume(accessToken: $0) }
    }

    func seek(ms: Int) {
        if let last { self.last = Snapshot(trackId: last.trackId, progressMs: max(0, ms),
                                           durationMs: last.durationMs, isPlaying: last.isPlaying, fetchedAt: Date()) }
        // 鳴り始める前に送ると、読み込み前の Spotify が捨てる。鳴り始めたら送る。
        guard isConfirmed else {
            pendingSeekMs = ms
            return
        }
        send { try await SpotifyWebAPI.seek(ms: ms, accessToken: $0) }
    }

    func next() { send { try await SpotifyWebAPI.next(accessToken: $0) } }
    func previous() { send { try await SpotifyWebAPI.previous(accessToken: $0) } }

    /// 聞きに行くのをやめる (Spotify 側の音は止めない。止めるのは `pause`)。
    func detach() {
        session += 1
        pollTask?.cancel()
        pollTask = nil
        last = nil
        isConfirmed = false
        expectedTrackIds = []
        pendingSeekMs = nil
    }

    // MARK: - 位置

    var positionMs: Int? {
        guard let last else { return nil }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let fetched = Int64(last.fetchedAt.timeIntervalSince1970 * 1000)
        return Int(spotifyPositionNow(progressMs: Int64(last.progressMs), fetchedAtMs: fetched, nowMs: now,
                                      isPlaying: last.isPlaying, durationMs: last.durationMs.map(Int64.init)))
    }

    var durationMs: Int? { last?.durationMs }

    // MARK: - 中身

    /// 操作を送って、すぐ状態を聞き直す (Spotify 側が受け付けたかを画面に返す)。
    private func send(_ action: @escaping @Sendable (String) async throws -> Void) {
        let mine = session
        Task { @MainActor in
            do {
                try await action(try await spotify.accessToken())
                try? await Task.sleep(for: .milliseconds(300))
                guard mine == session else { return }
                await poll()
            } catch let failure as SpotifyWebAPI.Failure {
                Logger.musickit.error("spotify_control_failed: \(String(describing: failure.kind))")
                guard mine == session else { return }
                // 通信の揺れ・「今はできない」(Restriction violated) は伝えない。状態は次の周回で読み直す。
                if Self.isWorthTelling(failure.kind) { onFailure?(failure.kind) }
            } catch {}
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // 鳴っている間は 1 秒ごと、止まっている間はゆっくり。
                let interval: Duration = (self?.last?.isPlaying ?? false) ? .seconds(1) : .seconds(3)
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                await self.poll()
            }
        }
    }

    private func poll() async {
        let mine = session
        do {
            let state = try await SpotifyWebAPI.playerState(accessToken: try await spotify.accessToken())
            // 聞いている間に鳴らし直した・止めたなら、この答えは前の再生のもの。
            guard mine == session else { return }
            if !isConfirmed {
                let arrived = state?.trackId.map(expectedTrackIds.contains) ?? false
                let timedOut = Date().timeIntervalSince(startedAt) > Self.confirmTimeout
                guard arrived || timedOut else { return }
                isConfirmed = true
                if let ms = pendingSeekMs {
                    pendingSeekMs = nil
                    seek(ms: ms)
                }
            }
            last = state.map {
                Snapshot(trackId: $0.trackId, progressMs: $0.progressMs, durationMs: $0.durationMs,
                         isPlaying: $0.isPlaying, fetchedAt: Date())
            }
            onChange?(last)
        } catch let failure as SpotifyWebAPI.Failure {
            guard mine == session else { return }
            // 通信の揺れ・混雑は次の周回で聞き直す。鍵や許可の問題は聞き続けても直らない。
            if Self.stopsPlayback(failure.kind) {
                detach()
                onFailure?(failure.kind)
            }
        } catch {}
    }

    /// 聞き続けても直らない失敗 (再生ごと手放す)。
    static func stopsPlayback(_ kind: SpotifyFailure) -> Bool {
        switch kind {
        case .sessionExpired, .playbackNotAllowed, .premiumRequired, .notRegistered: true
        default: false
        }
    }

    /// 利用者に伝える失敗。
    private static func isWorthTelling(_ kind: SpotifyFailure) -> Bool {
        stopsPlayback(kind) || kind == .noDevice
    }

    static func trackId(fromURI uri: String) -> String? {
        uri.hasPrefix("spotify:track:") ? String(uri.dropFirst("spotify:track:".count)) : nil
    }
}
