//! 表示用の連結規則。**区切り文字を決めるのはここ 1 箇所**。
//!
//! アプリのプロフィール行 (原本 Swift `joined(separator: " ・ ")`) から来た規則で、
//! iOS / Android / Web が同じ見た目になるための土台。呼び出し側ごとに `join(" ・ ")`
//! を書き始めると、同じ意味の行が画面ごとに違う区切りで出る (実際に Rust の中だけで
//! 3 実装に割れていた)。

/// 項目の区切り。全角スペース込みの中黒。
pub const PARTS_SEPARATOR: &str = " ・ ";

/// 非 `None` かつ非空の要素を [`PARTS_SEPARATOR`] で繋ぐ。
///
/// 1 つも残らなければ `None` — 呼び出し側は「行ごと出さない」を素直に書ける。
pub fn join_parts<S: AsRef<str>>(parts: impl IntoIterator<Item = Option<S>>) -> Option<String> {
    let kept: Vec<String> = parts
        .into_iter()
        .flatten()
        .map(|s| s.as_ref().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    (!kept.is_empty()).then(|| kept.join(PARTS_SEPARATOR))
}

/// 多い列を「先頭 N 件 + ほか M <単位>」に畳む。
///
/// 全体曲の原唱者は 60 人を超え、ツアーの会場は 20 を超える。全部並べると行が読めなくなり、
/// かといって単純に切ると「まだ続きがある」ことが伝わらない。畳み方を 1 箇所に持つ。
pub fn join_capped(items: &[&str], separator: &str, shown: usize, unit: &str) -> Option<String> {
    match items.len() {
        0 => None,
        n if n <= shown => Some(items.join(separator)),
        n => Some(format!("{} ほか {} {unit}", items[..shown].join(separator), n - shown)),
    }
}

/// `"2024-05-18"` → `"2024"`。日付でない文字列はそのまま先頭 4 文字。
pub fn year_of(date: &str) -> String {
    date.chars().take(4).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_and_blank_parts_do_not_produce_a_row() {
        assert_eq!(join_parts([None::<&str>, None]), None);
        assert_eq!(join_parts([Some(""), Some("")]), None);
        assert_eq!(join_parts([Some(""), Some("A"), None]), Some("A".to_string()));
    }

    #[test]
    fn parts_are_joined_with_the_app_separator() {
        assert_eq!(join_parts([Some("A"), Some("B")]), Some("A ・ B".to_string()));
    }

    #[test]
    fn long_lists_are_capped_with_a_remainder() {
        assert_eq!(join_capped(&[], " / ", 2, "名"), None);
        assert_eq!(join_capped(&["a", "b"], " / ", 2, "名"), Some("a / b".to_string()));
        assert_eq!(
            join_capped(&["a", "b", "c", "d"], " / ", 2, "名"),
            Some("a / b ほか 2 名".to_string())
        );
    }

    #[test]
    fn year_is_the_first_four_characters() {
        assert_eq!(year_of("2024-05-18"), "2024");
        assert_eq!(year_of("20"), "20");
        assert_eq!(year_of(""), "");
    }
}
