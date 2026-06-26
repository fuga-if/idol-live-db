import Foundation
import Observation

enum SearchScope: String {
    case songs = "search_history_songs"
    case idols = "search_history_idols"
    case events = "search_history_events"
    case submissions = "search_history_submissions"
}

@Observable
@MainActor
final class SearchHistoryManager {
    static let shared = SearchHistoryManager()

    private let maxItems = 15
    private var cache: [String: [String]] = [:]

    private init() {}

    func history(for scope: SearchScope) -> [String] {
        let key = scope.rawValue
        if let cached = cache[key] { return cached }
        let stored = UserDefaults.standard.stringArray(forKey: key) ?? []
        cache[key] = stored
        return stored
    }

    func record(query: String, scope: SearchScope) {
        var trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // クエリ文字数を100文字以内に制限
        if trimmed.count > 100 { trimmed = String(trimmed.prefix(100)) }
        let key = scope.rawValue
        var items = history(for: scope)
        items.removeAll { $0 == trimmed }
        items.insert(trimmed, at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
        cache[key] = items
        // NOTE: UserDefaults は標準で iCloud KV バックアップ対象。
        // 検索履歴はプライバシー上センシティブではないが、デバイス間同期は不要なため
        // 将来 iCloud KV Store を採用する際は本キーを除外すること。
        UserDefaults.standard.set(items, forKey: key)
    }

    func clear(scope: SearchScope) {
        let key = scope.rawValue
        cache[key] = []
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// 全スコープの検索履歴を一括削除
    func clearAll() {
        for scope in [SearchScope.songs, .idols, .events, .submissions] {
            clear(scope: scope)
        }
    }
}
