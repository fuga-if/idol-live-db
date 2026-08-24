//! イベント一覧の時系列フィルタ + 年度グルーピング。
//!
//! フィルタ済みイベント列を「今後 / 開催済み」で時系列分割し、年度ごとに束ねて並べる。
//! DB にも UI にも依存しない純粋ロジックなので単体テスト可能。
//! iOS `groupEventsByYear` (EventGrouping.swift) の一次実装。
//!
//! FFI 境界はエンティティ全体を渡さず、判定に要る唯一のフィールドである
//! 初回公演日 (`first_dates`) の射影を渡して「年ラベル + index 列」を返す形にしている
//! (1 ユーザー操作 = 1 FFI 呼び出し。呼び出し側は自国の配列を index で引き直す)。
//!
//! `today_key` を引数で受けるのは環境値 (現在時刻) を持ち込まないため。呼び出し側は
//! JST の今日 (`jst_today`) を渡す (公演日は日本の開催日なので、端末ローカル日で
//! 切ると海外で 1 日ずれる)。

/// 年度グループ 1 つぶん。年ラベルと、入力 `first_dates` への添字の列。
///
/// iOS 既存 struct `YearGroup` (events 実体を持つ表示用) との名前衝突を避けて
/// EventYearGroup と呼ぶ (生成バインディングがアプリと同一モジュールに入るため)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct EventYearGroup {
    /// 表示用の年ラベル ("2026年"。日付不明は "年度不明")。
    pub year: String,
    /// 入力 `first_dates` への添字。グループ内は時系列順
    /// (今後=近い順/昇順、開催済み=新しい順/降順) に並び替え済み。
    pub indices: Vec<u32>,
}

/// 日付不明グループのラベル。年順ソートで常に末尾へ送る。
const UNKNOWN_YEAR: &str = "年度不明";

/// 年度キーとして使える日付か (4 桁未満は不明扱い)。
///
/// Swift 原本の `prefix` に合わせて文字数基準 (DB 由来の ASCII 日付では
/// バイト数と一致するが、想定外の入力でも桁の意味を変えないため)。
fn year_date_key(date: Option<&str>) -> Option<&str> {
    let d = date?;
    (d.chars().count() >= 4).then_some(d)
}

/// 先頭 `n` 文字 (バイトでなく文字数)。Swift `String.prefix` と同じ挙動。
fn char_prefix(s: &str, n: usize) -> &str {
    match s.char_indices().nth(n) {
        Some((byte_idx, _)) => &s[..byte_idx],
        None => s,
    }
}

