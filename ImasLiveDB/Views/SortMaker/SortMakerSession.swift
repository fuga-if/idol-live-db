import Foundation

// =============================================================================
// ソートメーカーの対象・途中保存。
//
// 並べ替えの状態はコア (`sortMakerReplay`) が「シード + 答えの列」から毎回作り直すので、
// 保存するのは対象の id 列・シード・答えだけ。1 戦答えるたびに書き、曲とアイドルで 1 件ずつ持つ。
// 終わったセッションも消さずに残し、ハブと設定画面の「前回の結果」に使う。
// =============================================================================

/// 何を並べるか。
enum SortMakerSubject: String, Codable, CaseIterable, Identifiable {
    case song
    case idol

    var id: String { rawValue }

    /// ハブ・ナビタイトル・共有文の見出し。
    var title: String {
        switch self {
        case .song: return "好きな曲ソート"
        case .idol: return "好きなアイドルソート"
        }
    }

    /// ティアー表のナビタイトル。
    var tierTitle: String {
        switch self {
        case .song: return "曲のティアー表"
        case .idol: return "アイドルのティアー表"
        }
    }

    /// 「128曲」「52人」の助数詞。
    var counter: String {
        switch self {
        case .song: return "曲"
        case .idol: return "人"
        }
    }

    var systemImage: String {
        switch self {
        case .song: return "music.note"
        case .idol: return "person.fill"
        }
    }
}

/// 上位何位まで決めるか。
enum SortMakerDepth: Int, Codable, CaseIterable, Identifiable {
    case top10 = 10
    case all = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .top10: return "ベスト10"
        case .all: return "全順位"
        }
    }
}

/// 保存しておくセッション。
struct SortMakerSession: Codable, Identifiable, Hashable {
    let subject: SortMakerSubject
    /// 対象の id 列 (曲 id / アイドル id)。コアの添字はこの並びの位置。
    let itemIds: [String]
    let seed: UInt64
    /// 0 = 全順位。
    let topK: Int
    /// 設定画面で絞った範囲の説明 (「シャニマス・ソロ曲」)。結果と共有文に出す。
    let scopeLabel: String
    /// 答えの列。L / R / T の 1 文字ずつ。
    var answers: String
    /// 終わった時点の上位 3 件の表示名 (ハブの「前回の 1 位」用)。
    var topNames: [String] = []
    var isFinished: Bool = false
    var savedAt: Date

    var id: SortMakerSubject { subject }

    var choices: [SortMakerChoice] { answers.compactMap(SortMakerChoice.init(code:)) }

    /// コアで今の状態を作り直す。
    func replay() -> SortMakerState {
        sortMakerReplay(itemCount: UInt32(itemIds.count), topK: UInt32(topK), seed: seed, answers: choices)
    }
}

extension SortMakerChoice {
    init?(code: Character) {
        switch code {
        case "L": self = .left
        case "R": self = .right
        case "T": self = .tie
        default: return nil
        }
    }

    var code: Character {
        switch self {
        case .left: return "L"
        case .right: return "R"
        case .tie: return "T"
        }
    }
}

@MainActor
@Observable
final class SortMakerStore {
    static let shared = SortMakerStore()

    private let key = "sort_maker_sessions_v1"
    private(set) var sessions: [SortMakerSubject: SortMakerSession] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SortMakerSession].self, from: data) {
            sessions = Dictionary(decoded.map { ($0.subject, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    func session(_ subject: SortMakerSubject) -> SortMakerSession? { sessions[subject] }

    func save(_ s: SortMakerSession) {
        sessions[s.subject] = s
        persist()
    }

    func clear(_ subject: SortMakerSubject) {
        guard sessions.removeValue(forKey: subject) != nil else { return }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(sessions.values)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
