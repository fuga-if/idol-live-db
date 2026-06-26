import Foundation
import Observation
import AVFoundation
import MediaPlayer

/// イントロ再生の共通エンジン (ソロ/Rush/パーティで共用)。
///
/// /dev/intro (本家 IntroQuiz) の MusicService の安定パターンを移植:
/// - 再生世代トークン: 新しい再生/停止指示ごとに +1。非同期処理は自分の世代が現役かを
///   確認してから副作用を起こす (問題の高速遷移で古い再生が次の問題を汚さない)。
/// - 鳴り始め (playbackState/timeControlStatus == .playing) を待ってから停止タイマー開始
///   (play() 直後に固定 sleep すると起動レイテンシでイントロ長が不安定 = 報告された主因)。
///
/// 「再生 → duration 経過で onFinished」だけを責務とし、フェーズ遷移や採点は呼び出し側が持つ。
@Observable @MainActor
final class IntroAudioEngine {

    private(set) var isPlaying: Bool = false

    @ObservationIgnored private var playbackTask: Task<Void, Never>? = nil
    @ObservationIgnored private var previewPlayer: AVPlayer? = nil
    @ObservationIgnored private var previewEndObserver: NSObjectProtocol? = nil
    @ObservationIgnored private var playGen: Int = 0
    @ObservationIgnored private var usedFullPlayer = false
    // duration 経過/失敗時に呼ぶハンドラ。@MainActor 隔離内でのみ保持・呼び出しするため
    // クロージャを跨いで送らない (Swift 6 strict concurrency の sending 違反を避ける)。
    @ObservationIgnored private var onFinished: (() -> Void)? = nil
    // MPMusicPlayerController.applicationMusicPlayer は ApplicationMusicPlayer(MusicKit) より
    // setQueue(storeIDs:) で catalog 即キュー可能 (毎問の MusicCatalogResourceRequest が不要)。
    // アクセス自体に副作用があるため lazy で初回フル再生時のみ生成する。
    @ObservationIgnored private lazy var musicPlayer = MPMusicPlayerController.applicationMusicPlayer

    private static let playingWaitCap: UInt64 = 3_000_000_000    // 鳴り始め待ちの上限 (3s)
    private static let previewPlayHardCap: UInt64 = 5_000_000_000 // preview 鳴り始め上限 (5s)
    private static let playWaitStep: UInt64 = 50_000_000          // ポーリング間隔 (50ms)

    /// 現在の問題のイントロを頭出し再生。duration 経過 (または失敗/シミュレータ) で onFinished を呼ぶ。
    /// `duration == nil` のときは停止タイマーを張らず、stop() されるまで流し続ける
    /// (Rush モードの「押すまで流す」用)。onFinished は現役世代のときだけ MainActor 上で呼ばれる。
    func play(appleMusicId: String, previewUrl: URL?, duration: TimeInterval?,
              onFinished: @escaping () -> Void) {
        stop()                  // 直前の再生を確実に止め、世代を進める
        self.onFinished = onFinished
        let gen = playGen

        // シミュレータでは MPMusicPlayerController が使えず触るとクラッシュするため、
        // 再生処理自体をスキップして即終了扱いにする。
        #if targetEnvironment(simulator)
        finish(gen: gen)
        #else
        // Apple Music 加入: MPMusicPlayerController で catalog をフル再生。
        // 未加入/未取得: preview_url を AVPlayer で再生。どちらも無ければ即終了。
        if MusicKitService.shared.hasAppleMusicSubscription, !appleMusicId.isEmpty {
            playFull(appleMusicId: appleMusicId, fallbackPreview: previewUrl, duration: duration, gen: gen)
        } else if let url = previewUrl {
            playPreview(url: url, duration: duration, gen: gen)
        } else {
            finish(gen: gen)
        }
        #endif
    }

