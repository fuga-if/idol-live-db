import Foundation
import Observation
import SwiftUI

/// パーティ対戦 (1台2人・分割画面・早押し奪い合い) の進行状態。
///
/// 本家 IntroQuiz の LocalParty を 2 人ローカル専用に縮約:
/// - イントロ再生中/再生後どちらでも、各自のセルをタップして早押し (buzz)。
/// - 押した人が回答 (4択)。正解で +1 して次のラウンドへ。
/// - 不正解はそのラウンドで脱落 (eliminated)、相手に解答権が移りイントロを流し直す。
/// - 両者不正解なら答えを開示して次へ。
@Observable @MainActor
final class IntroPartySession {

    enum Phase: Sendable {
        case loading
        case playing    // 早押し受付中 (再生中/再生後どちらも)
        case buzzed     // 誰かが押して回答中
        case revealed   // 答え開示
        case finished
    }

    struct Player: Sendable {
        var name: String
        var colorHex: String
    }

    private(set) var phase: Phase = .loading
    private(set) var questions: [IntroGameQuestion] = []
    private(set) var currentIndex: Int = 0
    private(set) var scores: [Int] = [0, 0]
    /// 早押しして現在回答中のプレイヤー (nil = まだ誰も押していない)。
    private(set) var buzzedPlayer: Int? = nil
    /// このラウンドで不正解になり解答権を失ったプレイヤー。
    private(set) var eliminatedThisRound: Set<Int> = []
    /// 開示フェーズ用: 直近の解答者と正誤。
    private(set) var lastAnswerer: Int? = nil
    private(set) var lastCorrect: Bool = false

    var settings: IntroGameSettings = IntroGameSettings()

    let players: [Player] = [
        Player(name: "1P", colorHex: "3B82F6"),  // accentBlue 系
        Player(name: "2P", colorHex: "EC4899"),  // accentPink 系
    ]

    @ObservationIgnored let audio = IntroAudioEngine()
    var isPlayingIntro: Bool { audio.isPlaying }

    var currentQuestion: IntroGameQuestion? {
        questions.indices.contains(currentIndex) ? questions[currentIndex] : nil
    }

    var totalRounds: Int { questions.count }
    var roundText: String { "\(min(currentIndex + 1, totalRounds)) / \(totalRounds)" }

    /// 勝者インデックス (引き分けは nil)。
    var winner: Int? {
        if scores[0] == scores[1] { return nil }
        return scores[0] > scores[1] ? 0 : 1
    }

    // MARK: - Setup

    func generateQuestions(database: AppDatabase) async throws {
        phase = .loading
        let pool = try await database.fetchIntroDonSongs(brandIds: settings.selectedBrandIds)
        guard pool.count >= 4 else {
            questions = []
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
        currentIndex = 0
        scores = [0, 0]
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

    // MARK: - Playback (共通エンジンに委譲)

    func playCurrentIntro() async {
        guard let q = currentQuestion else { return }
        // 再生が終わっても .playing のまま早押しを受け付ける (本家と同じ)。
        audio.play(
            appleMusicId: q.appleMusicId,
            previewUrl: q.previewUrl.flatMap(URL.init(string:)),
            duration: settings.introDuration
        ) {}
    }

    func stopPlayback() { audio.stop() }
    func continueIntro() { audio.continuePlaying() }
    func pauseHeldIntro() { audio.pauseHeld() }
    func replayIntro() async { await playCurrentIntro() }

    // MARK: - Buzz / Answer

    /// 早押し。受付中で未脱落・誰も押していなければ受理。
    func buzz(player: Int) {
        guard phase == .playing else { return }
        guard players.indices.contains(player) else { return }
        guard buzzedPlayer == nil, !eliminatedThisRound.contains(player) else { return }
        buzzedPlayer = player
        stopPlayback()
        phase = .buzzed
    }

    /// 押した人の回答。正解で加点して開示、不正解は脱落させ相手へ解答権。
    func submitAnswer(player: Int, title: String) {
        guard phase == .buzzed, buzzedPlayer == player, let q = currentQuestion else { return }
        if title == q.title {
            scores[player] += 1
            lastAnswerer = player
            lastCorrect = true
            phase = .revealed
        } else {
            eliminatedThisRound.insert(player)
            buzzedPlayer = nil
            lastAnswerer = player
            lastCorrect = false
            // 両者脱落なら答えを開示。片方残っていれば流し直して解答権を渡す。
            if eliminatedThisRound.count >= players.count {
                phase = .revealed
            } else {
                phase = .playing
                Task { await playCurrentIntro() }
            }
        }
    }

    /// どちらも分からない → 答えを開示。
    func giveUp() {
        guard phase == .playing || phase == .buzzed else { return }
        stopPlayback()
        buzzedPlayer = nil
        lastAnswerer = nil
        lastCorrect = false
        phase = .revealed
    }

    // MARK: - Navigation

    func nextRound() async {
        guard phase == .revealed else { return }
        buzzedPlayer = nil
        eliminatedThisRound = []
        lastAnswerer = nil
        lastCorrect = false
        let next = currentIndex + 1
        if next >= questions.count {
            stopPlayback()
            phase = .finished
        } else {
            currentIndex = next
            phase = .playing
            await playCurrentIntro()
        }
    }

    func reset() {
        stopPlayback()
        phase = .loading
        questions = []
        currentIndex = 0
        scores = [0, 0]
        buzzedPlayer = nil
        eliminatedThisRound = []
        lastAnswerer = nil
        lastCorrect = false
    }
}
