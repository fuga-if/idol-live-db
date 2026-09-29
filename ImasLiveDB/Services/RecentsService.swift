import Foundation

/// 最近見た項目の種別。
enum RecentKind: String, Codable, Sendable {
    case event
    case song
    case idol
}

/// 最近見た項目 1 件。モデル本体は持たず id/name のみ保持し、表示時に local カタログから解決する。
struct RecentItem: Codable, Identifiable, Hashable, Sendable {
    let kind: RecentKind
    let entityId: String
    let name: String

    var id: String { "\(kind.rawValue):\(entityId)" }
}

/// 最近見たイベント/曲/アイドルをローカル (UserDefaults) に記録する。
/// サーバ非依存・端末ローカルのみ。並べ方 (新しい順・同一項目は先頭へ・上限) はコアの
/// `recents_after_visit` が決める。ここは鍵 (`kind:id`) と名前の対応と保存だけ。
@Observable @MainActor
final class RecentsService {
    static let shared = RecentsService()

    private let storageKey = "recent_items_v1"

    private(set) var items: [RecentItem] = []

    private init() { load() }

    /// 項目を記録する。既存の同一 (kind,id) は取り除いて先頭に積み直す。
    func record(kind: RecentKind, id: String, name: String) {
        guard !id.isEmpty, !name.isEmpty else { return }
        let item = RecentItem(kind: kind, entityId: id, name: name)
        var byKey = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        byKey[item.id] = item
        items = recentsAfterVisit(currentKeys: items.map(\.id), visitedKey: item.id).compactMap { byKey[$0] }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RecentItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
