import Foundation

/// `EditFeedReading` ポートの GRDB アダプタ。
///
/// 段階移行 (Strangler) のため、当面は `AppDatabase` の既存メソッドへ委譲する。
/// `nonisolated` な async メソッドなので MainActor から `await` で呼ぶとオフメインで実行される。
struct GRDBEditFeedRepository: EditFeedReading {
    let database: AppDatabase

    func editRecordShowId(recordType: String, recordName: String) async throws -> String? {
        try await database.fetchEditRecordShowIdAsync(recordType: recordType, recordName: recordName)
    }

    func editRecordSongId(recordType: String, recordName: String) async throws -> String? {
        try await database.fetchEditRecordSongIdAsync(recordType: recordType, recordName: recordName)
    }

    func editRecordTitle(recordType: String, recordName: String) async throws -> String? {
        try await database.fetchEditRecordTitleAsync(recordType: recordType, recordName: recordName)
    }
}
