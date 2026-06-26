import SwiftUI

/// お知らせの既読状態をローカル (UserDefaults) に持つ。サーバー不要。
@Observable @MainActor
final class AnnouncementStore {
    static let shared = AnnouncementStore()

    private(set) var readIds: Set<String>

    private init() {
        readIds = Set(UserDefaults.standard.stringArray(forKey: AnnouncementDefaults.readKey) ?? [])
    }

    var unreadCount: Int {
        AnnouncementCatalog.all.reduce(0) { $0 + (readIds.contains($1.id) ? 0 : 1) }
    }

    func isRead(_ id: String) -> Bool { readIds.contains(id) }

    func markRead(_ id: String) {
        guard !readIds.contains(id) else { return }
        readIds.insert(id)
        persist()
    }

    func markAllRead() {
        readIds = Set(AnnouncementCatalog.all.map(\.id))
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(readIds), forKey: AnnouncementDefaults.readKey)
    }
}
