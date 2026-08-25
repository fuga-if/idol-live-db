import Foundation

// =============================================================================
// ゲームの軽量プログレス永続化 (UserDefaults)。サーバ非依存・端末ローカルのみ。
// - 各ゲームの「直近スコア」「最高スコア」「プレイ回数」を記録 → ハブのカードに表示。
// - 「デイリーチャレンジ」= 1日1回どれかのゲームを遊んだら達成。連続達成日数 (ストリーク) を数える。
//   月曜ミーム通知と同じく「毎日開く理由」を作るのが狙い。
//
// 更新規則 (自己ベストの比較・連続達成の加算・記録しない条件) は imas-core の
// `domain/game_progress.rs` が単独で持つ。ここに残すのは **保存の実体** だけで、
// ストアは「読む → コアに渡す → 返ってきた値を書く」に徹する
// (同じ規則を iOS/Android の 2 実装に置くと片方だけ直った時に食い違うため)。
// =============================================================================

/// ハブが束ねるゲームの識別子。rawValue は永続キー兼用なので変更しない。
enum GameKind: String, CaseIterable, Codable, Sendable {
    case introDon
    case idolQuiz
    case songSingerQuiz
    case colorMatch

    /// 表示名 (リザルト・シェア文言で使う)。
    var displayName: String {
        switch self {
        case .introDon:       return "イントロドン"
        case .idolQuiz:       return "アイドル当てクイズ"
        case .songSingerQuiz: return "ソロ曲クイズ"
        case .colorMatch:     return "カラーマッチ"
        }
    }

    /// 0–100 の正規化スコア (正答率) を扱うゲームか。それ以外は「点」をそのまま表示。
    var scoreIsPercent: Bool {
        switch self {
        case .colorMatch: return true
        case .introDon, .idolQuiz, .songSingerQuiz: return false
        }
    }
}

// 1 ゲーム分の記録 `GameRecord` と連続記録 `GameStreakState` の型は imas-core の
// 生成バインディングにある (保存キー game_records_v1 / game_streak_v1 の中身そのもの)。

extension GameRecord {
    /// 1 度でも遊んだか (ハブのカードが「未プレイ」を出すかの判定)。
    /// コアの `has_played()` と同義だが、保存値 1 つを見るだけの述語に FFI 往復を
    /// 足す価値がないので FFI 面には出ていない。表示分岐用にここで持つ。
    var hasPlayed: Bool { playCount > 0 }
}

/// ゲーム横断のローカル進捗ストア。
@Observable @MainActor
final class GameProgressStore {
    static let shared = GameProgressStore()

    private let recordsKey = "game_records_v1"
    private let streakKey = "game_streak_v1"

    /// ゲーム別レコード。
    private(set) var records: [GameKind: GameRecord] = [:]

    /// 連続デイリー達成の保存値 (連続日数・通算日数・最後に達成した端末ローカル日)。
    private(set) var streakState = GameStreakState(streak: 0, totalDays: 0, lastClearedDay: nil)

    private init() { load() }

    // MARK: - 参照

    /// 未プレイのゲームの初期値 (コアの `GameRecord::default()` と同じゼロ値)。
    private static let emptyRecord = GameRecord(lastScore: 0, lastOutOf: 0, bestScore: 0,
                                                bestOutOf: 0, playCount: 0)

    func record(for kind: GameKind) -> GameRecord { records[kind] ?? Self.emptyRecord }

    /// 自己ベストの正答率 (0–100)。まだ記録が無ければ nil
    /// (「—」を出すか今回の率で代用するかは画面ごとに違うので、文言には落とさない)。
    func bestRatePercent(for kind: GameKind) -> Int? {
        gameProgressBestRatePercent(record: record(for: kind)).map(Int.init)
    }

    /// 連続デイリー達成日数 (保存値そのもの)。表示には `displayStreak` を使う。
    var streak: Int { Int(streakState.streak) }
    /// 通算デイリー達成日数。
    var totalDays: Int { Int(streakState.totalDays) }
    /// 最後にデイリーを達成した日 (端末ローカル YYYY-MM-DD)。未達成は nil。
    var lastClearedDay: String? { streakState.lastClearedDay }

