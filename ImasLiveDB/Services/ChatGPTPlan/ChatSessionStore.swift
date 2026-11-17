import Foundation
import os

/// チャットの会話を端末のファイルに置く。
///
/// 保存の形・題・何本まで残すか・一覧の並びはコア (`domain::chat_sessions`)。ここはファイルを
/// 読む・書く・消すだけ。置き場は Application Support の中で、サーバには送らない。
/// 利用者の記録を含む返事が入るので、端末のバックアップ (iCloud) にも乗せない。
///
/// 一覧は全ファイルを読むので、呼ぶ側はメインスレッドの外から呼ぶ (`Task.detached`)。
enum ChatSessionStore {
    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        var dir = base.appendingPathComponent("ChatSessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }

    private static func file(_ id: String) -> URL? {
        // id は自分で振った UUID。念のため、パスに使えない字が混ざったものは扱わない。
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return directory?.appendingPathComponent("\(id).json")
    }

    /// 一覧 (新しい順)。上限を越えた古い会話は、ここで消す。
    static func list() -> [ChatSessionSummary] {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        let sessions = urls.filter { $0.pathExtension == "json" }.compactMap { url -> ChatSession? in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return chatSessionDecode(text: text)
        }
        let shelf = chatSessionShelf(sessions: sessions)
        shelf.overflowIds.forEach(delete)
        return shelf.sessions
    }

    static func load(_ id: String) -> ChatSession? {
        guard let url = file(id), let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return chatSessionDecode(text: text)
    }

    static func save(_ session: ChatSession) {
        guard let url = file(session.id) else { return }
        do {
            try chatSessionEncode(session: session).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Logger.database.error("chat_session_save_failed: \(error.localizedDescription)")
        }
    }

    static func delete(_ id: String) {
        guard let url = file(id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAll() {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        urls.filter { $0.pathExtension == "json" }.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
