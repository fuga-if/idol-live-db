import Foundation
import Observation
import AVFoundation
import MediaPlayer

/// イントロ再生の共通エンジン (ソロ/Rush/パーティで共用)。
///
/// /dev/intro (本家 IntroQuiz) の MusicService の手法を踏襲:
/// - **preview 優先**: 30 秒プレビュー URL を AVPlayer で鳴らす (本家 preferPreviewMode 既定 ON)。
///   カタログのフル再生 (MPMusicPlayerController.setQueue) は毎曲ネットワーク取得が走り
///   ラグ/無音の原因になるため、preview_url があるならそちらを使う (= サクサク)。
/// - **次曲プリフェッチ**: 次に出す曲の AVPlayerItem を裏でバッファしておき (prefetch)、
///   出題時はその item を再利用して待ち時間ゼロで鳴らす (本家 prefetchUpcoming 相当)。
/// - **鳴り始め待ち**: timeControlStatus==.playing を待ってから stop タイマーを開始
///   (play 直後の固定 sleep は起動レイテンシでイントロ長が不安定になる)。
/// - 再生世代トークンで古い非同期処理を破棄。
/// - preview_url が無い曲のみカタログのフル再生にフォールバック。
@Observable @MainActor
final class IntroAudioEngine {

    private(set) var isPlaying: Bool = false

    @ObservationIgnored private var playSession: Int = 0
    @ObservationIgnored private var previewPlayer: AVPlayer? = nil
    @ObservationIgnored private var endObserver: NSObjectProtocol? = nil
    @ObservationIgnored private var startTask: Task<Void, Never>? = nil
    @ObservationIgnored private var onFinished: (() -> Void)? = nil
    @ObservationIgnored private var usedFullPlayer = false
    @ObservationIgnored private lazy var musicPlayer = MPMusicPlayerController.applicationMusicPlayer

    // 次曲プリフェッチ (本家 prefetchUpcoming 相当): 鳴らさず item をバッファしておく。
    @ObservationIgnored private var prefetchedURL: URL? = nil
    @ObservationIgnored private var prefetchedItem: AVPlayerItem? = nil
    @ObservationIgnored private var prefetchPlayer: AVPlayer? = nil

    private static let previewPlayHardCap: UInt64 = 5_000_000_000  // preview 鳴り始め上限 (5s)
    private static let previewWaitStep: UInt64 = 50_000_000        // ポーリング間隔 (50ms)
    private static let playingWaitCap: UInt64 = 3_000_000_000      // フル再生 鳴り始め上限 (3s)
    private static let playWaitStep: UInt64 = 50_000_000

    // MARK: - 次曲プリフェッチ

