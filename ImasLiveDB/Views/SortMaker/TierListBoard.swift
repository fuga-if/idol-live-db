import Foundation

// =============================================================================
// ティアー表の保存。曲とアイドルで 1 枚ずつ。
//
// 並べるのは利用者の手 (好みの判断を機械に任せない)。コアが持つのは段の並びと色、
// ソートメーカーの順位からのたたき台 (`tierListAssignFromRanking`) だけ。
// =============================================================================

struct TierListBoard: Codable, Identifiable, Hashable {
    let subject: SortMakerSubject
    /// 対象の id 列 (未分類の並び順にも使う)。
    let itemIds: [String]
    /// id → 段の添字 (0 = S)。載っていない id は未分類。
    var placements: [String: Int]
    let scopeLabel: String
    /// ソートメーカーの結果から作ったときのたたき台 (「たたき台に戻す」用)。
    var suggested: [String: Int]? = nil
    var savedAt: Date

    var id: SortMakerSubject { subject }

    var unplacedIds: [String] { itemIds.filter { placements[$0] == nil } }

    func ids(inTier tier: Int) -> [String] {
        itemIds.filter { placements[$0] == tier }
    }
}

extension TierListBoard {
    /// ソートメーカーの結果からたたき台を作る。
    static func fromRanking(subject: SortMakerSubject, scopeLabel: String,
                            rows: [(rank: Int, item: SortMakerItem)]) -> TierListBoard {
        let tiers = tierListAssignFromRanking(ranks: rows.map { UInt32($0.rank) })
        var placements: [String: Int] = [:]
        for (row, tier) in zip(rows, tiers) { placements[row.item.id] = Int(tier) }
        return TierListBoard(subject: subject, itemIds: rows.map(\.item.id), placements: placements,
                             scopeLabel: scopeLabel, suggested: placements, savedAt: Date())
    }
}

@MainActor
@Observable
final class TierListStore {
    static let shared = TierListStore()

    private let key = "tier_list_boards_v1"
    private(set) var boards: [SortMakerSubject: TierListBoard] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([TierListBoard].self, from: data) {
            boards = Dictionary(decoded.map { ($0.subject, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    func board(_ subject: SortMakerSubject) -> TierListBoard? { boards[subject] }

    func save(_ b: TierListBoard) {
        boards[b.subject] = b
        persist()
    }

    func clear(_ subject: SortMakerSubject) {
        guard boards.removeValue(forKey: subject) != nil else { return }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(boards.values)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
