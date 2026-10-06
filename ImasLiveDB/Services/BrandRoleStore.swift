import Foundation

extension Notification.Name {
    /// 担当ブランドの設定が変わった (設定画面・はじめの案内・バックアップの取り込み)。
    static let brandRolesChanged = Notification.Name("brandRolesChanged")
}

/// 担当ブランド (アプリ全体の設定)。ブランドごとに なし / 担当 / メイン の 3 段で、メインは複数可。
///
/// 端末の設定 (UserDefaults) に保存の形 (コアの `brandRolesToJson`) の文字列を 1 つ持ち、バックアップで運ぶ。
/// 空は「まだ決めていない」で、そのときはコアが記録 (担当アイドル・参加した公演) から既定を組む
/// (`brandRoleSettings`)。段の扱い・既定の組み方・保存の形はすべてコア。ここは読み書きと材料集めだけ。
enum BrandRoleStore {
    static let key = "brand_roles_json"
    /// はじめの案内 (担当ブランドを選ぶシート) を出したか。スキップしても 1 度きり。
    static let promptedKey = "brand_roles_prompted"

    static var json: String { UserDefaults.standard.string(forKey: key) ?? "" }

    static var isConfigured: Bool { brandRolesConfigured(json: json) }

    /// はじめの案内を出すか (まだ決めておらず、まだ出していない)。
    static var shouldPrompt: Bool { !isConfigured && !UserDefaults.standard.bool(forKey: promptedKey) }

    static func markPrompted() {
        UserDefaults.standard.set(true, forKey: promptedKey)
    }

    static func save(_ rows: [BrandRoleRow]) {
        write(brandRolesToJson(rows: rows))
    }

    /// バックアップから戻す (保存の形のまま)。
    static func restore(json: String) {
        guard brandRolesConfigured(json: json) else { return }
        write(json)
    }

    private static func write(_ json: String) {
        UserDefaults.standard.set(json, forKey: key)
        markPrompted()
        NotificationCenter.default.post(name: .brandRolesChanged, object: nil)
    }

    /// 既定を組む材料 (ブランド・担当アイドルのブランド・参加した公演のブランド)。
    @MainActor
    static func loadRecord() async -> BrandRoleRecord {
        let c = AppContainer.shared
        let brands = (try? await c.brandReading.brands()) ?? []
        let oshiIds = (try? await c.markReading.markedEntityIds(entity: .idol, kind: .myPick)) ?? []
        let idols = oshiIds.isEmpty ? [] : ((try? await c.idolReading.idols(ids: oshiIds)) ?? [])
        let idolById = Dictionary(idols.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let refs = (try? await c.producerCards.attendedShowRefs()) ?? []
        let shows = (try? await c.producerCards.showInfos(ids: refs.map(\.showId))) ?? [:]
        return BrandRoleRecord(
            today: JSTDay.today(),
            brands: brands.map {
                BrandRoleBrand(id: $0.id, label: $0.shortName, color: $0.color, sortOrder: Int64($0.sortOrder))
            },
            oshiBrandIds: oshiIds.compactMap { idolById[$0]?.brandId },
            visits: refs.map { BrandRoleVisit(date: $0.date, brandId: shows[$0.showId]?.brandId) }
        )
    }

    /// 今の設定 (まだ決めていなければ記録から組んだ既定)。
    @MainActor
    static func load() async -> BrandRoleSettings {
        brandRoleSettings(json: json, record: await loadRecord())
    }
}
