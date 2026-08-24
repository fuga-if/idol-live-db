import Foundation

/// 「日替わり」ものの共通ルール。日付キーと、日付から曲を 1 つ選ぶ決定論的な種。
///
/// 本体は imas-core (Rust) の `domain/daily_pick.rs`。なぜ端末ローカル日か・なぜ `JSTDay` と
/// 分けるか・FNV-1a の offset basis を直してはいけない理由など、設計意図もそちらに記載。
/// ここは「既定値 `Date()` と、端末の暦法設定 (`Calendar.current`) で解決した日付成分の注入」
/// だけを担う薄いラッパ。暦法 (和暦・仏暦 等) は OS からしか分からず、Rust 側の chrono は
/// グレゴリオ暦固定なので、epoch 秒ではなく暦法解決済みの成分を渡すのが契約
/// (和暦端末では era 年の "0008-07-26" が出るのが出荷済みの挙動で、変えると保存済みの
/// 連続記録キーと食い違う)。
enum DailyPick {
    /// 端末ローカルの `"yyyy-MM-dd"`。端末の暦法設定に従う (原本実装からの互換)。
    static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return dailyPickDayKey(
            localYear: Int32(clamping: c.year ?? 0),
            localMonth: Int32(clamping: c.month ?? 0),
            localDay: Int32(clamping: c.day ?? 0))
    }

    /// 端末ローカルの前日。連続記録の判定に使う。
    /// 日付の引き算はカレンダー任せ (夏時間で 24 時間ちょうどとは限らず、暦によっては
    /// era 跨ぎ・うるう規則がグレゴリオ暦と違うため、epoch から 86400 秒引く方式も
    /// Rust 側でのグレゴリオ暦演算も不可)。原本と同じく失敗時は当日へフォールバック。
    static func previousDayKey(_ date: Date = Date()) -> String {
        dayKey(Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date)
    }

    /// 文字列 → `[0, mod)` の安定インデックス (FNV-1a 系)。
    static func stableIndex(_ s: String, mod: Int) -> Int {
        Int(dailyPickStableIndex(seed: s, modulo: Int64(mod)))
    }

    /// その日そのブランドの「今日の 1 曲」を、曲 ID 一覧の何番目にするか。
    /// 1 ブランドだけ解決する時 (ウィジェットのスナップショット) 用。複数ブランドを
    /// ループで回すなら `songIndices` を使う (要素ごとの FFI 呼び出しにしない)。
    static func songIndex(dayKey: String, brandId: String, count: Int) -> Int {
        Int(dailyPickSongIndex(dayKey: dayKey, brandId: brandId, count: Int64(count)))
    }

    /// 複数ブランド分の「今日の 1 曲」を 1 回の FFI 呼び出しでまとめて解決する一括版。
    /// 返り値は `brands` と同順。1 件ずつの答えは `songIndex` と必ず一致する
    /// (アプリの一括解決とウィジェットの単発解決が同じ曲を選ぶための契約)。
    static func songIndices(dayKey: String, brands: [(brandId: String, count: Int)]) -> [Int] {
        dailyPickSongIndices(
            dayKey: dayKey,
            brands: brands.map {
                DailyPickBrandCandidates(brandId: $0.brandId, count: UInt32(max(0, $0.count)))
            }
        ).map(Int.init)
    }
}
