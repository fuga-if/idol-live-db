import Foundation

/// `EditFeedReading` ポートの GRDB アダプタ。
///
/// 段階移行 (Strangler) のため、当面は `AppDatabase` の既存メソッドへ委譲する。
/// `nonisolated` な async メソッドなので MainActor から `await` で呼ぶとオフメインで実行される。
struct GRDBEditFeedRepository: EditFeedReading {
    let database: AppDatabase

    func editRecordShowId(recordType: String, recordName: String) async throws -> String? {
        try database.fetchEditRecordShowId(recordType: recordType, recordName: recordName)
    }

    func editRecordSongId(recordType: String, recordName: String) async throws -> String? {
        try database.fetchEditRecordSongId(recordType: recordType, recordName: recordName)
    }

    func editRecordTitle(recordType: String, recordName: String) async throws -> String? {
        try database.fetchEditRecordTitle(recordType: recordType, recordName: recordName)
    }
}
