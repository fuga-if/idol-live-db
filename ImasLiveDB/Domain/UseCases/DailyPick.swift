import Foundation

/// 「日替わり」ものの共通ルール。日付キーと、日付から曲を 1 つ選ぶ決定論的な種。
///
/// ## なぜ端末ローカル日で、なぜ `JSTDay` と分けるか
///
/// `JSTDay` は **公演日 (`shows.date`) との比較**に使う。公演日は日本のライブの開催日なので
/// 端末がどこにあっても JST で判定しないと 1 日ずれる。
///
/// こちらは **「そのユーザーの 1 日」**が単位。連続クリア日数や日替わりピックは、
/// 使っている人の深夜 0 時で切り替わるのが自然なので端末ローカルのまま。
/// 意味が違うので統合しない。
///
/// ## なぜ 1 か所に置くか
///
/// 「今日の 1 曲」はアプリ内 (`DailySongVoteSheet`) とウィジェット用スナップショット
/// (`InfoWidgetBridge`) の両方が **同じ曲を選ばないといけない**。
/// 以前は日付キー・FNV-1a・種文字列の組み立てが両方にコピーされていて
/// (コメントに「同一実装」と書いてあるだけ)、片方を直すとウィジェットとアプリが
/// 黙って違う曲を出す状態だった。契約なのでここに集約してテストで固定する。
enum DailyPick {
    /// 端末ローカルの `"yyyy-MM-dd"`。
    static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 端末ローカルの前日。連続記録の判定に使う。
    /// 日付の引き算はカレンダー任せ (夏時間などで 24 時間ちょうどとは限らないため)。
    static func previousDayKey(_ date: Date = Date()) -> String {
        dayKey(Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date)
    }

    /// 文字列 → `[0, mod)` の安定インデックス (FNV-1a 系)。
    /// プロセスをまたいでも同じ値になる必要があるので `hashValue` は使えない
    /// (Swift の Hasher は起動ごとに seed が変わる)。
    ///
    /// - Important: offset basis が標準 FNV-1a の `14695981039346656037` ではなく
    ///   1 桁欠けた `1469598103934665603` のまま出荷されている。分布に実害はないので
    ///   **直さない**。直すと全ユーザーの「今日の1曲」が一斉に入れ替わる。
    ///   `DailyPickTests.testStableIndexMatchesShippedValues` で固定している。
    static func stableIndex(_ s: String, mod: Int) -> Int {
        guard mod > 0 else { return 0 }
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Int(h % UInt64(mod))
    }

    /// その日そのブランドの「今日の 1 曲」を、曲 ID 一覧の何番目にするか。
    ///
    /// アプリ本体とウィジェットのスナップショット生成が同じ答えを出すための唯一の入口。
    /// 種文字列の組み立て (`"日付|ブランドID"`) までここに含める。
    /// - Parameter count: そのブランドの候補曲数。0 なら 0 を返す (呼び出し側で空判定する前提)。
    static func songIndex(dayKey: String, brandId: String, count: Int) -> Int {
        stableIndex(dayKey + "|" + brandId, mod: count)
    }
}