    /// 今日デイリーチャレンジを達成済みか。
    var didClearToday: Bool {
        gameProgressDidClearToday(streak: streakState, todayKey: DailyPick.dayKey())
    }

    /// ストリークが「今日途切れていないか」を織り込んだ表示用の連続日数。
    var displayStreak: Int {
        Int(gameProgressDisplayStreak(streak: streakState,
                                      todayKey: DailyPick.dayKey(),
                                      yesterdayKey: DailyPick.previousDayKey()))
    }

    // MARK: - 記録

    /// ゲーム結果を記録する。score/outOf は「正解ポイント / 満点」。
    /// 同時に当日のデイリーチャレンジ達成 + ストリーク更新を行う。
    ///
    /// 戻り値の `isNewBest` が結果画面の「自己ベスト更新！」バッジ。判定は best を
    /// 上書きする前に済ませる必要があり、その順序ごとコア側で固定されている
    /// (画面が「読む → 判定 → 書く」を自前で並べると順序を崩した瞬間に恒久的に false になる)。
    @discardableResult
    func recordResult(_ kind: GameKind, score: Int, outOf: Int) -> GameProgressUpdate {
        // 連続クリア日数は「そのユーザーの 1 日」が単位なので端末ローカル日 (`DailyPick`)。
        // 公演日との比較に使う `JSTDay` (JST 固定) とは意味が違う。
        let update = gameProgressApplyResult(
            record: record(for: kind),
            streak: streakState,
            score: Int32(clamping: score),
            outOf: Int32(clamping: outOf),
            todayKey: DailyPick.dayKey(),
            yesterdayKey: DailyPick.previousDayKey())
        // 記録として成立しなかった場合 (出題 0 問) は保存値が入力と同値なので書かない。
        guard update.didRecord else { return update }
        records[kind] = update.record
        streakState = update.streak
        save()
        return update
    }

    // MARK: - 永続化

    /// UserDefaults に入っている JSON の形。コアの `GameRecord` は FFI 型で Codable を
    /// 持たないので、出荷済みの保存形 (キー名・順序) を固定する DTO をここに置く。
    /// フィールド名を変えると既存ユーザの記録が読めなくなる。
    private struct StoredRecord: Codable {
        var lastScore: Int
        var lastOutOf: Int
        var bestScore: Int
        var bestOutOf: Int
        var playCount: Int

        init(_ r: GameRecord) {
            lastScore = Int(r.lastScore)
            lastOutOf = Int(r.lastOutOf)
            bestScore = Int(r.bestScore)
            bestOutOf = Int(r.bestOutOf)
            playCount = Int(r.playCount)
        }

        var record: GameRecord {
            GameRecord(lastScore: Int32(clamping: lastScore), lastOutOf: Int32(clamping: lastOutOf),
                       bestScore: Int32(clamping: bestScore), bestOutOf: Int32(clamping: bestOutOf),
                       playCount: Int32(clamping: playCount))
        }
    }

    /// 保存キー game_streak_v1 の中身 (`GameStreakState` の保存形)。
    private struct StreakState: Codable {
        var streak: Int
        var totalDays: Int
        var lastClearedDay: String?

        init(_ s: GameStreakState) {
            streak = Int(s.streak)
            totalDays = Int(s.totalDays)
            lastClearedDay = s.lastClearedDay
        }

        var state: GameStreakState {
            GameStreakState(streak: Int32(clamping: streak), totalDays: Int32(clamping: totalDays),
                            lastClearedDay: lastClearedDay)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: recordsKey),
           let decoded = try? JSONDecoder().decode([GameKind: StoredRecord].self, from: data) {
            records = decoded.mapValues(\.record)
        }
        if let data = UserDefaults.standard.data(forKey: streakKey),
           let s = try? JSONDecoder().decode(StreakState.self, from: data) {
            streakState = s.state
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records.mapValues(StoredRecord.init)) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
        if let data = try? JSONEncoder().encode(StreakState(streakState)) {
            UserDefaults.standard.set(data, forKey: streakKey)
        }
    }
}
