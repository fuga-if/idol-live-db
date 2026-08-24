import Foundation

/// 「今日」の判定を JST に固定するための共通ルール。
///
/// 判定本体は imas-core (Rust) の `jst_day.rs` にあり、Android の `JstDay` と同じ実装を共有する。
/// ここは「既定値 `Date()` の注入」と「Swift らしい呼び口の維持」だけを担う薄いラッパ。
/// なぜ JST 固定か・なぜ都度計算かの設計意図は imas-core/src/jst_day.rs に記載。
///
/// `now` を引数にしているのはテストで日付境界を再現するため (既定は現在時刻)。
enum JSTDay {
    /// 公演日 (`shows.date`) と同じ `"yyyy-MM-dd"` 表記。
    static let format = "yyyy-MM-dd"

    static let timeZone = TimeZone(identifier: "Asia/Tokyo")!

    /// JST での「今日」を `"yyyy-MM-dd"` で返す。
    static func today(now: Date = Date()) -> String {
        jstToday(nowEpochSeconds: Int64(now.timeIntervalSince1970.rounded(.down)))
    }

    /// 公演日が「今日以降」か。当日は未来として扱う (開催日当日はまだ終わっていない)。
    ///
    /// - Parameter date: `"yyyy-MM-dd"` の公演日。空文字は未来ではない。
    static func isTodayOrLater(_ date: String, now: Date = Date()) -> Bool {
        jstIsTodayOrLater(date: date, nowEpochSeconds: Int64(now.timeIntervalSince1970.rounded(.down)))
    }
}
