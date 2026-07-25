import Foundation

/// 「今日」の判定を JST に固定するための共通ルール。
///
/// ## なぜ JST 固定か
///
/// DB に入っている公演日 (`shows.date`) は **日本のライブの開催日**で、`"yyyy-MM-dd"` の
/// 文字列。これを「今日」と文字列比較して「未来公演か」「次の公演はどれか」を出している。
/// 端末ローカルのタイムゾーンで「今日」を作ると、海外にいるユーザーだけ判定が 1 日ずれる
/// (例: ハワイ (UTC-10) では日本の 7/26 10:00 がまだ 7/25 なので、日本では終わった公演が
/// 「これから」に出る)。`AttendanceStatus` と `AppDatabase` のカレンダークエリは元から
/// JST 固定で、それが本来の方針。
///
/// ## なぜ関数で、なぜ `now` を渡すか
///
/// 以前 `static let` でキャッシュしている実装があり、アプリを開いたまま日付が変わると
/// 「今日」が古いままになっていた。呼ぶたびに計算する。
/// `now` を引数にしているのはテストで日付境界を再現するため (既定は現在時刻)。
enum JSTDay {
    /// 公演日 (`shows.date`) と同じ `"yyyy-MM-dd"` 表記。
    static let format = "yyyy-MM-dd"

    static let timeZone = TimeZone(identifier: "Asia/Tokyo")!

    /// JST での「今日」を `"yyyy-MM-dd"` で返す。
    static func today(now: Date = Date()) -> String {
        let f = DateFormatter()
        // 端末のカレンダー設定 (和暦等) に引きずられないよう POSIX 固定。
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = format
        return f.string(from: now)
    }

    /// 公演日が「今日以降」か。当日は未来として扱う (開催日当日はまだ終わっていない)。
    ///
    /// - Parameter date: `"yyyy-MM-dd"` の公演日。空文字は未来ではない。
    static func isTodayOrLater(_ date: String, now: Date = Date()) -> Bool {
        guard !date.isEmpty else { return false }
        return date >= today(now: now)
    }
}
