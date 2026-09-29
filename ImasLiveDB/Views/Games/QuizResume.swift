import Foundation

// =============================================================================
// 途中でやめたクイズの「つづきから」。
//
// 出題はどれもシード付きでコアが一括生成するので、途中の状態は「シード + 設定 + 何問目まで
// 答えたか + 積み上げ」だけ保存すれば、同じ出題を作り直して続きから再開できる
// (問題そのものは保存しない。歌詞は JASRAC の条件で端末に貯めない)。
// 1 問答えるたびに保存し、最後まで遊ぶか新しく始めたら消す。ゲームごとに 1 件。
// イントロドンは音源の再生状態を持つので対象外。
// =============================================================================

/// 保存しておく途中経過。
struct QuizSuspended: Codable, Identifiable {
    let kind: GameKind
    /// 出題を作り直すシード。
    let seed: UInt64
    let brandIds: [String]
    /// 次に出す問題の位置 (歌詞クイズは出題順の中の位置。歌詞の無い曲を飛ばすので答えた数とずれる)。
    let nextIndex: Int
    /// コアの積み上げ (`QuizTally`)。メンバーカラーは当てた人数 / 答えた人数。
    let asked: Int
    let correct: Int
    let points: Int
    /// ペンライト・連続正解・見直すの元。
    let plays: [QuizStagePlay]
    /// 全問数 (一覧の「Q.06 / 10」)。
    let total: Int
    /// 歌詞クイズの形式 (`LyricsQuizModeSetting.rawValue`)。
    var lyricsMode: String? = nil
    /// メンバーカラーの難易度 (0/1/2)。
    var difficulty: Int? = nil
    /// メンバーカラーの遊び方 ("choice" = 4択 / "match" = 並べる)。古い保存は並べる。
    var colorMode: String? = nil
    let savedAt: Date

    var id: GameKind { kind }

    var tally: QuizTally {
        QuizTally(asked: UInt32(clamping: asked), correct: UInt32(clamping: correct),
                  points: UInt32(clamping: points))
    }
}

@MainActor
@Observable
final class QuizResumeStore {
    static let shared = QuizResumeStore()

    private let key = "quiz_suspended_v1"
    private(set) var sessions: [GameKind: QuizSuspended] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([QuizSuspended].self, from: data) {
            sessions = Dictionary(decoded.map { ($0.kind, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    /// いちばん最近中断したもの (ゲーム一覧の「つづきから」)。
    var latest: QuizSuspended? { sessions.values.max { $0.savedAt < $1.savedAt } }

    func suspended(_ kind: GameKind) -> QuizSuspended? { sessions[kind] }

    func save(_ s: QuizSuspended) {
        sessions[s.kind] = s
        persist()
    }

    func clear(_ kind: GameKind) {
        guard sessions.removeValue(forKey: kind) != nil else { return }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(sessions.values)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
