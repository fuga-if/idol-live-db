import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "personal_tag")

/// 個人用タグ (ローカル専用・サーバー非送信)。コミュニティタグとは別に、ユーザーが自由入力で
/// 付ける私用の分類 (例:「聞いた」) を管理する。UserMarkService の note/seat と同じく、件数が
/// 少ない前提で読み取りは都度 DB を引く (キャッシュは持たず、version でSwiftUI再描画を駆動)。
@Observable
@MainActor
final class PersonalTagService {
    static let shared = PersonalTagService()

    private let db: AppDatabase
    private var version: Int = 0

    private init() {
        self.db = AppDatabase.shared
    }

    func tags(for entityType: String, entityId: String) -> [PersonalTag] {
        _ = version
        do {
            return try db.fetchPersonalTags(entityType: entityType, entityId: entityId)
        } catch {
            logger.error("fetchPersonalTags failed: entityType=\(entityType) entityId=\(entityId) error=\(error.localizedDescription)")
            return []
        }
    }

    /// 足せたら true。書けなかったときは入力欄を消さないよう、呼び出し側に返す。
    @discardableResult
    func addTag(entityType: String, entityId: String, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try db.addPersonalTag(entityType: entityType, entityId: entityId, tagName: trimmed)
            version &+= 1
            return true
        } catch {
            LocalWriteFailure.report(error, action: "マイタグの追加")
            return false
        }
    }

    func removeTag(entityType: String, entityId: String, name: String) {
        do {
            try db.removePersonalTag(entityType: entityType, entityId: entityId, tagName: name)
            version &+= 1
        } catch {
            LocalWriteFailure.report(error, action: "マイタグの削除")
        }
    }
}
