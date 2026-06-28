import Foundation

// =============================================================================
// ゲームの軽量プログレス永続化 (UserDefaults)。サーバ非依存・端末ローカルのみ。
// - 各ゲームの「直近スコア」「最高スコア」「プレイ回数」を記録 → ハブのカードに表示。
// - 「デイリーチャレンジ」= 1日1回どれかのゲームを遊んだら達成。連続達成日数 (ストリーク) を数える。
//   月曜ミーム通知と同じく「毎日開く理由」を作るのが狙い。
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

/// 1 ゲーム分の記録。
struct GameRecord: Codable, Sendable {
    var lastScore: Int = 0
    var lastOutOf: Int = 0
    var bestScore: Int = 0
    var bestOutOf: Int = 0
    var playCount: Int = 0

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

    /// 連続デイリー達成日数。
    private(set) var streak = 0
    /// 通算デイリー達成日数。
    private(set) var totalDays = 0
    /// 最後にデイリーを達成した日 (YYYY-MM-DD)。未達成は nil。
    private(set) var lastClearedDay: String?

    private init() { load() }

    // MARK: - 参照

    func record(for kind: GameKind) -> GameRecord { records[kind] ?? GameRecord() }

    /// 今日デイリーチャレンジを達成済みか。
    var didClearToday: Bool { lastClearedDay == Self.today() }

    /// ストリークが「今日途切れていないか」。昨日までクリアしていて今日未達なら継続中、
    /// それより古ければ 0 として扱う (表示用)。
    var displayStreak: Int {
        guard let last = lastClearedDay else { return 0 }
        if last == Self.today() || last == Self.yesterday() { return streak }
        return 0
    }

    // MARK: - 記録

    /// ゲーム結果を記録する。score/outOf は「正解数 / 出題数」。
    /// 同時に当日のデイリーチャレンジ達成 + ストリーク更新を行う。
    func recordResult(_ kind: GameKind, score: Int, outOf: Int) {
        guard outOf > 0 else { return }
        var rec = record(for: kind)
        rec.lastScore = score
        rec.lastOutOf = outOf
        rec.playCount += 1
        // 最高記録は正答率で比較 (出題数が違っても公平に)。
        let newRate = Double(score) / Double(outOf)
        let bestRate = rec.bestOutOf > 0 ? Double(rec.bestScore) / Double(rec.bestOutOf) : -1
        if newRate > bestRate {
            rec.bestScore = score
            rec.bestOutOf = outOf
        }
        records[kind] = rec
        registerDailyClear()
        save()
    }

    /// プレイ完了をデイリー達成として登録し、連続日数を更新する。
    private func registerDailyClear() {
        let today = Self.today()
        guard lastClearedDay != today else { return }  // 1 日 1 回だけカウント
        if lastClearedDay == Self.yesterday() {
            streak += 1
        } else {
            streak = 1  // 連続が途切れた → リスタート
        }
        lastClearedDay = today
        totalDays += 1
    }

    // MARK: - 永続化

    private struct StreakState: Codable {
        var streak: Int
        var totalDays: Int
        var lastClearedDay: String?
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: recordsKey),
           let decoded = try? JSONDecoder().decode([GameKind: GameRecord].self, from: data) {
            records = decoded
        }
        if let data = UserDefaults.standard.data(forKey: streakKey),
           let s = try? JSONDecoder().decode(StreakState.self, from: data) {
            streak = s.streak
            totalDays = s.totalDays
            lastClearedDay = s.lastClearedDay
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
        let s = StreakState(streak: streak, totalDays: totalDays, lastClearedDay: lastClearedDay)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: streakKey)
        }
    }

    // MARK: - 日付ヘルパ (端末ローカル YYYY-MM-DD)

    static func today(_ date: Date = Date()) -> String { dayKey(date) }
    static func yesterday(_ date: Date = Date()) -> String {
        dayKey(Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date)
    }
    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
