//! 公演名からライブ名と重なる部分を落とす規則。
//!
//! 一覧の行・チップ・パンくず・`<title>` は、どれもライブ名を見出しに持ったうえで
//! 公演名を添える。実データの公演名はライブ名を丸ごと含むことが多く、素朴に繋ぐと
//! 同じ長い名前が 2 回並んで、公演を見分ける手掛かり (`DAY1` / `【第一回】`) が
//! 読めなくなる。落とし方を 1 箇所に持つ。

/// **部分的な**重なりとみなす最短の長さ (文字数)。
///
/// ライブ名を丸ごと含む場合には効かない。効くのは末尾だけが重なる場合で、
/// 「〜」「!!」「2nd」のような短い一致で公演名の頭を削らないための下限。
pub const MIN_OVERLAP_CHARS: usize = 4;

/// 行に出す公演名。ライブ名と重なる部分を落とし、何も残らなければ `None`。
///
/// 実データの重なり方は 2 通りあり、後者は前者の一般形なので 1 つの規則で扱う:
///
/// ```text
/// (a) 公演名がライブ名を丸ごと頭に含む
///     ライブ: THE IDOLM@STER MILLION THE@TER WAVE 11&12 発売記念イベント
///     公演  : 同上 + 【第一回】                              → 【第一回】
///
/// (b) ライブ名の末尾と公演名の先頭が重なる (2 つの副題を持つツアー)
///     ライブ: 765PRO ALLSTARS dual twin live tour ふたごぼしのつばさ / つみまつよるまち
///     公演  : つみまつよるまち TOKYO LAST CHOICE          → TOKYO LAST CHOICE
/// ```
pub fn distinguishing_show_name<'a>(event_name: &str, show_name: &'a str) -> Option<&'a str> {
    let rest = strip_leading_overlap(event_name, show_name);
    // 区切りの空白と中黒だけを落とす。`【` や `第` は見分けに要るので残す。
    let rest = rest.trim_start_matches([' ', '\u{3000}', '-', '~', '～', '・', '/']).trim();
    (!rest.is_empty()).then_some(rest)
}

/// `event_name` の末尾と `show_name` の先頭が重なっているぶんを落とす。
///
/// 1. まず**ライブ名そのもの**が頭に付いていないかを見る。付いていれば長さを問わず
///    落とす (ライブ名が丸ごと一致している以上、偶然ではない)。
/// 2. 次に末尾だけの重なりを、**長い方から**試す。短い方から消すと `AB AB` のような
///    形で片方が残る。こちらは偶然の一致がありうるので下限を設ける。
fn strip_leading_overlap<'a>(event_name: &str, show_name: &'a str) -> &'a str {
    if let Some(stripped) = show_name.strip_prefix(event_name) {
        return stripped;
    }
    let event: Vec<char> = event_name.chars().collect();
    let max = event.len().min(show_name.chars().count());
    for len in (MIN_OVERLAP_CHARS..=max).rev() {
        let tail: String = event[event.len() - len..].iter().collect();
        if let Some(stripped) = show_name.strip_prefix(tail.as_str()) {
            return stripped;
        }
    }
    show_name
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_show_named_after_its_event_adds_nothing() {
        // 公演が 1 本しかないライブ。行のタイトルと同じ名前を繰り返さない。
        assert_eq!(distinguishing_show_name("A LIVE", "A LIVE"), None);
        assert_eq!(distinguishing_show_name("A LIVE", "A LIVE "), None);
    }

    #[test]
    fn only_the_part_that_tells_shows_apart_is_kept() {
        assert_eq!(
            distinguishing_show_name(
                "MILLION THE@TER WAVE 発売記念イベント",
                "MILLION THE@TER WAVE 発売記念イベント【第一回】"
            ),
            Some("【第一回】")
        );
        assert_eq!(
            distinguishing_show_name("SideM 2nd STAGE", "SideM 2nd STAGE Shining Side"),
            Some("Shining Side")
        );
        // 区切りの中黒や波ダッシュは落とすが、見分けに要る文字は残す。
        assert_eq!(distinguishing_show_name("ツアー", "ツアー ・ 第1回公演"), Some("第1回公演"));
    }

    #[test]
    fn an_unrelated_show_name_is_left_alone() {
        assert_eq!(distinguishing_show_name("A LIVE", "DAY2"), Some("DAY2"));
        assert_eq!(distinguishing_show_name("A LIVE", "昼公演"), Some("昼公演"));
    }

    #[test]
    fn a_tail_that_the_show_name_repeats_is_dropped() {
        assert_eq!(
            distinguishing_show_name(
                "765PRO ALLSTARS dual twin live tour ふたごぼしのつばさ / つみまつよるまち",
                "つみまつよるまち TOKYO LAST CHOICE"
            ),
            Some("TOKYO LAST CHOICE")
        );
        assert_eq!(distinguishing_show_name("ツアー名", "ツアー名 DAY1"), Some("DAY1"));
    }

    #[test]
    fn a_short_coincidental_overlap_does_not_eat_the_name() {
        assert_eq!(distinguishing_show_name("ライブ 2nd", "2nd 昼公演"), Some("2nd 昼公演"));
        assert_eq!(distinguishing_show_name("A LIVE!!", "!! DAY1"), Some("!! DAY1"));
    }
}