    /// サブスク加入: MPMusicPlayerController で catalog を setQueue→prepareToPlay→play。
    /// **playbackState==.playing を待ってから** duration を計測する。
    private func playFull(appleMusicId: String, fallbackPreview: URL?, duration: TimeInterval?, gen: Int) {
        usedFullPlayer = true
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        musicPlayer.setQueue(with: [appleMusicId])
        musicPlayer.prepareToPlay()
        musicPlayer.currentPlaybackTime = 0
        musicPlayer.play()
        isPlaying = true

        playbackTask = Task {
            var waited: UInt64 = 0
            while waited < Self.playingWaitCap {
                if Task.isCancelled || gen != self.playGen { return }
                if self.musicPlayer.playbackState == .playing { break }
                try? await Task.sleep(nanoseconds: Self.playWaitStep)
                waited += Self.playWaitStep
            }
            if Task.isCancelled || gen != self.playGen { return }
            // フル再生が始まらない (カタログ未提供/地域制限/権利切れ等) → プレビューにフォールバック。
            // これをしないと apple_music_id はあるのに無音になる曲が出る (報告された再生不能バグ)。
            if self.musicPlayer.playbackState != .playing {
                self.musicPlayer.pause()
                self.usedFullPlayer = false
                if let url = fallbackPreview {
                    self.playPreview(url: url, duration: duration, gen: gen)
                } else {
                    self.finish(gen: gen)
                }
                return
            }
            guard let duration else { return }   // 押すまで流す: 自動停止しない
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled || gen != self.playGen { return }
            self.finish(gen: gen)
        }
    }

    /// 非加入/プレビュー: AVPlayerItem で status を観測しつつ AVPlayer で再生。
    /// timeControlStatus==.playing を待ってから duration を計測。item.status==.failed の
    /// 真の失敗 (403/期限切れ/地域制限) は無音で尺を消費させず即終了。
    private func playPreview(url: URL, duration: TimeInterval?, gen: Int) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = 1.0
        previewPlayer = player
        isPlaying = true

        // 30秒プレビューの自然終端で確実に止める (duration > 残尺のとき)。
        previewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(gen: gen) }
        }

        player.play()

        playbackTask = Task {
            var waited: UInt64 = 0
            var failed = false
            while waited < Self.previewPlayHardCap {
                if Task.isCancelled || gen != self.playGen { return }
                if item.status == .failed { failed = true; break }
                if player.timeControlStatus == .playing { break }
                try? await Task.sleep(nanoseconds: Self.playWaitStep)
                waited += Self.playWaitStep
            }
            if Task.isCancelled || gen != self.playGen { return }
            if failed { self.finish(gen: gen); return }
            guard let duration else { return }   // 押すまで流す: 自動停止しない (自然終端は observer 任せ)
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled || gen != self.playGen { return }
            self.finish(gen: gen)
        }
    }

    /// 再生を止めて終了通知 (現役世代に対してのみ・重複/競合安全)。
    private func finish(gen: Int) {
        guard gen == playGen else { return }
        #if !targetEnvironment(simulator)
        if usedFullPlayer { musicPlayer.pause() }
        #endif
        previewPlayer?.pause()
        isPlaying = false
        let handler = onFinished
        handler?()
    }

    /// 再生を完全停止し世代を進める (進行中の非同期再生を無効化)。
    func stop() {
        playGen += 1
        playbackTask?.cancel()
        playbackTask = nil
        if let token = previewEndObserver {
            NotificationCenter.default.removeObserver(token)
            previewEndObserver = nil
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
        playbackTask?.cancel()
        playbackTask = nil
        #if !targetEnvironment(simulator)
        if usedFullPlayer { musicPlayer.play() }
        #endif
        previewPlayer?.play()
        isPlaying = true
    }

    /// 長押しを離したら一時停止する (世代は進めない = 現在位置を保持)。
    func pauseHeld() {
        #if !targetEnvironment(simulator)
        if usedFullPlayer { musicPlayer.pause() }
        #endif
        previewPlayer?.pause()
        isPlaying = false
    }
}
