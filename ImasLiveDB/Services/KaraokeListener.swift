import AVFAudio
import Foundation
import Observation
import ShazamKit

/// カラオケモードの「耳で合わせる」。マイクで鳴っている音を Shazam のカタログと照合して、
/// 開いている曲のどこが今鳴っているかを聞く。
///
/// CD の off vocal は原曲と同じ尺なので、当たったのが原曲でも off vocal でも、
/// 当たった位置 (`predictedCurrentMatchOffset`) をそのまま行の時刻の軸に使う。
/// 別の曲に当たったら (隣の部屋・前の曲の残り) 採らない (判定はコア `karaokeHeardSameSong`)。
///
/// 合うまでは数秒おきに聞き、合ってからは 30 秒おきに聞き直してずれを直す (直し方はコア `karaokeHeard`)。
/// 聞いた音はどこにも残さない (照合は ShazamKit が署名にして行う)。
@MainActor @Observable
final class KaraokeListener {
    enum State: Equatable {
        /// 聞いていない (止めた・まだ始めていない)。
        case idle
        case listening
        /// 開いている曲として当たった。
        case matched
        /// 当たったが別の曲だった。
        case otherSong
        /// 鳴っている音がカタログに見つからない (カラオケ機の独自の演奏など)。
        case notFound
        /// マイクを許可されていない。
        case denied
        /// 照合できない (通信・ShazamKit が使えない)。タップで合わせてもらう。
        case unavailable
    }

    private(set) var state: State = .idle

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var session: SHManagedSession?

    /// 合ってから聞き直す間隔。
    private static let recheck: Duration = .seconds(30)
    /// 合うまでの間隔。
    private static let retry: Duration = .seconds(2)
    /// 続けて失敗したらあきらめる回数 (ShazamKit が使えない設定のときに回し続けない)。
    private static let maxErrors = 3

    /// 聞き始める。`onHeard(曲の位置 ms, そのときの単調時計 ms)` は開いている曲として当たったときだけ呼ぶ。
    func start(song: Song, onHeard: @escaping @MainActor (Int64, Int64) -> Void) {
        stop()
        task = Task { [weak self] in
            guard await Self.requestMicrophone() else {
                self?.state = .denied
                return
            }
            let session = SHManagedSession()
            self?.session = session
            await session.prepare()
            var errors = 0
            while !Task.isCancelled {
                self?.state = .listening
                let result = await session.result()
                if Task.isCancelled { break }
                var wait = Self.retry
                switch result {
                case .match(let match):
                    errors = 0
                    let now = KaraokeTime.nowMs()
                    let item = match.mediaItems.first
                    if let item, karaokeHeardSameSong(
                        songTitle: song.title, songAppleMusicId: song.appleMusicId, songIsrc: song.isrc,
                        heardTitle: item.title, heardAppleMusicId: item.appleMusicID, heardIsrc: item.isrc) {
                        onHeard(Int64((item.predictedCurrentMatchOffset * 1000).rounded()), now)
                        self?.state = .matched
                        wait = Self.recheck
                    } else {
                        self?.state = .otherSong
                    }
                case .noMatch:
                    errors = 0
                    self?.state = .notFound
                case .error:
                    errors += 1
                    if errors >= Self.maxErrors {
                        self?.state = .unavailable
                        session.cancel()
                        return
                    }
                    wait = .seconds(5)
                }
                try? await Task.sleep(for: wait)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        session?.cancel()
        session = nil
        if state != .denied && state != .unavailable { state = .idle }
    }

    private static func requestMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }
}

/// カラオケの時計の「今」。端末の単調時計 (ms)。画面を消さないモードなので眠りは気にしない。
enum KaraokeTime {
    static func nowMs() -> Int64 {
        Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000)
    }
}
