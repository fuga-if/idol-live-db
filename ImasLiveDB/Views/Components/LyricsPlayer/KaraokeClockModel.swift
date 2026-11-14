import Foundation
import Observation

/// カラオケモードの時計。端末の単調時計に、合わせた位置・速さ・手のずらしを足して曲の位置を出す
/// (計算はコア `karaoke*`)。`LyricsPlayback.positionMs` の代わりにこれを読む。
@MainActor @Observable
final class KaraokeClockModel {
    enum Change: Equatable {
        case tapped
        case rateFixed
        case heard
        case nudged
    }

    private(set) var clock: KaraokeClock?
    /// 止めているときの曲の位置。
    private(set) var pausedAtMs: Int64?
    /// 最後に時計が動いた理由 (下の状態の文に出す)。
    private(set) var lastChange: Change?
    @ObservationIgnored private var anchor: KaraokeAnchor?
    @ObservationIgnored private var pending: KaraokeHeard?

    var isSynced: Bool { clock != nil }
    var isPaused: Bool { pausedAtMs != nil }
    var nudgeMs: Int { Int(clock?.nudgeMs ?? 0) }

    /// 今の曲の位置 (ms)。まだ合わせていなければ nil。
    func positionMs(now: Int64 = KaraokeTime.nowMs()) -> Int? {
        if let pausedAtMs { return Int(pausedAtMs) }
        return clock.map { Int(karaokePosition(clock: $0, nowMs: now)) }
    }

    /// 「この行が今始まった」。
    func tap(lineStartMs: Int, now: Int64 = KaraokeTime.nowMs()) {
        let outcome = karaokeTap(previous: clock, previousAnchor: anchor, lineStartMs: Int64(lineStartMs), nowMs: now)
        clock = outcome.clock
        anchor = outcome.anchor
        pending = nil
        pausedAtMs = nil
        lastChange = outcome.rateChanged ? .rateFixed : .tapped
    }

    /// 耳で聞いた位置。止めている間は採らない。
    /// - Returns: 大きく外れた値を保留した (すぐ聞き直して確かめたい) とき true。
    @discardableResult
    func heard(songMs: Int64, at now: Int64) -> Bool {
        guard pausedAtMs == nil else { return false }
        let outcome = karaokeHeard(clock: clock, pending: pending, heardSongMs: songMs, nowMs: now)
        clock = outcome.clock
        pending = outcome.pending
        switch outcome.change {
        case .adopted, .eased, .jumped:
            lastChange = .heard
            // 時計を耳で動かしたら、速さを出す前の点はこの聞いた点に置き換える
            // (古い点との間には耳の補正が挟まっていて、速さの材料にならない)。
            anchor = KaraokeAnchor(songMs: songMs, monoMs: now)
        case .kept: break
        case .held: return true
        }
        return false
    }

    func nudge(_ deltaMs: Int) {
        guard let clock else { return }
        let nudged = karaokeNudge(clock: clock, deltaMs: Int64(deltaMs))
        self.clock = nudged
        // 止めている位置も、実際に動いたずらしの分だけ動かす (上限で止まったら動かさない)。
        if let pausedAtMs { self.pausedAtMs = pausedAtMs + nudged.nudgeMs - clock.nudgeMs }
        lastChange = .nudged
    }

    func pause(now: Int64 = KaraokeTime.nowMs()) {
        guard let clock, pausedAtMs == nil else { return }
        pausedAtMs = karaokePosition(clock: clock, nowMs: now)
    }

    func resume(now: Int64 = KaraokeTime.nowMs()) {
        guard let clock, let pausedAtMs else { return }
        // 止めた位置から続ける (ずらしは位置に入っているので、合わせ直す位置からは引く)。
        self.clock = karaokeRebase(clock: clock, songMs: pausedAtMs - clock.nudgeMs, nowMs: now)
        self.pausedAtMs = nil
        // 止めていた時間が速さに化けないよう、前の点は捨てる。
        anchor = nil
    }

    /// 合わせる前に戻す (同じ曲をもう一度歌う)。
    func reset() {
        clock = nil
        anchor = nil
        pending = nil
        pausedAtMs = nil
        lastChange = nil
    }
}

/// 曲ごとに選んだ自分のパート (アイドルの id だけ。歌詞は残さない)。
enum KaraokePartStore {
    private static func key(_ songId: String) -> String { "karaoke.parts.\(songId)" }

    static func load(songId: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(songId)) ?? []
    }

    static func save(_ ids: [String], songId: String) {
        if ids.isEmpty {
            UserDefaults.standard.removeObject(forKey: key(songId))
        } else {
            UserDefaults.standard.set(ids, forKey: key(songId))
        }
    }
}
