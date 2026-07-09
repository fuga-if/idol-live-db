import Foundation
import Observation
import AVFoundation
import MediaPlayer
import os

/// イントロ再生の共通エンジン (ソロ/Rush/パーティで共用)。
///
/// /dev/intro (本家 IntroQuiz) の MusicService の手法を踏襲:
/// - **preview 優先**: 30 秒プレビュー URL を AVPlayer で鳴らす (本家 preferPreviewMode 既定 ON)。
///   カタログのフル再生 (MPMusicPlayerController.setQueue) は毎曲ネットワーク取得が走り
///   ラグ/無音の原因になるため、preview_url があるならそちらを使う (= サクサク)。
/// - **previewUrl は呼び出し側で既に DB から渡される** ので、本家がやる「URL先読みキャッシュ」
///   は不要。再生時に毎回 `AVPlayerItem(url:)` → `AVPlayer(playerItem:)` 新規生成。
///   AVPlayer/AVPlayerItem のプリフェッチは廃止 (item の所属 AVPlayer を後から付け替えると
///   'AVPlayerItem cannot be associated with more than one instance of AVPlayer' で SIGABRT する)。
/// - **鳴り始め待ち**: timeControlStatus==.playing を待ってから stop タイマーを開始
///   (play 直後の固定 sleep は起動レイテンシでイントロ長が不安定になる)。
/// - 再生世代トークンで古い非同期処理を破棄。
/// - preview_url が無い曲のみカタログのフル再生にフォールバック。
@Observable @MainActor
final class IntroAudioEngine {

    private(set) var isPlaying: Bool = false

    /// フル再生 (Apple Music カタログ = 実イントロ) を優先するか。
    /// false (既定) は preview 優先でサクサク。設定で切替 (本家 preferPreviewMode 相当)。
    var preferFull: Bool = false

    @ObservationIgnored private var playSession: Int = 0
    @ObservationIgnored private var previewPlayer: AVPlayer? = nil
    @ObservationIgnored private var endObserver: NSObjectProtocol? = nil
    @ObservationIgnored private var startTask: Task<Void, Never>? = nil
    @ObservationIgnored private var onFinished: (() -> Void)? = nil
    @ObservationIgnored private var usedFullPlayer = false
    @ObservationIgnored private lazy var musicPlayer: MPMusicPlayerController =
        MPMusicPlayerController.applicationMusicPlayer
    /// `beginGeneratingPlaybackNotifications()` を呼んだ回数 (end とペアにするため)。
    @ObservationIgnored private var notificationsGenerationCount: Int = 0

    /// playFull で「曲はロードできたが再生開始しなかった」appleMusicId を覚えておく集合。
    /// Apple Music カタログにフル尺が無い曲 (Orange Sapphire 等) は同じセッションで何度
    /// 引かれても同じく失敗するので、2 回目以降は 800ms 待たず直接 preview に行く。
    /// プロセス生存中のみ保持 (端末をまたいで永続化はしない)。
    @ObservationIgnored private var fullPlaybackBlacklist: Set<String> = []

    /// preload 済みのカタログ曲 ID (本家 preloadedStoreID 相当)。
    /// 答え合わせフェーズで先に setQueue + prepareToPlay を済ませておけば、
    /// ユーザが「次の問題」ボタンを押すまでの時間で prepare が完了している → 即 play() で鳴る。
    /// 重い曲 (Orange Sapphire 等) はこの「先んじた preload による prepare 時間確保」が必須。
    @ObservationIgnored private var preloadedFullId: String? = nil

    /// ユーザの Apple Music ライブラリ全曲を起動後 1 回だけスキャンしたキャッシュ
    /// (storeID → MPMediaItem)。 MPMediaPropertyPredicate は playbackStoreID で
    /// フィルタできないため、 全曲走査せざるを得ない。 数百〜数千曲想定で問題なし。
    @ObservationIgnored private var libraryByStoreID: [String: MPMediaItem]? = nil

    /// ユーザの Apple Music ライブラリから storeID で MPMediaItem を引く (本家 mediaItem 経路)。
    /// カタログのストリーミング再生 (setQueue(with: [storeID])) が失敗する曲でも、
    /// ユーザがライブラリ追加 (♡) 済みなら MPMediaItemCollection で setQueue できて
    /// MPMusicPlayer が確実に再生できる (本家での Orange Sapphire 再生はこの経路)。
    private func libraryItem(forStoreID storeID: String) -> MPMediaItem? {
        // 認可されていなければ何も返さない (権限ダイアログ未承認時)。
        guard MPMediaLibrary.authorizationStatus() == .authorized else { return nil }
        if libraryByStoreID == nil {
            var map: [String: MPMediaItem] = [:]
            let items = MPMediaQuery.songs().items ?? []
            for item in items {
                if let sid = item.value(forProperty: MPMediaItemPropertyPlaybackStoreID) as? String,
                   !sid.isEmpty {
                    map[sid] = item
                }
            }
            libraryByStoreID = map
        }
        return libraryByStoreID?[storeID]
    }

