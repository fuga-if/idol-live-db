import Foundation
import Observation
import AVFoundation
import MediaPlayer

enum IntroGamePhase: Sendable {
    case idle
    case loading
    case playing
    case answering
    case revealed
    case finished
}

struct IntroAnswerRecord: Identifiable, Sendable {
    let id: String
    let title: String
    let selectedTitle: String?
    let correct: Bool
}

/// ゲームモード (本家 IntroQuiz 準拠)。
enum IntroGameMode: String, Sendable, CaseIterable {
    case normal   // 固定問数
    case rush     // 制限時間内に連続出題、正解数を競う
    case party    // 1台2人・分割対戦 (早押し奪い合い)
}

/// 回答方式。ユーザーが切替可能。音声不可/未許可時は choices にフォールバック。
enum IntroAnswerMode: String, Sendable, CaseIterable {
    case choices  // 4択タップ
    case voice    // 音声で曲名を発話
}

struct IntroGameSettings: Sendable {
    var mode: IntroGameMode = .normal
    var answerMode: IntroAnswerMode = .choices
    var questionCount: Int = 10
    var introDuration: TimeInterval = 5.0
    /// Rush の制限時間 (秒)。mode == .rush のとき使用。
    var rushTimeLimit: TimeInterval = 60
    var selectedBrandIds: Set<String>? = nil
}

@Observable @MainActor
final class IntroGameSession {

    private(set) var phase: IntroGamePhase = .idle
    private(set) var questions: [IntroGameQuestion] = []
    private(set) var currentIndex: Int = 0
    private(set) var score: Int = 0
    private(set) var records: [IntroAnswerRecord] = []
    private(set) var selectedTitle: String? = nil
    private(set) var isCorrect: Bool? = nil
    private(set) var isPlayingIntro: Bool = false

    var settings: IntroGameSettings = IntroGameSettings()

    private var playbackTask: Task<Void, Never>? = nil
    private var previewPlayer: AVPlayer? = nil
    private var previewEndObserver: NSObjectProtocol? = nil

    // /dev/intro (本家 IntroQuiz) の MusicService の安定パターンを移植:
    // - 再生世代トークン: 新しい再生/停止指示ごとに +1。非同期処理は自分の世代が現役か
    //   を確認してから副作用を起こす (問題の高速遷移で古い再生が次の問題を汚さない)。
    // - 鳴り始め (playbackState/timeControlStatus == .playing) を待ってから停止タイマー開始
    //   (play() 直後に固定 sleep すると起動レイテンシでイントロ長が不安定 = 主因だった)。
    private var playSession: Int = 0
    // MPMusicPlayerController.applicationMusicPlayer は ApplicationMusicPlayer(MusicKit) より
    // setQueue(storeIDs:) で catalog 即キュー可能 (毎問の MusicCatalogResourceRequest が不要)。
    // アクセス自体に副作用があるため lazy で初回フル再生時のみ生成する。
    @ObservationIgnored private lazy var musicPlayer = MPMusicPlayerController.applicationMusicPlayer

    private static let playingWaitCap: UInt64 = 3_000_000_000   // 鳴り始め待ちの上限 (3s)
    private static let previewPlayHardCap: UInt64 = 5_000_000_000 // preview 鳴り始め上限 (5s)
    private static let playWaitStep: UInt64 = 50_000_000          // ポーリング間隔 (50ms)

    var currentQuestion: IntroGameQuestion? {
        questions.indices.contains(currentIndex) ? questions[currentIndex] : nil
    }

    var totalCount: Int { questions.count }

    var progressText: String { "\(currentIndex + 1) / \(totalCount)" }

    // MARK: - Start