    /// 次に出題しそうな曲の preview を裏でバッファしておく (再生はしない)。
    /// 出題時に同 URL なら item を再利用して即再生できる。
    func prefetch(previewUrl: URL?) {
        guard let url = previewUrl, url != prefetchedURL else { return }
        prefetchPlayer?.replaceCurrentItem(with: nil)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)   // play() しない → readyToPlay までバッファ
        player.volume = 0
        prefetchedURL = url
        prefetchedItem = item
        prefetchPlayer = player
    }

    private func consumePrefetched(_ url: URL) -> AVPlayerItem? {
        guard url == prefetchedURL, let item = prefetchedItem else { return nil }
        prefetchPlayer?.replaceCurrentItem(with: nil)
        prefetchPlayer = nil
        prefetchedItem = nil
        prefetchedURL = nil
        return item
    }

    // MARK: - 再生

    /// イントロを頭出し再生。`duration == nil` は停止タイマーを張らず stop() まで流す
    /// (Rush の「押すまで流す」用)。duration 経過/失敗/シミュレータで onFinished を 1 回呼ぶ。
    func play(appleMusicId: String, previewUrl: URL?, duration: TimeInterval?,
              onFinished: @escaping () -> Void) {
        stop()
        self.onFinished = onFinished
        let session = playSession

        #if targetEnvironment(simulator)
        finish(session: session)
        #else
        // preview 優先 (サクサク)。無い曲のみカタログのフル再生にフォールバック。
        if let url = previewUrl {
            playPreview(url: url, duration: duration, session: session)
        } else if MusicKitService.shared.hasAppleMusicSubscription, !appleMusicId.isEmpty {
            playFull(appleMusicId: appleMusicId, duration: duration, session: session)
        } else {
            finish(session: session)
        }
        #endif
    }

    /// preview URL を AVPlayer で再生。プリフェッチ済み item があれば再利用して即鳴らす。
    private func playPreview(url: URL, duration: TimeInterval?, session: Int) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = consumePrefetched(url) ?? AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = 1.0
        previewPlayer = player
        usedFullPlayer = false
        isPlaying = true

        // 30 秒プレビューの自然終端で確実に止める (duration > 残尺のとき)。
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.previewPlayer === player else { return }
                self.finish(session: session)
            }
        }

        player.play()

        startTask = Task {
            // 鳴り始め (.playing) か真の失敗 (.failed) を待つ。.failed のみ即終了。
            var waited: UInt64 = 0
            var failed = false
            while waited < Self.previewPlayHardCap {
                if Task.isCancelled || session != self.playSession { return }
                if item.status == .failed { failed = true; break }
                if player.timeControlStatus == .playing { break }
                try? await Task.sleep(nanoseconds: Self.previewWaitStep)
                waited += Self.previewWaitStep
            }
            if Task.isCancelled || session != self.playSession { return }
            if failed { self.finish(session: session); return }
            guard let duration else { return }   // 押すまで流す: 自動停止しない
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled || session != self.playSession { return }
            self.finish(session: session)
        }
    }

    /// preview_url が無い曲のフォールバック: カタログをフル再生。
    private func playFull(appleMusicId: String, duration: TimeInterval?, session: Int) {
        usedFullPlayer = true
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        musicPlayer.setQueue(with: [appleMusicId])
        musicPlayer.prepareToPlay()
        musicPlayer.currentPlaybackTime = 0
        musicPlayer.play()
        isPlaying = true

        startTask = Task {
            var waited: UInt64 = 0
            while waited < Self.playingWaitCap {
                if Task.isCancelled || session != self.playSession { return }
                if self.musicPlayer.playbackState == .playing { break }
                try? await Task.sleep(nanoseconds: Self.playWaitStep)
                waited += Self.playWaitStep
            }
            if Task.isCancelled || session != self.playSession { return }
            guard let duration else { return }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled || session != self.playSession { return }
            self.finish(session: session)
        }
    }

    /// 再生を止めて終了通知 (現役世代のみ・重複/競合安全)。
    private func finish(session: Int) {
        guard session == playSession else { return }
        #if !targetEnvironment(simulator)
        if usedFullPlayer { musicPlayer.pause() }
        #endif
        previewPlayer?.pause()
        isPlaying = false
        onFinished?()
    }

    /// 再生を完全停止し世代を進める (進行中の非同期再生を無効化)。プリフェッチは保持。
    func stop() {
        playSession += 1
        startTask?.cancel()
        startTask = nil
        if let token = endObserver {
            NotificationCenter.default.removeObserver(token)
            endObserver = nil
        }
        #if !targetEnvironment(simulator)
        if usedFullPlayer { musicPlayer.pause() }
        #endif
        previewPlayer?.pause()
        previewPlayer = nil
        isPlaying = false
    }

    /// 「もう少し流す」: 停止タイマー無しで現在位置から再生継続 (本家 playUntilStopped 相当)。
    func continuePlaying() {
        startTask?.cancel()
        startTask = nil
        #if !targetEnvironment(simulator)
        if usedFullPlayer { musicPlayer.play() }
        #endif
        previewPlayer?.play()
        isPlaying = true
    }

    /// 長押しを離したら一時停止 (世代は進めない = 現在位置を保持)。
    func pauseHeld() {
        #if !targetEnvironment(simulator)
        if usedFullPlayer { musicPlayer.pause() }
        #endif
        previewPlayer?.pause()
        isPlaying = false
    }
}