/// 時系列フィルタ + 年度グルーピングを適用し、年度グループの配列を返す。
///
/// - `first_dates`: 事前フィルタ済みイベント列の初回公演日の射影 ("YYYY-MM-DD"。
///   "YYYY" や "YYYY-MM" の部分日付、未定の `None` もあり得る)。
/// - `upcoming`: true=今後の予定 (近い順/昇順)、false=開催済み (新しい順/降順)。
/// - `today_key`: 今日 "YYYY-MM-DD"。今後/開催済みの境界 (境界日ちょうどは今後側)。
///
/// 返り値は年度グループの配列。今後=年昇順、開催済み=年降順。「年度不明」は常に末尾。
/// 日付不明 (4 桁未満・None) は開催済みに入れず今後タブにのみ残す (登録途中の予定扱い)。
pub fn group_events_by_year(
    first_dates: &[Option<String>],
    upcoming: bool,
    today_key: &str,
) -> Vec<EventYearGroup> {
    // 時系列分割。
    let time_filtered = first_dates.iter().enumerate().filter_map(|(i, date)| {
        let Some(date) = year_date_key(date.as_deref()) else {
            // 日付不明は「今後」にのみ残す。
            return upcoming.then_some((i as u32, None));
        };
        // date が today_key (フル "YYYY-MM-DD") より粒度の粗い部分日付 ("YYYY" や
        // "YYYY-MM" 等) の場合、桁数が揃わないまま文字列比較すると短い方が辞書順で
        // 前に来てしまい誤判定になる。today_key 側を date と同じ精度に切り詰めてから比較する。
        let comparable_today = char_prefix(today_key, date.chars().count());
        let keep = if upcoming { date >= comparable_today } else { date < comparable_today };
        keep.then_some((i as u32, Some(date)))
    });

    // 年ラベルごとに束ねる (挿入順 = 入力順を保つので、後段の安定ソートと合わせて
    // Swift 原本の「同日・同不明はもとの並びを保つ」挙動を再現できる)。
    let mut year_map: Vec<(String, Vec<u32>)> = Vec::new();
    for (index, date) in time_filtered {
        let year = match date {
            Some(d) => format!("{}年", char_prefix(d, 4)),
            None => UNKNOWN_YEAR.to_string(),
        };
        match year_map.iter_mut().find(|(y, _)| *y == year) {
            Some((_, indices)) => indices.push(index),
            None => year_map.push((year, vec![index])),
        }
    }

    // 年の並び: 今後=昇順、開催済み=降順。「年度不明」は常に末尾。
    // ラベルは "YYYY年" 固定形式なので文字列比較がそのまま年の大小になる。
    year_map.sort_by(|(a, _), (b, _)| {
        use std::cmp::Ordering;
        match (a == UNKNOWN_YEAR, b == UNKNOWN_YEAR) {
            (true, true) => Ordering::Equal,
            (true, false) => Ordering::Greater,
            (false, true) => Ordering::Less,
            (false, false) => {
                if upcoming { a.cmp(b) } else { b.cmp(a) }
            }
        }
    });

    // グループ内を時系列順に (日付未定は "" 扱い = 昇順なら先頭側、降順なら末尾側)。
    // 安定ソートなので同日はもとの並びを保つ。
    year_map
        .into_iter()
        .map(|(year, mut indices)| {
            indices.sort_by(|&l, &r| {
                let ld = first_dates[l as usize].as_deref().unwrap_or("");
                let rd = first_dates[r as usize].as_deref().unwrap_or("");
                if upcoming { ld.cmp(rd) } else { rd.cmp(ld) }
            });
            EventYearGroup { year, indices }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const TODAY: &str = "2026-06-18";

    fn dates(list: &[Option<&str>]) -> Vec<Option<String>> {
        list.iter().map(|d| d.map(str::to_string)).collect()
    }

    fn years(groups: &[EventYearGroup]) -> Vec<&str> {
        groups.iter().map(|g| g.year.as_str()).collect()
    }

    // --- iOS EventGroupingTests から移植 ---

    /// 今後タブ: 過去は除外され、近い順 (昇順) に並ぶ。
    #[test]
    fn upcoming_keeps_future_and_sorts_ascending() {
        // [a=2026-07-01, past=2025-01-01, c=2026-06-20]
        let input = dates(&[Some("2026-07-01"), Some("2025-01-01"), Some("2026-06-20")]);

        let groups = group_events_by_year(&input, true, TODAY);

        // 過去 (2025) は除外。2026 のみ、近い順 (c=06-20 → a=07-01)。
        assert_eq!(years(&groups), vec!["2026年"]);
        assert_eq!(groups[0].indices, vec![2, 0]);
    }

    /// 開催済みタブ: 未来は除外され、年は降順に並ぶ。
    #[test]
    fn past_keeps_past_and_sorts_years_descending() {
        // [a=2025-03-01, b=2024-12-01, future=2026-07-01]
        let input = dates(&[Some("2025-03-01"), Some("2024-12-01"), Some("2026-07-01")]);

        let groups = group_events_by_year(&input, false, TODAY);

        // 未来 (2026-07) は除外。年は降順。
        assert_eq!(years(&groups), vec!["2025年", "2024年"]);
    }

    /// 開催済みタブ: 同一年の中は新しい順 (降順)。
    #[test]
    fn within_year_past_sorts_descending() {
        // [old=2025-01-10, new=2025-09-10]
        let input = dates(&[Some("2025-01-10"), Some("2025-09-10")]);

        let groups = group_events_by_year(&input, false, TODAY);

        assert_eq!(years(&groups), vec!["2025年"]);
        // 開催済みは新しい順。
        assert_eq!(groups[0].indices, vec![1, 0]);
    }

    /// 日付未定イベントは今後タブの末尾 (「年度不明」) にのみ現れ、開催済みには出ない。
    #[test]
    fn unknown_date_appears_in_upcoming_at_end_only() {
        // [a=2026-07-01, unknown=None]
        let input = dates(&[Some("2026-07-01"), None]);

        let upcoming = group_events_by_year(&input, true, TODAY);
        assert_eq!(years(&upcoming), vec!["2026年", "年度不明"]); // 年度不明は末尾
        assert_eq!(upcoming[1].indices, vec![1]);

        let past = group_events_by_year(&input, false, TODAY);
        assert!(!past.iter().any(|g| g.year == "年度不明")); // 開催済みには出ない
    }

    // --- 追加の境界ケース (iOS テストに無い分) ---

    /// 今日ちょうどの日付は「今後」側 (境界は >=)。
    #[test]
    fn event_on_today_counts_as_upcoming() {
        let input = dates(&[Some(TODAY)]);

        assert_eq!(group_events_by_year(&input, true, TODAY)[0].indices, vec![0]);
        assert!(group_events_by_year(&input, false, TODAY).is_empty());
    }

    /// 部分日付 ("YYYY" / "YYYY-MM") は today_key を同じ精度に切り詰めて比較する。
    /// 桁数が揃わないまま比較すると "2026" < "2026-06-18" となり、今年開催予定の
    /// 日付未確定イベントが開催済みへ落ちてしまう (Swift 原本のコメントの再現)。
    #[test]
    fn partial_date_is_compared_at_its_own_precision() {
        // [今年 (日付未確定), 今月 (日未確定), 昨年 (日付未確定)]
        let input = dates(&[Some("2026"), Some("2026-06"), Some("2025")]);

        let upcoming = group_events_by_year(&input, true, TODAY);
        // "2026" >= "2026"、"2026-06" >= "2026-06" → 今年分は今後側に残る。
        assert_eq!(years(&upcoming), vec!["2026年"]);
        assert_eq!(upcoming[0].indices, vec![0, 1]);

        let past = group_events_by_year(&input, false, TODAY);
        // "2025" < "2026" → 昨年分だけ開催済み。
        assert_eq!(years(&past), vec!["2025年"]);
        assert_eq!(past[0].indices, vec![2]);
    }

    /// 4 桁未満の文字列は年が読めないので日付不明扱い (今後タブにのみ残る)。
    #[test]
    fn too_short_date_is_treated_as_unknown() {
        let input = dates(&[Some("20"), Some("")]);

        let upcoming = group_events_by_year(&input, true, TODAY);
        assert_eq!(years(&upcoming), vec!["年度不明"]);
        // グループ内ソートは年キーでなく生の日付 (無ければ "") の昇順なので、
        // "" が "20" より前に来る (Swift 原本 `l.firstDate ?? ""` と同じ挙動)。
        assert_eq!(upcoming[0].indices, vec![1, 0]);

        assert!(group_events_by_year(&input, false, TODAY).is_empty());
    }

    /// 今後タブは年昇順で複数グループが並ぶ。
    #[test]
    fn upcoming_sorts_years_ascending() {
        let input = dates(&[Some("2027-01-01"), Some("2026-08-01")]);

        let groups = group_events_by_year(&input, true, TODAY);

        assert_eq!(years(&groups), vec!["2026年", "2027年"]);
    }

    /// 同日イベントはもとの並び (入力順) を保つ (安定ソート)。
    #[test]
    fn same_date_events_keep_input_order() {
        let input = dates(&[Some("2026-07-01"), Some("2026-07-01"), Some("2026-06-20")]);

        let groups = group_events_by_year(&input, true, TODAY);

        assert_eq!(groups[0].indices, vec![2, 0, 1]);
    }

    /// 空入力は空出力 (空グループを作らない)。
    #[test]
    fn empty_input_returns_empty() {
        assert!(group_events_by_year(&[], true, TODAY).is_empty());
        assert!(group_events_by_year(&[], false, TODAY).is_empty());
    }
}