    func generateQuestions(database: AppDatabase) async throws {
        phase = .loading
        questions = []
        currentIndex = 0
        score = 0
        records = []
        selectedTitle = nil
        isCorrect = nil

        let pool = try database.fetchIntroDonSongs(brandIds: settings.selectedBrandIds)

        guard pool.count >= 4 else {
            phase = .idle
            return
        }

        questions = Array(pool.shuffled().prefix(settings.questionCount)).map { song in
            IntroGameQuestion(
                id: song.id,
                title: song.title,
                brandId: song.brandId,
                appleMusicId: song.appleMusicId ?? "",
                previewUrl: song.previewUrl,
                artworkUrl: song.artworkUrl,
                choices: makeChoices(for: song, pool: pool)
            )
        }

        phase = .playing
        await playCurrentIntro()
    }

    private func makeChoices(for song: Song, pool: [Song]) -> [String] {
        let wrongs = pool
            .filter { $0.id != song.id && $0.title != song.title }
            .shuffled()
            .prefix(3)
            .map(\.title)
        var choices = wrongs + [song.title]
        choices.shuffle()
        return choices
    }

    // MARK: - Playback

    private var usedFullPlayer = false

    func playCurrentIntro() async {
        guard let q = currentQuestion else { return }
        stopPlayback()                  // 直前の再生を確実に止め、世代を進める
        let session = playSession

        // シミュレータでは MPMusicPlayerController が使えず触るとクラッシュするため、
        // 再生処理自体をスキップして回答フェーズへ進める。
        #if targetEnvironment(simulator)
        phase = .answering
        return
        #else
        let duration = settings.introDuration
        // Apple Music 加入: MPMusicPlayerController で catalog をフル再生。
        // 未加入/未取得: preview_url を AVPlayer で再生。どちらも無ければ即回答へ。
        if MusicKitService.shared.hasAppleMusicSubscription, !q.appleMusicId.isEmpty {
            playFullIntro(appleMusicId: q.appleMusicId, duration: duration, session: session)
        } else if let s = q.previewUrl, let url = URL(string: s) {
            playPreview(url: url, duration: duration, session: session)
        } else {
            phase = .answering
        }
        #endif
    }

    /// サブスク加入: MPMusicPlayerController で catalog を setQueue→prepareToPlay→play。
    /// **playbackState==.playing を待ってから** duration を計測する (play() 直後の固定 sleep
    /// だと起動レイテンシでイントロが短く/無音になり不安定だった = 報告された主因)。
    private func playFullIntro(appleMusicId: String, duration: TimeInterval, session: Int) {
        usedFullPlayer = true
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        musicPlayer.setQueue(with: [appleMusicId])
        musicPlayer.prepareToPlay()
        musicPlayer.currentPlaybackTime = 0
        musicPlayer.play()
        isPlayingIntro = true

        playbackTask = Task {
            var waited: UInt64 = 0
            while waited < Self.playingWaitCap {
                if Task.isCancelled || session != self.playSession { return }
                if self.musicPlayer.playbackState == .playing { break }
                try? await Task.sleep(nanoseconds: Self.playWaitStep)
                waited += Self.playWaitStep
            }
            if Task.isCancelled || session != self.playSession { return }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled || session != self.playSession { return }
            self.finishIntro(session: session)
        }
    }

    /// 非加入/プレビュー: AVPlayerItem で status を観測しつつ AVPlayer で再生。
    /// timeControlStatus==.playing を待ってから duration を計測。item.status==.failed の
    /// 真の失敗 (403/期限切れ/地域制限) は無音で尺を消費させず即回答へ。
    private func playPreview(url: URL, duration: TimeInterval, session: Int) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = 1.0
        previewPlayer = player
        isPlayingIntro = true

