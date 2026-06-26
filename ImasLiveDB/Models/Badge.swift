import SwiftUI

// MARK: - BadgeTier

enum BadgeTier: String, Codable, Sendable, CaseIterable {
    case none, bronze, silver, gold, platinum

    var label: String {
        switch self {
        case .none: return "なし"
        case .bronze: return "ブロンズ"
        case .silver: return "シルバー"
        case .gold: return "ゴールド"
        case .platinum: return "プラチナ"
        }
    }

    var color: Color {
        switch self {
        case .none: return Color(.systemGray4)
        case .bronze: return .brown
        case .silver: return Color(.systemGray)
        case .gold: return .yellow
        case .platinum: return Color(red: 0.4, green: 0.8, blue: 1.0)
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle.dashed"
        case .bronze: return "medal.fill"
        case .silver: return "medal.fill"
        case .gold: return "rosette"
        case .platinum: return "star.circle.fill"
        }
    }

    var threshold: Int {
        switch self {
        case .none: return 0
        case .bronze: return 10
        case .silver: return 50
        case .gold: return 200
        case .platinum: return 500
        }
    }
}

// MARK: - UserBadges

/// バッジ集計 (`GET /users/:id/badges`)。
///
/// 貢献度は 2 指標を「個別集計」する (合成しない。確定契約 §3):
///   - `editCount`     = 編集件数 (tier 判定の主指標。cloudkit_ok=1 かつ source='app')
///   - `goodsReceived` = 自分の編集が受けた Good 累計
///
/// `categories` は record_type 別の編集件数 (source='app' 限定)。
///
/// 契約 §1/§3: サーバは素の camelCase (`editCount` / `goodsReceived`) を直返しする。
/// 旧キー (`total_approved` / `contribution_count`) は廃止されたため別名フォールバックは持たない。
/// CodingKeys は camelCase のまま (アンダースコア無しの camelCase キーは共通 decoder の
/// `.convertFromSnakeCase` 下でも無変換で突き合うため、共通 decoder を変えずに契約へ一致)。
struct UserBadges: Codable, Sendable {
    let tier: BadgeTier
    /// 編集件数 (= サーバ `editCount`)。tier 判定の主指標。欠落時 0。
    let editCount: Int
    /// 受け取った Good 累計 (= サーバ `goodsReceived`)。欠落時 0。
    let goodsReceived: Int
    let categories: [String: Int]

    private enum CodingKeys: String, CodingKey {
        case tier, editCount, goodsReceived, categories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tier = (try c.decodeIfPresent(BadgeTier.self, forKey: .tier)) ?? .none
        editCount = (try c.decodeIfPresent(Int.self, forKey: .editCount)) ?? 0
        goodsReceived = (try c.decodeIfPresent(Int.self, forKey: .goodsReceived)) ?? 0
        categories = (try c.decodeIfPresent([String: Int].self, forKey: .categories)) ?? [:]
    }

    init(tier: BadgeTier, editCount: Int, goodsReceived: Int, categories: [String: Int]) {
        self.tier = tier
        self.editCount = editCount
        self.goodsReceived = goodsReceived
        self.categories = categories
    }
}
