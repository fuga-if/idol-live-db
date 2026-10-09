import Foundation
import os
import SpotifyiOS
import UIKit

/// 利用者の Spotify アプリと Spotify の SDK (App Remote) で繋いで鳴らす。音を出すのは Spotify アプリで、
/// このアプリは「この曲を鳴らして」と頼み、鳴っている曲と位置を Spotify アプリから知らされる。
///
/// - 繋ぐ: Spotify アプリが動いていれば、ログインの鍵 (`app-remote-control` 入り) でそのまま繋ぐ。
///   動いていなければ `authorizeAndPlayURI` で Spotify アプリを起こし (一瞬 Spotify アプリに切り替わる)、
///   戻ってきた URL (`imaslivedb://spotify-callback`) の鍵で繋ぐ。
/// - 鳴らす: 1 曲は SDK で。並べて鳴らすときは SDK に口が無いので、繋いだ後に Web API の
///   `PUT /me/player/play` に並べた曲を渡す (繋いだ Spotify アプリが鳴らす先として見えている)。
/// - 位置: SDK が状態の変わり目を知らせる。その間はコア (`spotifyPositionNow`) が経過を足して埋める。
///   このアプリが裏に回ると SDK の接続は切れるので、表に戻ったら繋ぎ直す。繋がっていない間は
///   Web API に周期で聞きに行く。
///
/// 鳴らし始めは Spotify 側の切り替わりが遅れる (頼んでから 1〜2 秒は前の曲が返る)。
/// そこで鳴らし始めごとに番号 (`session`) を振り、頼んだ曲が一度返ってくるまでの状態は渡さない。
/// その間の位置の指定 (歌詞の行のタップ) も、頼んだ曲が鳴り始めてから送る。
@MainActor
final class SpotifyRemotePlayer: NSObject {
    /// 最後に知った状態と、知った時刻。
    struct Snapshot {
        let trackId: String?
        let progressMs: Int
        let durationMs: Int?
        let isPlaying: Bool
        let fetchedAt: Date
    }

    private(set) var last: Snapshot?
    /// 状態を知るたびに呼ぶ (頼んだ曲が鳴り始めてから)。nil は Spotify が何も鳴らしていない。
    var onChange: ((Snapshot?) -> Void)?
    /// 鍵が切れた・許可が無い・鳴らす先が消えたなど、利用者に伝える失敗。
    var onFailure: ((SpotifyFailure) -> Void)?

    private var spotify: SpotifyService { .shared }
    private var appRemote: SPTAppRemote?
    private var appRemoteClientId: String?
    /// 接続を待っている頼み (繋がった / 断られたで起こす)。
    /// 待ちごとに番号を振る (前の待ちの時間切れが、後から始めた待ちを起こさないように)。
    private var connectWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var pollTask: Task<Void, Never>?
    /// 鳴らし始めの番号。古い頼みの結果 (前の再生のぶん) を捨てるのに使う。
    private var session = 0
    /// いま鳴らしているか (表に戻ったときに繋ぎ直すか)。
    private var isActive = false
    /// 頼んだ曲が鳴り始めたのを確かめたか。確かめるまでは状態を渡さない。
    private var isConfirmed = false
    private var startedAt = Date()
    private var expectedTrackIds: Set<String> = []
    /// 鳴り始める前に頼まれた位置。鳴り始めたら送る。
    private var pendingSeekMs: Int?