        // 30秒プレビューの自然終端で確実に止める (introDuration > 残尺のとき)。
        previewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishIntro(session: session) }
        }

        player.play()

        playbackTask = Task {
            var waited: UInt64 = 0
            var failed = false
            while waited < Self.previewPlayHardCap {
                if Task.isCancelled || session != self.playSession { return }
                if item.status == .failed { failed = true; break }
                if player.timeControlStatus == .playing { break }
                try? await Task.sleep(nanoseconds: Self.playWaitStep)
                waited += Self.playWaitStep
            }
            if Task.isCancelled || session != self.playSession { return }
            if failed { self.finishIntro(session: session); return }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled || session != self.playSession { return }
            self.finishIntro(session: session)
        }
    }

    /// 再生を止めて回答フェーズへ (現役世代に対してのみ・重複/競合安全)。
    private func finishIntro(session: Int) {
        guard session == playSession else { return }
        #if !targetEnvironment(simulator)
        if usedFullPlayer { musicPlayer.pause() }
        #endif
        previewPlayer?.pause()
        isPlayingIntro = false
        if phase == .playing { phase = .answering }
    }

    func stopPlayback() {
        playSession += 1            // 進行中の非同期再生を無効化 (世代を進める)
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
        isPlayingIntro = false
    }

    // MARK: - もう少し流す / リプレイ

    /// 「もう少し流す」: 再生ボタン長押し中、停止タイマー無しで現在位置から再生を継続
    /// (本家 IntroQuiz の playUntilStopped 相当)。回答フェーズ中に「あと少し聴きたい」用。
    func continueIntro() {
        playbackTask?.cancel()
        playbackTask = nil
        #if !targetEnvironment(simulator)
        if usedFullPlayer { musicPlayer.play() }
        #endif
        previewPlayer?.play()
        isPlayingIntro = true
    }

    /// 長押しを離したら一時停止する (回答フェーズに留まる)。
    func pauseHeldIntro() {
        #if !targetEnvironment(simulator)
        if usedFullPlayer { musicPlayer.pause() }
        #endif
        previewPlayer?.pause()
        isPlayingIntro = false
    }

    /// 現在の問題のイントロを頭出しして再生し直す。
    func replayIntro() async {
        await playCurrentIntro()
    }

    // MARK: - Answer

    func submitAnswer(_ title: String) {
        // 再生中 (.playing) の早押しも受け付ける。
        // 以前は .answering 限定で、 UI 上は「早押し可能！」と表示しているのに
        // submitAnswer がスキップされて入力が無視されていた。
        guard phase == .playing || phase == .answering, let q = currentQuestion else { return }
        stopPlayback()
        selectedTitle = title
        let correct = title == q.title
        isCorrect = correct
        if correct { score += 1 }
        records.append(IntroAnswerRecord(id: q.id, title: q.title, selectedTitle: title, correct: correct))
        phase = .revealed
    }

    func skipQuestion() {
        guard let q = currentQuestion else { return }
        stopPlayback()
        selectedTitle = nil
        isCorrect = false
        records.append(IntroAnswerRecord(id: q.id, title: q.title, selectedTitle: nil, correct: false))
        phase = .revealed
    }

    // MARK: - Navigation

    func nextQuestion() async {
        guard phase == .revealed else { return }
        selectedTitle = nil
        isCorrect = nil

        let next = currentIndex + 1
        if next >= questions.count {
            stopPlayback()
            phase = .finished
            saveBestScore()
        } else {
            currentIndex = next
            phase = .playing
            await playCurrentIntro()
        }
    }

    func reset() {
        stopPlayback()
        phase = .idle
        questions = []
        currentIndex = 0
        score = 0
        records = []
        selectedTitle = nil
        isCorrect = nil
    }

    // MARK: - Best Score

    var bestScore: Int {
        UserDefaults.standard.integer(forKey: bestScoreKey)
    }

    var isNewBest: Bool {
        score > 0 && score >= bestScore
    }

    private var bestScoreKey: String {
        // %g で整数は "2"、サブ秒は "0.2" になり、超イントロのベストスコアが別管理される
        // (Int だと 0.2→0 で衝突していた)。整数値の既存キーは "2" のまま維持される。
        "introDonBestScore_\(String(format: "%g", settings.introDuration))s_\(settings.questionCount)q"
    }

    private func saveBestScore() {
        let key = bestScoreKey
        if score > UserDefaults.standard.integer(forKey: key) {
            UserDefaults.standard.set(score, forKey: key)
        }
    }
}
