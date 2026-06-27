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
    case allSongs // 全曲チャレンジ: 全曲出し切るまで終わらない、タイムと正答率を競う
    case party    // 1台2人・分割対戦 (早押し奪い合い)
}

/// 回答方式。ユーザーが切替可能。音声不可/未許可時は choices にフォールバック。
enum IntroAnswerMode: String, Sendable, CaseIterable {
    case choices  // 4択タップ
    case voice    // 音声で曲名を発話
}

/// 再生方式。フル再生=Apple Musicカタログの実イントロ(頭出し)、プレビュー=30秒クリップ(サクサク)。
enum IntroPlaybackMode: String, Sendable, CaseIterable {
    case full     // 実イントロ (要サブスク)
    case preview  // 30秒プレビュー (高速)
}

struct IntroGameSettings: Sendable {
    var mode: IntroGameMode = .normal
    var answerMode: IntroAnswerMode = .choices
    var playback: IntroPlaybackMode = .full
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
    /// 連続正解数 (本家のコンボ表示用)。正解で+1、不正解/スキップで0。
    private(set) var combo: Int = 0
    private(set) var bestCombo: Int = 0
    private(set) var records: [IntroAnswerRecord] = []
    private(set) var selectedTitle: String? = nil
    private(set) var isCorrect: Bool? = nil
    /// Rush モードの残り時間 (秒)。UI のカウントダウン表示用。
    private(set) var rushRemaining: TimeInterval = 0
    /// 全曲チャレンジ等の経過タイム (秒)。完走時に確定。タイムと正答率を競う用。
    private(set) var elapsedTime: TimeInterval = 0
    @ObservationIgnored private var sessionStart: Date? = nil

    /// 全曲チャレンジか (全曲を出し切るまで終わらない・タイムを競う)。
    var isAllSongsChallenge: Bool { settings.mode == .allSongs }

    /// プレイ中の現在経過秒 (ライブ表示用)。完走後は確定値 elapsedTime を返す。
    var elapsedSoFar: TimeInterval {
        if elapsedTime > 0 { return elapsedTime }
        return sessionStart.map { Date().timeIntervalSince($0) } ?? 0
    }
    /// Rush の回答エフェクト用シグナル (tick が増えるたびに UI が○/✕を一瞬出す)。
    private(set) var rushFlashTick: Int = 0
    private(set) var rushFlashCorrect: Bool = false

    var settings: IntroGameSettings = IntroGameSettings()

    /// 曲一覧の絞り込みをそのまま出題プールに使う場合のプリセット (nil ならブランド条件でDB取得)。
    @ObservationIgnored var presetPool: [Song]? = nil

    /// IntroDon 出題に使える曲だけに絞る (apple_music_id あり・親曲でない)。
    static func playable(_ songs: [Song]) -> [Song] {
        songs.filter { ($0.appleMusicId?.isEmpty == false) && $0.parentSongId == nil }
    }

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
        audio.preferFull = settings.playback == .full
        questions = []
        currentIndex = 0
        score = 0
        combo = 0
        bestCombo = 0
        records = []
        selectedTitle = nil
        isCorrect = nil

        // プリセット (曲一覧の絞り込み) があればそれを使う。無ければブランド条件でDB取得。
        let pool = try presetPool.map { Self.playable($0) }
            ?? database.fetchIntroDonSongs(brandIds: settings.selectedBrandIds)

        guard pool.count >= 4 else {
            phase = .idle
            return
        }

        // Rush / 全曲チャレンジ は選択ブランドの全曲をプール。Normal は questionCount 問。
        let count = (settings.mode == .rush || settings.mode == .allSongs) ? pool.count : settings.questionCount
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
        elapsedTime = 0
        newBestTimeAchieved = false
        sessionStart = Date()
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

    /// 高速形式 (押すまで流す・選択肢常時・即次へ)。Rush と 全曲チャレンジ。
    var isFastFlow: Bool { settings.mode == .rush || settings.mode == .allSongs }