    /// 頼んだ曲が鳴り始めるのを待つ長さ。過ぎたら、返ってくる状態をそのまま信じる。
    private static let confirmTimeout: TimeInterval = 8
    /// Spotify アプリを起こして戻ってくるのを待つ長さ。
    private static let wakeTimeout: Duration = .seconds(60)

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // 裏に回ると SDK の接続は保てない。自分から切って、戻ったら繋ぎ直す。
                if self?.appRemote?.isConnected == true { self?.appRemote?.disconnect() }
            }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                Task { @MainActor in _ = await self.connect() }
            }
        }
    }

    // MARK: - 操作

    /// 曲を並べて、`offset` 番目から鳴らし始める。
    func play(uris: [String], offset: Int) async throws {
        session += 1
        let mine = session
        let first = uris[offset]
        try await ensureConnected(wakingWith: first)
        guard mine == session else { return }
        if uris.count == 1 {
            try await playNative(first)
        } else {
            do {
                try await playList(uris: uris, offset: offset)
            } catch let failure as SpotifyWebAPI.Failure where failure.kind == .noDevice {
                // 繋いだ直後で鳴らす先の一覧に出てこないことがある。せめて押した曲だけは鳴らす。
                try await playNative(first)
            }
        }
        guard mine == session else { return }
        isActive = true
        expectedTrackIds = Set(uris.compactMap(Self.trackId(fromURI:)))
        isConfirmed = false
        startedAt = Date()
        pendingSeekMs = nil
        // 次に知らされるまでの間も位置が進むように、頭から鳴り始めたことにしておく。
        last = Snapshot(trackId: Self.trackId(fromURI: first), progressMs: 0,
                        durationMs: nil, isPlaying: true, fetchedAt: Date())
        startPolling()
    }

    func pause() {
        if let last { self.last = Snapshot(trackId: last.trackId, progressMs: positionMs ?? last.progressMs,
                                           durationMs: last.durationMs, isPlaying: false, fetchedAt: Date()) }
        command(native: { $0.pause($1) }, web: { try await SpotifyWebAPI.pause(accessToken: $0) })
    }

    func resume() {
        if let last { self.last = Snapshot(trackId: last.trackId, progressMs: last.progressMs,
                                           durationMs: last.durationMs, isPlaying: true, fetchedAt: Date()) }
        command(native: { $0.resume($1) }, web: { try await SpotifyWebAPI.resume(accessToken: $0) })
    }

    func seek(ms: Int) {
        if let last { self.last = Snapshot(trackId: last.trackId, progressMs: max(0, ms),
                                           durationMs: last.durationMs, isPlaying: last.isPlaying, fetchedAt: Date()) }
        // 鳴り始める前に送ると、読み込み前の Spotify が捨てる。鳴り始めたら送る。
        guard isConfirmed else {
            pendingSeekMs = ms
            return
        }
        command(native: { $0.seek(toPosition: max(0, ms), callback: $1) },
                web: { try await SpotifyWebAPI.seek(ms: ms, accessToken: $0) })
    }

    func next() {
        command(native: { $0.skip(toNext: $1) }, web: { try await SpotifyWebAPI.next(accessToken: $0) })
    }

    func previous() {
        command(native: { $0.skip(toPrevious: $1) }, web: { try await SpotifyWebAPI.previous(accessToken: $0) })
    }

    /// 追うのをやめる (Spotify 側の音は止めない。止めるのは `pause`)。
    func detach() {
        session += 1
        isActive = false
        pollTask?.cancel()
        pollTask = nil
        last = nil
        isConfirmed = false
        expectedTrackIds = []
        pendingSeekMs = nil
        appRemote?.playerAPI?.unsubscribe(toPlayerState: nil)
    }

    /// Spotify アプリから戻ってきた URL (`authorizeAndPlayURI` の結果)。鍵を受け取って繋ぐ。
    func handleCallback(_ url: URL) {
        guard let remote = appRemote else { return }
        let params = remote.authorizationParameters(from: url)
        if let token = params?[SPTAppRemoteAccessTokenKey] {
            remote.connectionParameters.accessToken = token
            remote.connect()
        } else {
            resumeWaiters(false)
        }
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

    // MARK: - 繋ぐ

    private func remote() -> SPTAppRemote? {
        guard let clientId = spotify.clientId, let redirect = URL(string: spotifySetupGuide(platform: .ios).redirectUri)
        else { return nil }
        if let appRemote, appRemoteClientId == clientId { return appRemote }
        appRemote?.disconnect()
        let remote = SPTAppRemote(configuration: SPTConfiguration(clientID: clientId, redirectURL: redirect), logLevel: .error)
        remote.delegate = self
        appRemote = remote
        appRemoteClientId = clientId
        return remote
    }

    /// 繋がっていなければ繋ぐ。Spotify アプリが動いていなければ、`uri` を鳴らしながら起こす。
    private func ensureConnected(wakingWith uri: String) async throws {
        guard let remote = remote() else { throw SpotifyWebAPI.Failure(kind: .sessionExpired) }
        if remote.isConnected { return }
        if await connect() { return }
        // Spotify アプリが動いていない。起こして (Spotify アプリに切り替わる)、戻ってくるのを待つ。
        let installed = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            remote.authorizeAndPlayURI(uri) { c.resume(returning: $0) }
        }
        guard installed else { throw SpotifyWebAPI.Failure(kind: .appNotInstalled) }
        guard await waitForConnection(timeout: Self.wakeTimeout) else {
            throw SpotifyWebAPI.Failure(kind: .connectionFailed)
        }
    }

    /// ログインの鍵で繋ぐ。繋がったか。
    private func connect() async -> Bool {
        guard let remote = remote() else { return false }
        if remote.isConnected { return true }
        guard let token = try? await spotify.accessToken() else { return false }
        remote.connectionParameters.accessToken = token
        remote.connect()
        return await waitForConnection(timeout: .seconds(5))
    }

    private func waitForConnection(timeout: Duration) async -> Bool {
        let id = UUID()
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            connectWaiters[id] = c
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, let waiter = self.connectWaiters.removeValue(forKey: id) else { return }
                waiter.resume(returning: self.appRemote?.isConnected ?? false)
            }
        }
    }

    /// 繋がった / 断られたときに、待っている頼みをすべて起こす。
    private func resumeWaiters(_ connected: Bool) {
        let waiters = connectWaiters.values
        connectWaiters = [:]
        waiters.forEach { $0.resume(returning: connected) }
    }

    // MARK: - 鳴らす

    private func playNative(_ uri: String) async throws {
        guard let player = appRemote?.playerAPI else { throw SpotifyWebAPI.Failure(kind: .connectionFailed) }
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            player.play(uri) { _, error in c.resume(returning: error == nil) }
        }
        guard ok else { throw SpotifyWebAPI.Failure(kind: .premiumRequired) }
    }

    private func playList(uris: [String], offset: Int) async throws {
        let token = try await spotify.accessToken()
        let devices = try await SpotifyWebAPI.devices(accessToken: token)
        guard let index = spotifyPickDevice(devices: devices), let deviceId = devices[Int(index)].id else {
            throw SpotifyWebAPI.Failure(kind: .noDevice)
        }
        try await SpotifyWebAPI.play(uris: uris, offset: offset, deviceId: deviceId, accessToken: token)
    }

    /// 操作を送る。繋がっていれば SDK で、繋がっていなければ Web API で。
    private func command(native: @escaping (SPTAppRemotePlayerAPI, SPTAppRemoteCallback?) -> Void,
                         web: @escaping @Sendable (String) async throws -> Void) {
        let mine = session
        if let player = appRemote?.playerAPI, appRemote?.isConnected == true {
            native(player) { _, error in
                if let error { Logger.musickit.error("spotify_sdk_command_failed: \(error.localizedDescription)") }
            }
            return
        }
        Task { @MainActor in
            do {
                try await web(try await spotify.accessToken())
                try? await Task.sleep(for: .milliseconds(300))
                guard mine == session else { return }
                await pollWeb()
            } catch let failure as SpotifyWebAPI.Failure {
                Logger.musickit.error("spotify_control_failed: \(String(describing: failure.kind))")
                guard mine == session else { return }
                // 通信の揺れ・「今はできない」(Restriction violated) は伝えない。
                if Self.isWorthTelling(failure.kind) { onFailure?(failure.kind) }
            } catch {}
        }
    }

    // MARK: - 状態

    /// SDK が繋がっている間は SDK の知らせを待ち、繋がっていない間は Web API に聞きに行く。
    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let interval: Duration = (self?.last?.isPlaying ?? false) ? .seconds(1) : .seconds(3)
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                if self.appRemote?.isConnected == true { continue }
                await self.pollWeb()
            }
        }
    }

    private func pollWeb() async {
        let mine = session
        do {
            let state = try await SpotifyWebAPI.playerState(accessToken: try await spotify.accessToken())
            guard mine == session else { return }
            accept(state.map {
                Snapshot(trackId: $0.trackId, progressMs: $0.progressMs, durationMs: $0.durationMs,
                         isPlaying: $0.isPlaying, fetchedAt: Date())
            })
        } catch let failure as SpotifyWebAPI.Failure {
            guard mine == session else { return }
            if Self.stopsPlayback(failure.kind) {
                detach()
                onFailure?(failure.kind)
            }
        } catch {}
    }

    /// 知った状態を受け取る (SDK の知らせ・Web API の答えのどちらからも)。
    private func accept(_ snapshot: Snapshot?) {
        guard isActive else { return }
        if !isConfirmed {
            let arrived = snapshot?.trackId.map(expectedTrackIds.contains) ?? false
            let timedOut = Date().timeIntervalSince(startedAt) > Self.confirmTimeout
            guard arrived || timedOut else { return }
            isConfirmed = true
            if let ms = pendingSeekMs {
                pendingSeekMs = nil
                seek(ms: ms)
            }
        }
        last = snapshot
        onChange?(snapshot)
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

    nonisolated static func trackId(fromURI uri: String) -> String? {
        uri.hasPrefix("spotify:track:") ? String(uri.dropFirst("spotify:track:".count)) : nil
    }
}

// MARK: - SDK の知らせ

extension SpotifyRemotePlayer: SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        MainActor.assumeIsolated {
            // 引数の appRemote は自分が持っているものと同じ (主スレッドで知らされる)。
            self.appRemote?.playerAPI?.delegate = self
            self.appRemote?.playerAPI?.subscribe(toPlayerState: nil)
            resumeWaiters(true)
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        MainActor.assumeIsolated {
            Logger.musickit.error("spotify_sdk_connect_failed: \(error?.localizedDescription ?? "-")")
            resumeWaiters(false)
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        // 裏に回った・Spotify アプリが落ちた。表に戻れば繋ぎ直し、それまでは Web API に聞く。
    }

    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let trackId = Self.trackId(fromURI: playerState.track.uri)
        let progress = playerState.playbackPosition
        let duration = Int(playerState.track.duration)
        let playing = !playerState.isPaused
        MainActor.assumeIsolated {
            accept(Snapshot(trackId: trackId, progressMs: progress, durationMs: duration > 0 ? duration : nil,
                            isPlaying: playing, fetchedAt: Date()))
        }
    }
}
