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
///
/// **共有コアに委譲していない理由** (docs/SHARED_CORE_STUDY.md §4-B1 の線引き):
/// このクラスに残っているのは iCloud KVS という **iOS 専用 transport の入出力だけ**で、
/// 判定も集計も持っていない。ミラーの中身は `[UserMark]` をそのまま `JSONEncoder` に
/// 通した端末内部形式で、`BackupExportImportService` の envelope (iOS/Android 共通契約・
/// checksum つき) とは別物。共有コア (`domain/backup_summary.rs`) が扱うのは後者だけなので、
/// ここを載せ替えると KVS に既に載っている過去のバックアップが読めなくなる。
/// 「ローカルに無い行だけ足す」非破壊マージの本体は `AppDatabase.restoreUserMarksIfAbsent`
/// (SQLite の存在確認) で、これも OS 側に残す判断。
@MainActor
final class UserMarkBackup {
    static let shared = UserMarkBackup()

    private let store = NSUbiquitousKeyValueStore.default
    private let key = "user_marks_backup_v1"
    private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "mark_backup")

    /// `NSUbiquitousKeyValueStore` の 1 値あたりの上限 (1MB)。超えると `set` は
    /// **無言で失敗する** (戻り値も通知も無い) — このクラスが扱う全マーク種別に共通の制約
    /// (特定の1機能の話ではない。担当/お気に入り/メモ/参加が多いユーザーは元々ここに
    /// 近づき得る)。余裕を持たせて 9 割で警告する。
    private static let sizeWarningThresholdBytes = 900_000

    private struct Payload: Codable {
        var marks: [UserMark]
        var updatedAt: Double
    }

    private init() {}

    /// 渡されたマーク (付いている行だけ) を KVS にミラーする (上書き)。マーク変更のたびに呼ぶ。
    func backup(_ marks: [UserMark]) {
        do {
            let data = try JSONEncoder().encode(Payload(marks: marks, updatedAt: Date().timeIntervalSince1970))
            let sizeBytes = data.count
            if sizeBytes > Self.sizeWarningThresholdBytes {
                logger.warning("user_marks backup is \(sizeBytes) bytes for \(marks.count) marks — approaching the 1MB per-value limit, writes may silently fail")
            } else {
                logger.debug("user_marks backup: \(sizeBytes) bytes for \(marks.count) marks")
            }
            store.set(data, forKey: key)
            // `synchronize()` の戻り値は「ローカルの変更をディスクへ反映できたか」の弱い
            // シグナル (iCloud への配信成否までは保証しない) だが、KVS がこの API で唯一
            // 返す確認手段なので、失敗が分かる時だけでも拾ってログに残す。
            if !store.synchronize() {
                logger.warning("user_marks backup: store.synchronize() returned false after writing \(sizeBytes) bytes")
            }
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