    private static let previewPlayHardCap: UInt64 = 5_000_000_000  // preview 鳴り始め上限 (5s)
    private static let previewWaitStep: UInt64 = 50_000_000        // ポーリング間隔 (50ms)
    /// フル再生 鳴り始め上限。
    /// 本家 IntroQuiz は 3 秒待つ (`playingFallback`)。 私の旧 800ms は短すぎて、
    /// CDN コールドキャッシュ + 楽曲権利チェック + IPA 解決で時間のかかる曲
    /// (Orange Sapphire 等) を「鳴る曲なのに preview に強制フォールバック」していた。
    private static let playingWaitCap: UInt64 = 3_000_000_000
    private static let playWaitStep: UInt64 = 50_000_000

    // MARK: - 次曲プリフェッチ (no-op)

    /// プリフェッチ機構は撤去 (AVPlayerItem 所属問題で SIGABRT する温床)。
    /// previewUrl は呼び出し側から直接渡されており、本家の「URL 先読みキャッシュ」も不要。
    /// 互換のため空実装を残す (呼び出し側の差分を最小化)。
    func prefetch(previewUrl: URL?) { /* no-op (旧プリフェッチ撤去) */ }

    // MARK: - 次曲フル再生 preload (本家 preloadIntro 相当)

    /// カタログ曲を先に setQueue + prepareToPlay しておく (再生開始はしない)。
    /// 答え合わせフェーズで呼んで、 ユーザ操作の時間 (数秒〜) で prepare を完了させ、
    /// 「次の問題」 押下時に startPreloaded 経路で即 play() できるようにする。
    /// 重い曲 (Orange Sapphire 等) で「prepare 完了前に play して固着」を回避する本家方式。
    func preloadFull(appleMusicId: String) {
        guard !appleMusicId.isEmpty,
              MusicKitService.shared.hasAppleMusicSubscription,
              !fullPlaybackBlacklist.contains(appleMusicId),
              appleMusicId != preloadedFullId else { return }
        // 本家準拠の入口クリーンアップ。 前問の playFull がまだポーリング中なら、 そいつが
        // 「800ms 経って .stopped」と判定して self.musicPlayer.stop() を踏み、 今打った
        // setQueue (preload) を破壊する競合があった (調査結果 §4-D)。
        playSession += 1
        startTask?.cancel()
        startTask = nil
        // MusicKitService.playFull が立てた ApplicationMusicPlayer.shared の queue 残骸が
        // MPMusicPlayer の setQueue 受付を妨げる事例があった。 IntroDon 開始時に確実にクリア
        // (`pause` だけだと残るので `stop()` 経由)。
        MusicKitService.shared.stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        musicPlayer.stop()

        // Library 経路を先に試す (ユーザがプレイリスト/ライブラリに追加済みなら最も確実)。
        // 本家で Orange Sapphire が鳴るのはこの経路。Catalog ストリーミングが失敗する曲でも
        // Library 追加済みなら MPMediaItemCollection で setQueue できて確実に鳴る。
        if let item = libraryItem(forStoreID: appleMusicId) {
            let collection = MPMediaItemCollection(items: [item])
            musicPlayer.setQueue(with: collection)
        } else {
            musicPlayer.setQueue(with: [appleMusicId])
        }
        musicPlayer.prepareToPlay()
        musicPlayer.currentPlaybackTime = 0
        preloadedFullId = appleMusicId
        // play() 入口の stop() が次に呼ばれた時、 `usedFullPlayer == true` (前問の状態)
        // のままだと `musicPlayer.stop()` を踏んで preload キューを破壊する。 preload に
        // よって状態は事実上「リセット」されたので、 ここで usedFullPlayer も false に。
        // playFull 内で改めて true を立てる。
        usedFullPlayer = false
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
        // フル再生で過去に失敗した曲は preferFull でも preview に直行 (800ms 待ち回避)。
        let blacklisted = fullPlaybackBlacklist.contains(appleMusicId)
        let canFull = MusicKitService.shared.hasAppleMusicSubscription && !appleMusicId.isEmpty && !blacklisted
        if preferFull, canFull {
            // フル再生 (実イントロを頭出し)。サブスク加入時のみ。
            // 失敗時 (サブスク配信終了/地域制限の曲: Orange Sapphire 等) は preview にフォールバック。
            playFull(appleMusicId: appleMusicId, previewFallbackUrl: previewUrl, duration: duration, session: session)
        } else if let url = previewUrl {
            // preview 優先 (サクサク)。
            playPreview(url: url, duration: duration, session: session)
        } else if canFull {
            // preview が無い曲はフル再生にフォールバック。
            playFull(appleMusicId: appleMusicId, previewFallbackUrl: nil, duration: duration, session: session)
        } else {
            finish(session: session)
        }
        #endif
    }

