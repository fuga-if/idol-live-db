import Foundation

/// 横断検索 (曲/アイドル/イベント等をまとめて) の読み取りポート (driven port)。
///
/// 実装は `Adapters/Persistence/GRDBGlobalSearchRepository`。
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol GlobalSearchReading: Sendable {
    /// クエリにマッチする各種エンティティをまとめて返す。
    func search(query: String) async throws -> SearchResults

    /// 打った語が種別ごとに何件当たるか (打ち切りなし)。
    ///
    /// 各一覧の検索欄が「他のタブに N 件」を出すために使う。実体は要らないので
    /// 数だけ返す。上限で切らないのは、「20 件」と出しておいて実は 137 件ある、では
    /// タブを移る判断の根拠にならないため。
    func counts(query: String) async throws -> CrossTabSearchCounts
}

/// 種別ごとの一致件数。コアの `SearchCounts` をアプリ側の型に写したもの。
struct CrossTabSearchCounts: Equatable, Sendable {
    var songs: Int = 0
    var idols: Int = 0
    var events: Int = 0

    /// どこにも当たらない (チップを 1 つも出さない)。
    var isEmpty: Bool { songs == 0 && idols == 0 && events == 0 }
}
