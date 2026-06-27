import Foundation
import OSLog

/// 担当 / お気に入り / メモ / 参加 (UserMark) を iCloud Key-Value Store に退避し、
/// 再インストール・機種変でも復元できるようにするバックアップ。
///
/// 設計 (重要・破壊しない):
/// - 端末ローカル DB が唯一の正。KVS はそのミラー (バックアップ) にすぎない。
/// - 復元は **非破壊**: ローカルに無いマークを追加するだけ。ローカルの既存マークを
///   消したり上書きしたりは一切しない。よって「アプリをバックグラウンド↔復帰」しても
///   ローカルのマークが消えることはない。
/// - KVS は端末間で自動同期し、アプリ削除後も iCloud 上に残る (= 機種変でも復元可)。
@MainActor
final class UserMarkBackup {
    static let shared = UserMarkBackup()

    private let store = NSUbiquitousKeyValueStore.default
    private let key = "user_marks_backup_v1"
    private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "mark_backup")

    private struct Payload: Codable {
        var marks: [UserMark]
        var updatedAt: Double
    }

    private init() {}

    /// 現在のローカル全マークを KVS にミラーする (上書き)。マーク変更のたびに呼ぶ。
    func backup(_ marks: [UserMark]) {
        do {
            let data = try JSONEncoder().encode(Payload(marks: marks, updatedAt: Date().timeIntervalSince1970))
            store.set(data, forKey: key)
            store.synchronize()
        } catch {
            logger.error("backup encode failed: \(error.localizedDescription)")
        }
    }

    /// KVS のバックアップ済みマークを読む (無ければ nil)。
    func loadBackup() -> [UserMark]? {
        guard let data = store.data(forKey: key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return payload.marks
    }

    /// 診断用: KVS に入っているマーク件数 (iCloud から同期されたものを反映するため synchronize 後)。
    func backedUpCount() -> Int {
        store.synchronize()
        return loadBackup()?.count ?? 0
    }

    /// 他端末での更新を受け取るための監視を開始する。
    func startObserving(_ onExternalChange: @escaping @MainActor () -> Void) {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { _ in
            Task { @MainActor in onExternalChange() }
        }
        store.synchronize()
    }
}