    func playCurrentIntro() async {
        guard let q = currentQuestion else { return }
        // 高速形式は「押すまで流す」(duration=nil)。通常は introDuration で自動停止。
        let fast = isFastFlow
        audio.play(
            appleMusicId: q.appleMusicId,
            previewUrl: q.previewUrl.flatMap(URL.init(string:)),
            duration: fast ? nil : settings.introDuration
        ) { [weak self] in
            guard let self else { return }
            if !fast, self.phase == .playing { self.phase = .answering }
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

    /// 音声判定の録音へ引き継ぐ前に、再生を完全停止しオーディオセッションを解放する。
    func releasePlaybackForRecording() {
        audio.releaseForRecording()
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
        if correct {
            score += 1
            combo += 1
            bestCombo = max(bestCombo, combo)
        } else {
            combo = 0
        }
        records.append(IntroAnswerRecord(id: q.id, title: q.title, selectedTitle: title, correct: correct))
        // 高速形式 (Rush/全曲) は正解画面を出さず ○/✕ エフェクトで即次へ。
        if settings.mode == .rush {
            flashRush(correct: correct)
            advanceRush()
        } else if settings.mode == .allSongs {
            flashRush(correct: correct)
            advanceAllSongs()
        } else {
            phase = .revealed
        }
    }

    func skipQuestion() {
        guard let q = currentQuestion else { return }
        stopPlayback()
        selectedTitle = nil
        isCorrect = false
        combo = 0
        records.append(IntroAnswerRecord(id: q.id, title: q.title, selectedTitle: nil, correct: false))
        if settings.mode == .rush {
            advanceRush()
        } else if settings.mode == .allSongs {
            advanceAllSongs()
        } else {
            phase = .revealed
        }
    }

    /// 全曲チャレンジ: 高速で次へ。最後まで行ったら完走 (タイム確定)。
    private func advanceAllSongs() {
        selectedTitle = nil
        isCorrect = nil
        let next = currentIndex + 1
        if next >= questions.count {
            stopPlayback()
            if let s = sessionStart { elapsedTime = Date().timeIntervalSince(s) }
            phase = .finished
            saveBestScore()
            saveBestTime()
        } else {
            currentIndex = next
            phase = .playing
            Task { await playCurrentIntro() }
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
            if let s = sessionStart { elapsedTime = Date().timeIntervalSince(s) }
            phase = .finished
            saveBestScore()
            if isAllSongsChallenge { saveBestTime() }
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
        combo = 0
        bestCombo = 0
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
        switch settings.mode {
        case .rush:
            return "introDonBestScore_rush_\(String(format: "%g", settings.rushTimeLimit))s"
        case .allSongs:
            return "introDonBestScore_allsongs"
        default:
            return "introDonBestScore_\(String(format: "%g", settings.introDuration))s_\(settings.questionCount)q"
        }
    }

    private func saveBestScore() {
        let key = bestScoreKey
        if score > UserDefaults.standard.integer(forKey: key) {
            UserDefaults.standard.set(score, forKey: key)
        }
    }

    // MARK: - Best Time (全曲チャレンジ: タイムを競う)

    /// 全曲チャレンジのベストタイム (秒)。0 = 未記録。ブランド選択ごとに別管理。
    private var bestTimeKey: String {
        let brands = settings.selectedBrandIds.map { $0.sorted().joined(separator: ",") } ?? "all"
        return "introDonBestTime_\(brands)"
    }

    var bestTime: TimeInterval {
        UserDefaults.standard.double(forKey: bestTimeKey)
    }

    /// 今回が自己ベストタイム更新だったか (保存時に確定。結果画面はこれを見る)。
    private(set) var newBestTimeAchieved = false

    private func saveBestTime() {
        let prev = UserDefaults.standard.double(forKey: bestTimeKey)
        if elapsedTime > 0, prev == 0 || elapsedTime < prev {
            newBestTimeAchieved = true
            UserDefaults.standard.set(elapsedTime, forKey: bestTimeKey)
        }
    }
}
