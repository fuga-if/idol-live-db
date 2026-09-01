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
    ///
    /// **nil = まだ数えられない**。0 件とは区別する。スナップショットは起動直後に
    /// バックグラウンドで載るので、それより先に訊くと数えようがない。ここを 0 で
    /// 返すと「どこにも無い」と読めてしまい、呼び出し側が待つべきか諦めるべきかを
    /// 判断できない (実際それでチップが永久に出なかった)。
    func counts(query: String) async throws -> CrossTabSearchCounts?

    /// 打った語がライブの「今後の予定」「開催済み」それぞれに何件あるか。
    ///
    /// 「ライブに N 件」から飛んだとき、当たりが過去のライブなのに既定の
    /// 「今後の予定」へ着地すると 0 件の画面が出る。件数を見せて誘っておいて
    /// 空を出すのは、この導線の趣旨に反するので、当たりのある側へ着地させる。
    /// nil = まだ数えられない (`counts` と同じ)。
    func eventSides(query: String, todayKey: String) async throws -> EventSearchSideCounts?
}

/// ライブの当たりが今後/開催済みのどちらにいるか。
struct EventSearchSideCounts: Equatable, Sendable {
    var upcoming: Int = 0
    var past: Int = 0

    /// 着地すべき側。同数・両方 0 なら既定の「今後の予定」。
    /// 件数で選ぶのは、当たりが両側にある語 (「ライブ」等) でも多い方を出すため。
    var landsOnPast: Bool { past > upcoming }
}

/// 種別ごとの一致件数。コアの `SearchCounts` をアプリ側の型に写したもの。
struct CrossTabSearchCounts: Equatable, Sendable {
    var songs: Int = 0
    var idols: Int = 0
    var events: Int = 0

    /// どこにも当たらない (チップを 1 つも出さない)。
    var isEmpty: Bool { songs == 0 && idols == 0 && events == 0 }
}
