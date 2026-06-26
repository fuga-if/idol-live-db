import Foundation

/// 編集フィード (誰が何を編集したか) のレコード解決ポート (driven port)。
///
/// CloudKit recordType/recordName から、表示用タイトルや関連する公演/楽曲 id を引く。
/// 実装は `Adapters/Persistence/GRDBEditFeedRepository`。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol EditFeedReading: Sendable {
    /// セトリ系レコード (Show/ShowSetlist/SetlistItem/SetlistPerformer) → 該当公演 id。
    func editRecordShowId(recordType: String, recordName: String) async throws -> String?
    /// 楽曲系コミュニティレコード (SongVideo/SongCall) → 該当楽曲 id。
    func editRecordSongId(recordType: String, recordName: String) async throws -> String?
    /// レコードの表示用タイトル。
    func editRecordTitle(recordType: String, recordName: String) async throws -> String?
}
