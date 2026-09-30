import Foundation

// =============================================================================
// ティアー表の保存。端末の中に何枚でも持てる (曲・アイドルごとに一覧から開き直す)。
//
// 並べるのは利用者の手 (好みの判断を機械に任せない)。コアが持つのは段の既定 (名前と色)、
// 段の数の上限、色の候補、名前の整え方、ソートメーカーの順位からのたたき台だけ。
// =============================================================================

/// 段 1 つ。並び替え・削除しても振り分けが崩れないように、振り分けは段の id で持つ。
struct TierDef: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var colorSeed: String

    init(id: String = UUID().uuidString, label: String, colorSeed: String) {
        self.id = id
        self.label = label
        self.colorSeed = colorSeed
    }

    /// コアの既定の S〜D。
    static func defaults() -> [TierDef] {
        tierListTiers().map { TierDef(label: $0.label, colorSeed: $0.colorSeed) }
    }
}

struct TierListBoard: Codable, Identifiable, Hashable {
    let id: String
    let subject: SortMakerSubject
    /// 対象の id 列 (未分類の並び順にも使う)。
    let itemIds: [String]
    /// 段 (上から)。
    var tiers: [TierDef]
    /// 項目 id → 段の id。載っていない項目は未分類。
    var placements: [String: String]
    let scopeLabel: String
    /// ソートメーカーの結果から作ったときのたたき台 (「たたき台に戻す」用)。
    var suggested: [String: String]? = nil
    /// 利用者が付けた表の名前 (nil = 「好きな曲ティアー表」等の既定)。
    var title: String? = nil
    let createdAt: Date
    var savedAt: Date

    init(subject: SortMakerSubject, itemIds: [String], scopeLabel: String,
         tiers: [TierDef] = TierDef.defaults(), placements: [String: String] = [:]) {
        self.id = UUID().uuidString
        self.subject = subject
        self.itemIds = itemIds
        self.tiers = tiers
        self.placements = placements
        self.scopeLabel = scopeLabel
        self.createdAt = Date()
        self.savedAt = Date()
    }

    var unplacedIds: [String] { itemIds.filter { tierIndex(of: $0) == nil } }
    var placedCount: Int { itemIds.count - unplacedIds.count }

    func ids(inTier tierId: String) -> [String] {
        itemIds.filter { placements[$0] == tierId }
    }

    /// 項目が今いる段の添字 (未分類・消えた段なら nil)。
    func tierIndex(of itemId: String) -> Int? {
        guard let tierId = placements[itemId] else { return nil }
        return tiers.firstIndex { $0.id == tierId }
    }

    /// 見出し・共有に出す表の名前。
    var displayTitle: String { title ?? defaultTitle }

    var defaultTitle: String {
        subject == .song ? "好きな曲ティアー表" : "好きなアイドルティアー表"
    }
}

extension TierListBoard {
    /// ソートメーカーの結果からたたき台を作る (振り分け規則はコア)。
    static func fromRanking(subject: SortMakerSubject, scopeLabel: String,
                            rows: [(rank: Int, item: SortMakerItem)]) -> TierListBoard {
        var board = TierListBoard(subject: subject, itemIds: rows.map(\.item.id), scopeLabel: scopeLabel)
        let tiers = tierListAssignFromRanking(ranks: rows.map { UInt32($0.rank) })
        for (row, tier) in zip(rows, tiers) where board.tiers.indices.contains(Int(tier)) {
            board.placements[row.item.id] = board.tiers[Int(tier)].id
        }
        board.suggested = board.placements
        return board
    }
}

@MainActor
@Observable
final class TierListStore {
    static let shared = TierListStore()

    private let key = "tier_list_boards_v2"
    private let legacyKey = "tier_list_boards_v1"
    /// 新しく触ったものが先。
    private(set) var boards: [TierListBoard] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([TierListBoard].self, from: data) {
            boards = decoded
        } else if let data = UserDefaults.standard.data(forKey: legacyKey),
                  let legacy = try? JSONDecoder().decode([LegacyTierListBoardV1].self, from: data) {
            boards = legacy.map { $0.migrated() }
            persist()
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
        sort()
    }

    func boards(for subject: SortMakerSubject) -> [TierListBoard] {
        boards.filter { $0.subject == subject }
    }

    func save(_ b: TierListBoard) {
        if let i = boards.firstIndex(where: { $0.id == b.id }) {
            boards[i] = b
        } else {
            boards.append(b)
        }
        sort()
        persist()
    }

    func delete(_ id: String) {
        boards.removeAll { $0.id == id }
        persist()
    }

    private func sort() {
        boards.sort { $0.savedAt > $1.savedAt }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(boards) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// 1 種類 1 枚・段は添字で持っていた頃の保存 (2026-10-01 の一時期だけ)。読み替えて捨てる。
private struct LegacyTierListBoardV1: Decodable {
    let subject: SortMakerSubject
    let itemIds: [String]
    let placements: [String: Int]
    let scopeLabel: String
    let suggested: [String: Int]?
    let title: String?
    let tierLabels: [String?]?
    let savedAt: Date

    func migrated() -> TierListBoard {
        var tiers = TierDef.defaults()
        for (i, label) in (tierLabels ?? []).enumerated() where tiers.indices.contains(i) {
            if let label { tiers[i].label = label }
        }
        func convert(_ m: [String: Int]) -> [String: String] {
            m.compactMapValues { tiers.indices.contains($0) ? tiers[$0].id : nil }
        }
        var board = TierListBoard(subject: subject, itemIds: itemIds, scopeLabel: scopeLabel,
                                  tiers: tiers, placements: convert(placements))
        board.suggested = suggested.map(convert)
        board.title = title
        board.savedAt = savedAt
        return board
    }
}
