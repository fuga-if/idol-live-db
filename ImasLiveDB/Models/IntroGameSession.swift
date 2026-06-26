import Foundation
import Observation
import MusicKit
import AVFoundation

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

struct IntroGameSettings: Sendable {
    var questionCount: Int = 10
    var introDuration: TimeInterval = 5.0
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

    func playCurrentIntro() async {
        guard let q = currentQuestion else { return }

        cancelPlayback()
        isPlayingIntro = false

        // シミュレータでは ApplicationMusicPlayer / MPMusicPlayerController が
        // 動作せず、 触ると "MPMusicPlayerController is not available on the simulator"
        // で fail する。 catch しても pause() 等で二次クラッシュを起こすため、
        // シミュレータでは再生処理自体を完全にスキップして答え選択画面に進める。
        #if targetEnvironment(simulator)
        self.phase = .answering
        return
        #else
        let duration = settings.introDuration

        // Apple Music 未加入の場合は preview_url を AVPlayer で再生する。
        // Apple Music 加入済みなら ApplicationMusicPlayer でフル再生。
        if MusicKitService.shared.hasAppleMusicSubscription {
            playWithApplicationMusicPlayer(appleMusicId: q.appleMusicId, duration: duration)
        } else if let previewURLString = q.previewUrl, let url = URL(string: previewURLString) {
            playWithPreviewPlayer(url: url, duration: duration)
        } else {
            // 再生不能 → 即座に回答フェーズへ
            phase = .answering
        }
        #endif
    }

    private func playWithApplicationMusicPlayer(appleMusicId: String, duration: TimeInterval) {
        playbackTask = Task {
            do {
                let request = MusicCatalogResourceRequest<MusicKit.Song>(
                    matching: \.id,
                    equalTo: MusicItemID(rawValue: appleMusicId)
                )
                let response = try await request.response()

                guard let song = response.items.first else {
                    self.phase = .answering
                    return
                }

                guard !Task.isCancelled else { return }

                try? AVAudioSession.sharedInstance().setCategory(.playback)
                try? AVAudioSession.sharedInstance().setActive(true)

                ApplicationMusicPlayer.shared.queue = [song]
                try await ApplicationMusicPlayer.shared.play()

                guard !Task.isCancelled else {
                    ApplicationMusicPlayer.shared.pause()
                    return
                }

                self.isPlayingIntro = true
                try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

                guard !Task.isCancelled else { return }

                ApplicationMusicPlayer.shared.pause()
                self.isPlayingIntro = false
                self.phase = .answering

            } catch {
                ApplicationMusicPlayer.shared.pause()
                self.isPlayingIntro = false
                if !(error is CancellationError) {
                    self.phase = .answering
                }
            }
        }
    }

    private func playWithPreviewPlayer(url: URL, duration: TimeInterval) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        previewPlayer?.pause()
        if let token = previewEndObserver {
            NotificationCenter.default.removeObserver(token)
            previewEndObserver = nil
        }
        let player = AVPlayer(url: url)
        previewPlayer = player
        player.play()
        isPlayingIntro = true

        playbackTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            } catch {
                // cancel された場合はそのまま抜ける
                return
            }
            guard !Task.isCancelled else { return }
            self.previewPlayer?.pause()
            self.isPlayingIntro = false
            self.phase = .answering
        }
    }

    func stopPlayback() {
        cancelPlayback()
        #if !targetEnvironment(simulator)
        ApplicationMusicPlayer.shared.pause()
        #endif
        previewPlayer?.pause()
        if let token = previewEndObserver {
            NotificationCenter.default.removeObserver(token)
            previewEndObserver = nil
        }
        isPlayingIntro = false
    }

    private func cancelPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
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