    /// preview URL を AVPlayer で再生 (本家相当・毎回新規生成)。
    /// previewUrl は呼び出し側から直接渡されるので URL キャッシュ不要、
    /// AVPlayer/AVPlayerItem のプリフェッチもしない (所属問題を避ける)。
    private func playPreview(url: URL, duration: TimeInterval?, session: Int) {
        // playFull と category options を揃える (.mixWithOthers)。 揃えないと preview 後の
        // セッション状態 (排他取得) が次の playFull の MPMusicPlayer 再生を妨げうる。
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = 1.0
        previewPlayer = player
        usedFullPlayer = false
        isPlaying = true

        // 30 秒プレビューの自然終端で確実に止める (duration > 残尺のとき)。
        // NotificationCenter の queue:.main は MainQueue だが Swift MainActor isolation
        // を保証しないため、MainActor.assumeIsolated はアサート失敗でクラッシュしうる
        // (特に「次の問題」遷移時に発火するケース)。Task @MainActor で安全に乗せ替える。
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.previewPlayer === player else { return }
                self.finish(session: session)
            }
        }

        player.play()

        // クラス全体は @MainActor だが Task { } は non-isolated に開始してしまうため、
        // self を触る処理 (playSession 参照・finish 呼び出し) で MainActor isolation を破る。
        // Swift 6 strict concurrency 下ではアサート失敗 → クラッシュ。@MainActor 化する。
        startTask = Task { @MainActor [weak self] in
            // 鳴り始め (.playing) か真の失敗 (.failed) を待つ。.failed のみ即終了。
            var waited: UInt64 = 0
            var failed = false
            while waited < Self.previewPlayHardCap {
                guard let self else { return }
                if Task.isCancelled || session != self.playSession { return }
                if item.status == .failed { failed = true; break }
                if player.timeControlStatus == .playing { break }
                try? await Task.sleep(nanoseconds: Self.previewWaitStep)
                waited += Self.previewWaitStep
            }
            guard let self else { return }
            if Task.isCancelled || session != self.playSession { return }
            if failed { self.finish(session: session); return }
            guard let duration else { return }   // 押すまで流す: 自動停止しない
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled || session != self.playSession { return }
            self.finish(session: session)
        }
    }

    /// preview_url が無い曲のフォールバック / preferFull 設定時のメイン再生: カタログをフル再生。
    /// 鳴り始めなかった場合 (サブスク配信終了/地域制限の曲) は preview にフォールバック。
    ///
    /// 本家準拠の 2 段構え:
    /// - 既に `preloadFull(appleMusicId:)` で setQueue + prepareToPlay 済みなら即 play() する
    ///   (preload は通常「答え合わせフェーズ」で打たれて prepare に数秒の余裕がある)
    /// - preload 済みでないなら旧経路 (同関数内 setQueue + 1秒待ち + play) にフォールバック
    private func playFull(appleMusicId: String, previewFallbackUrl: URL?,
                          duration: TimeInterval?, session: Int) {
        usedFullPlayer = true
        let preloaded = (preloadedFullId == appleMusicId)

        if !preloaded {
            // preload が間に合わなかった経路。 同関数内で setup する (フォールバック)。
            // ここも Library 経路を優先する。
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try? AVAudioSession.sharedInstance().setActive(true)
            musicPlayer.stop()
            if let item = libraryItem(forStoreID: appleMusicId) {
                musicPlayer.setQueue(with: MPMediaItemCollection(items: [item]))
            } else {
                musicPlayer.setQueue(with: [appleMusicId])
            }
            musicPlayer.prepareToPlay()
            musicPlayer.currentPlaybackTime = 0
        }
        preloadedFullId = nil   // 消費したのでクリア
        isPlaying = true

        // クラス全体は @MainActor だが Task { } は non-isolated に開始。@MainActor 化する。
        startTask = Task { @MainActor [weak self] in
            // preload 済みなら prepare はもう完了しているので 0 待ちで play() を呼べる。
            // preload なしなら同関数内 setQueue 直後なので 1 秒待って prepare 完了を保証。
            if !preloaded {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let s0 = self else { return }
            if Task.isCancelled || session != s0.playSession { return }
            // 本家準拠: 再生指示の直前に毎回 begin… を打って MPMusicPlayer の再生エンジンを
            // 「起こし直す」。 重い catalog 曲 (Orange Sapphire 等) で .stopped 固着しがちな
            // のは「再生エンジンが寝ている」状態で play() を踏むのが原因の仮説。
            s0.musicPlayer.beginGeneratingPlaybackNotifications()
            s0.notificationsGenerationCount += 1
            s0.musicPlayer.play()

            var waited: UInt64 = 0
            while waited < Self.playingWaitCap {
                guard let self else { return }
                if Task.isCancelled || session != self.playSession { return }
                if self.musicPlayer.playbackState == .playing { break }
                try? await Task.sleep(nanoseconds: Self.playWaitStep)
                waited += Self.playWaitStep
            }
            guard let self else { return }
            let pbState = self.musicPlayer.playbackState
            let nowPlaying = self.musicPlayer.nowPlayingItem?.title ?? "nil"
            if Task.isCancelled || session != self.playSession { return }
            // 起動 cap に達しても .playing にならない = サブスクで再生不可 (Orange Sapphire等)。
            // preview にフォールバック、無ければ無音を流さず即終了。
            // musicPlayer.pause() だけだとキューが残って次の preview が干渉することがある。
            // stop() + 空キュー化で完全に手放してから preview に切り替える。
            if self.musicPlayer.playbackState != .playing {
                // 同セッション内で同じ曲が再度引かれても 800ms 待ちを繰り返さない。
                self.fullPlaybackBlacklist.insert(appleMusicId)
                self.musicPlayer.stop()
                self.musicPlayer.setQueue(with: [])
                self.usedFullPlayer = false
                if let url = previewFallbackUrl {
                    self.playPreview(url: url, duration: duration, session: session)
                } else {
                    self.finish(session: session)
                }
                return
            }
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

    /// 再生を完全停止し世代を進める (進行中の非同期再生を無効化)。
    /// 本家準拠: musicPlayer も `pause()` でなく `stop()` で完全に手放す。
    /// pause だけだと前 queue が残って次の setQueue で衝突することがある (重い曲の固着原因)。
    func stop() {
        playSession += 1
        startTask?.cancel()
        startTask = nil
        if let token = endObserver {
            NotificationCenter.default.removeObserver(token)
            endObserver = nil
        }
        #if !targetEnvironment(simulator)
        // 一度でもフル再生に使ったことがあれば queue が乗ってる可能性 → 確実に stop。
        if usedFullPlayer { musicPlayer.stop() }
        // begin/end のペアを揃える (本家準拠)。 begin したまま放置すると通知配信が
        // 残り続け、 次の begin との二重打ちで MediaPlayer.framework が不整合を起こす。
        if notificationsGenerationCount > 0 {
            musicPlayer.endGeneratingPlaybackNotifications()
            notificationsGenerationCount -= 1
        }
        #endif
        previewPlayer?.pause()
        previewPlayer = nil
        isPlaying = false
    }

    /// 録音(音声判定)へ引き継ぐ前に再生を完全停止しセッションを解放する。
    /// pause だけだとシステム音楽プレイヤー(MPMusicPlayerController)が生き残り、
    /// 録音エンジン稼働中にオーディオ衝突で SIGTRAP する。本家の musicPlayback.stop+deactivate 相当。
    func releaseForRecording() {
        stop()
        #if !targetEnvironment(simulator)
        // フル再生を実際に使った時だけ MPMusicPlayerController に触れる。preview のみの曲で
        // ここを無条件に呼ぶと applicationMusicPlayer が lazy 生成され、録音エンジンと衝突する。
        if usedFullPlayer { musicPlayer.stop() }
        #endif
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 「もう少し流す」(長押し中): 停止タイマー無しで現在位置から再生継続。
    /// 押してる間ずっと流れ続け、 pauseHeld() で止める。
    func continuePlaying() {
        startTask?.cancel()
        startTask = nil
        #if !targetEnvironment(simulator)
        if usedFullPlayer { musicPlayer.play() }
        #endif
        previewPlayer?.play()
        isPlaying = true
    }

    /// 「続きから」(タップ): 現在位置から再生再開して duration 秒経過で自動停止。
    /// 長押しの continuePlaying() と違い、 タップは「もう一度ちょこっと聞きたい」 用なので
    /// 指定秒で勝手に止まる挙動が正しい (ずっと流れ続けるとユーザは何度も停止操作を強いられる)。
    func continueForDuration(_ duration: TimeInterval) {
        startTask?.cancel()
        startTask = nil
        #if !targetEnvironment(simulator)
        if usedFullPlayer { musicPlayer.play() }
        #endif
        previewPlayer?.play()
        isPlaying = true
        let session = playSession
        startTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let self else { return }
            if Task.isCancelled || session != self.playSession { return }
            self.finish(session: session)
        }
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
