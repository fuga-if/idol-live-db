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
    /// 利用者が付けた表の名前 (nil = 「好きな曲ティアー表」等の既定)。
    var title: String? = nil
    /// 段ごとの名前の上書き (添字は段。nil / 範囲外 = S〜D の既定名)。
    var tierLabels: [String?]? = nil
    var savedAt: Date

    var id: SortMakerSubject { subject }

    var unplacedIds: [String] { itemIds.filter { placements[$0] == nil } }

    func ids(inTier tier: Int) -> [String] {
        itemIds.filter { placements[$0] == tier }
    }

    /// 見出し・共有に出す表の名前。
    var displayTitle: String { displayTitle(ignoringCustom: false) }

    /// `ignoringCustom` なら利用者の名前を無視した既定の名前 (入力欄の見本用)。
    func displayTitle(ignoringCustom: Bool) -> String {
        if !ignoringCustom, let title { return title }
        return subject == .song ? "好きな曲ティアー表" : "好きなアイドルティアー表"
    }

    /// 段の名前 (上書きがあればそれ、無ければコアの既定名)。
    func label(ofTier index: Int, default defaultLabel: String) -> String {
        guard let labels = tierLabels, labels.indices.contains(index), let custom = labels[index] else {
            return defaultLabel
        }
        return custom
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
