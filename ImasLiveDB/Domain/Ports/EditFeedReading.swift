import Foundation

/// 編集フィード (誰が何を編集したか) のレコード解決ポート (driven port)。
///
/// CloudKit recordType/recordName から、表示用タイトルや関連する公演/楽曲 id を引く。
/// 実装は `Adapters/Persistence/GRDBEditFeedRepository`。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol EditFeedReading: Sendable {
    /// 一覧のレコードの表示用タイトルと、セトリ系レコードの公演 id をまとめて引く
    /// (行ごとに 2 回引かない)。解決できないレコードは結果に入らない。
    func editRecordTargets(_ keys: [EditRecordKey]) async throws -> [EditRecordKey: EditRecordResolution]
    /// 楽曲系コミュニティレコード (SongVideo) → 該当楽曲 id。
    func editRecordSongId(recordType: String, recordName: String) async throws -> String?
}

/// 編集されたレコードの鍵。
struct EditRecordKey: Hashable, Sendable {
    let recordType: String
    let recordName: String
}

/// レコードの表示用タイトルと、セトリ系なら属する公演 id。
struct EditRecordResolution: Sendable {
    let title: String?
    let showId: String?
}
