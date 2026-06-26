import Foundation

/// ユーザーマーク (お気に入り/担当/メモ/参加/回収) の **集合読み取り** ポート (driven port)。
///
/// 個々のマークの観測・トグルは `@Observable` な `UserMarkService` が担う (そちらはポート化しない)。
/// このポートは一覧の絞り込み・集計に使う「id 集合の一括取得」だけを抽象化する。
/// 実装は `Adapters/Persistence/GRDBMarkRepository`。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol MarkReading: Sendable {
    /// 指定エンティティ種別・マーク種別が付いた id 一覧。
    func markedEntityIds(entity: UserMarkEntity, kind: UserMarkKind) async throws -> [String]
    /// 自動回収済み (現地参加由来) の曲 id 集合。
    func autoCollectedSongIds() async throws -> Set<String>
}
