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
    /// Rush モードの残り時間 (秒)。UI のカウントダウン表示用。
    private(set) var rushRemaining: TimeInterval = 0
    /// Rush の回答エフェクト用シグナル (tick が増えるたびに UI が○/✕を一瞬出す)。
    private(set) var rushFlashTick: Int = 0
    private(set) var rushFlashCorrect: Bool = false

    var settings: IntroGameSettings = IntroGameSettings()

    @ObservationIgnored private var rushTimerTask: Task<Void, Never>? = nil

    /// イントロ再生は共通エンジンに委譲 (ソロ/Rush/パーティで同一の安定ロジックを共有)。
    @ObservationIgnored let audio = IntroAudioEngine()

    /// 再生中フラグはエンジンの状態をそのまま反映 (UI は従来どおり session.isPlayingIntro を見る)。
    var isPlayingIntro: Bool { audio.isPlaying }

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

        // Rush は時間で終わるため尽きないよう多めに用意 (尽きたら先頭へ wrap)。
        let count = settings.mode == .rush ? min(pool.count, 300) : settings.questionCount
        questions = Array(pool.shuffled().prefix(count)).map { song in
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
        if settings.mode == .rush { startRushTimer() }
        await playCurrentIntro()
    }

    // MARK: - Rush

    private func startRushTimer() {
        rushRemaining = settings.rushTimeLimit
        let deadline = Date().addingTimeInterval(settings.rushTimeLimit)
        rushTimerTask?.cancel()
        rushTimerTask = Task {
            while !Task.isCancelled {
                let remaining = deadline.timeIntervalSinceNow
                rushRemaining = max(0, remaining)
                if remaining <= 0 { finishRush(); return }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func finishRush() {
        rushTimerTask?.cancel()
        rushTimerTask = nil
        stopPlayback()
        phase = .finished
        saveBestScore()
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

    // MARK: - Playback (共通エンジンに委譲)

    func playCurrentIntro() async {
        guard let q = currentQuestion else { return }
        // Rush は「押すまで流す」(duration=nil)。それ以外は introDuration で自動停止。
        let isRush = settings.mode == .rush
        audio.play(
            appleMusicId: q.appleMusicId,
            previewUrl: q.previewUrl.flatMap(URL.init(string:)),
            duration: isRush ? nil : settings.introDuration
        ) { [weak self] in
            guard let self else { return }
            if !isRush, self.phase == .playing { self.phase = .answering }
        }
        prefetchNext()
    }

    /// 次に出題する曲の preview を裏で先読みしておく (本家 prefetchUpcoming 相当)。
    private func prefetchNext() {
        guard !questions.isEmpty else { return }
        let nextIndex = settings.mode == .rush
            ? (currentIndex + 1) % questions.count
            : currentIndex + 1
        guard questions.indices.contains(nextIndex) else { return }
        audio.prefetch(previewUrl: questions[nextIndex].previewUrl.flatMap(URL.init(string:)))
    }

    func stopPlayback() {
        audio.stop()
    }

    // MARK: - もう少し流す / リプレイ

    /// 「もう少し流す」: 再生ボタン長押し中、停止タイマー無しで現在位置から再生を継続。
    func continueIntro() {
        audio.continuePlaying()
    }

    /// 長押しを離したら一時停止する (回答フェーズに留まる)。
    func pauseHeldIntro() {
        audio.pauseHeld()
    }

    /// 「わかった！」: 再生を止めて回答フェーズへ (本家の buzz 相当)。Rush では使わない。
    func buzzToAnswer() {
        guard phase == .playing, settings.mode != .rush else { return }
        stopPlayback()
        phase = .answering
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
        // Rush は正解画面を出さず、○/✕ エフェクトだけ出して即次へ。
        if settings.mode == .rush {
            flashRush(correct: correct)
            advanceRush()
        } else {
            phase = .revealed
        }
    }

    func skipQuestion() {
        guard let q = currentQuestion else { return }
        stopPlayback()
        selectedTitle = nil
        isCorrect = false
        records.append(IntroAnswerRecord(id: q.id, title: q.title, selectedTitle: nil, correct: false))
        if settings.mode == .rush {
            advanceRush()
        } else {
            phase = .revealed
        }
    }

    /// Rush: 正解画面を挟まず次の出題へ即移行 (尽きたら先頭へ wrap)。
    private func advanceRush() {
        currentIndex = questions.isEmpty ? 0 : (currentIndex + 1) % questions.count
        selectedTitle = nil
        isCorrect = nil
        phase = .playing
        Task { await playCurrentIntro() }
    }

    /// Rush の○/✕フラッシュ用シグナル。tick 変化を UI が監視してエフェクトを出す。
    private func flashRush(correct: Bool) {
        rushFlashCorrect = correct
        rushFlashTick += 1
    }

    // MARK: - Navigation

    func nextQuestion() async {
        guard phase == .revealed else { return }
        selectedTitle = nil
        isCorrect = nil

        // Rush: 終了は rushTimerTask が .finished にする。ここでは出題を回し続ける (尽きたら先頭へ)。
        if settings.mode == .rush {
            currentIndex = questions.isEmpty ? 0 : (currentIndex + 1) % questions.count
            phase = .playing
            await playCurrentIntro()
            return
        }

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
        rushTimerTask?.cancel()
        rushTimerTask = nil
        rushRemaining = 0
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
        settings.mode == .rush
            ? "introDonBestScore_rush_\(String(format: "%g", settings.rushTimeLimit))s"
            : "introDonBestScore_\(String(format: "%g", settings.introDuration))s_\(settings.questionCount)q"
    }

    private func saveBestScore() {
        let key = bestScoreKey
        if score > UserDefaults.standard.integer(forKey: key) {
            UserDefaults.standard.set(score, forKey: key)
        }
    }
}
