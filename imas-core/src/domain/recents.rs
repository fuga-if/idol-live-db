//! 「最近見たもの」(MRU) の積み方。
//!
//! 両 OS が同じ規則 (新しい順・同じ項目は先頭へ繰り上げ・上限で打ち切り) を写経していた
//! (iOS `RecentsService` / Android `RecentsStore`)。保存 (UserDefaults / SharedPreferences) と
//! 項目の中身 (名前を持つか) は各 OS に残し、ここは**鍵の並び**だけを決める。

/// 「最近見たもの」の上限件数。
pub const RECENTS_LIMIT: usize = 20;

/// 見た項目の鍵 (`"event:<id>"` など、OS が作る) を先頭に積んだ並びを返す (新しい順)。
///
/// 同じ鍵が既にあれば取り除いてから先頭へ (重複しない)。上限を超えた古いものは落とす。
/// 空の鍵は記録しない (並びをそのまま返す)。
pub fn recents_after_visit(current: &[String], visited: &str) -> Vec<String> {
    if visited.is_empty() {
        return current.to_vec();
    }
    std::iter::once(visited)
        .chain(current.iter().map(String::as_str).filter(|key| *key != visited))
        .take(RECENTS_LIMIT)
        .map(str::to_string)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn keys(values: &[&str]) -> Vec<String> {
        values.iter().map(|v| v.to_string()).collect()
    }

    #[test]
    fn newest_first_and_revisits_move_to_the_front() {
        let first = recents_after_visit(&[], "song:a");
        assert_eq!(first, keys(&["song:a"]));
        let second = recents_after_visit(&first, "idol:b");
        assert_eq!(second, keys(&["idol:b", "song:a"]));
        assert_eq!(recents_after_visit(&second, "song:a"), keys(&["song:a", "idol:b"]), "重複しない");
    }

    #[test]
    fn caps_at_the_limit_dropping_the_oldest() {
        let full: Vec<String> = (0..RECENTS_LIMIT).map(|i| format!("song:{i}")).collect();
        let next = recents_after_visit(&full, "event:new");
        assert_eq!(next.len(), RECENTS_LIMIT);
        assert_eq!(next[0], "event:new");
        assert!(!next.contains(&format!("song:{}", RECENTS_LIMIT - 1)), "いちばん古いものが落ちる");
        // 既にある項目の再訪では何も落ちない。
        let revisit = recents_after_visit(&full, "song:5");
        assert_eq!(revisit.len(), RECENTS_LIMIT);
        assert_eq!(revisit[0], "song:5");
    }

    #[test]
    fn empty_key_is_not_recorded() {
        let current = keys(&["song:a"]);
        assert_eq!(recents_after_visit(&current, ""), current);
    }
}
