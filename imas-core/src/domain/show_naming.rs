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
use crate::domain::date_display::short_with_weekday;

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
///
/// 比べるのは幅を揃えた形 ([`fold_width_str`])。実データにはライブ名が `IDOLM@STER`、
/// 公演名が `IDOLM＠STER` という組があり、そのまま比べると 1 字の幅違いで
/// 「重なり無し」になって、公演名にライブ名が丸ごと残る。
fn strip_leading_overlap<'a>(event_name: &str, show_name: &'a str) -> &'a str {
    let event: Vec<char> = event_name.chars().map(fold_width).collect();
    let show: Vec<char> = show_name.chars().map(fold_width).collect();
    // 長い方から試す。先頭の候補はライブ名そのもの (長さを問わず落とす)。
    let max = event.len().min(show.len());
    (MIN_OVERLAP_CHARS.min(event.len())..=max)
        .rev()
        .find(|&len| show.starts_with(&event[event.len() - len..]))
        .map_or(show_name, |len| skip_chars(show_name, len))
}

/// 先頭 `n` 文字を落とす (折った文字列と元の文字列は 1 字対 1 字なので位置が一致する)。
fn skip_chars(text: &str, n: usize) -> &str {
    text.char_indices().nth(n).map_or("", |(i, _)| &text[i..])
}

/// 幅の違いだけの字を揃える: 全角英数記号 (`＠` `！` `Ａ`) → 半角、全角空白 → 空白。
/// 1 字 → 1 字の写像なので、文字数と位置は変わらない。
fn fold_width(c: char) -> char {
    match c {
        '\u{3000}' => ' ',
        '\u{FF01}'..='\u{FF5E}' => char::from_u32(c as u32 - 0xFEE0).unwrap_or(c),
        _ => c,
    }
}

/// 公演の呼び方。ライブ名との関係で決まる 3 つの形を 1 回で求める。
///
/// 見出し (公演ページ)・行 (ライブ詳細/トップ/会場)・兄弟のチップ・パンくず・`<title>` が
/// 全部これを使う。置き場ごとに切り方を書くと、1 箇所直して他が戻る。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShowIdentity {
    /// 見出しの本体。ふつうは**ライブ名** — 公演の主はライブで、`Day2` は見分けでしかない。
    /// 公演名がライブ名を丸ごと含む稀な形 (`★グランドフィナーレ★(… Live Broadcast)`) では
    /// 前にライブ名を付けると 2 回になるので、公演名そのものが本体になる。
    pub heading: String,
    /// 見出しに添える見分け (`Day2` / `昼公演`)。公演名がライブ名そのものなら無い。
    pub label: Option<String>,
    /// 見分けだけを出す場所 (ライブ詳細の行・兄弟のチップ・パンくず) の名前。
    /// 見分けがあればそれ、無ければ日付 (`9/13 (日)`) — 区別できるのが日付しか無いのだから、
    /// 出すべきものも日付。年はページの日付ブロックが持つ。
    pub short: ShortName,
}

/// 見分けだけの名前。日付で代用したかどうかを受け手が文字列から推し量らなくて済むように、
/// 種類を持たせる (チップに日付を添えるかは、名前が日付そのものでないときだけ)。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ShortName {
    /// `Day2` / `昼公演`。稀に公演名そのもの (ライブ名を途中に含む形)。
    Name(String),
    /// `9/13 (日)`。公演名がライブ名そのもので、見分けが無い。
    Date(String),
}

impl ShortName {
    pub fn text(&self) -> &str {
        match self {
            Self::Name(text) | Self::Date(text) => text,
        }
    }

    pub fn into_text(self) -> String {
        match self {
            Self::Name(text) | Self::Date(text) => text,
        }
    }

    pub fn is_name(&self) -> bool {
        matches!(self, Self::Name(_))
    }
}

impl ShowIdentity {
    /// `<title>` / og:title / JSON-LD の名前。本体と見分けを空白で繋ぐ。
    pub fn title(&self) -> String {
        match &self.label {
            Some(label) => format!("{} {label}", self.heading),
            None => self.heading.clone(),
        }
    }
}

/// `date` は `yyyy-MM-dd` (部分日付も可)。
pub fn show_identity(event_name: &str, show_name: &str, date: &str) -> ShowIdentity {
    let rest = distinguishing_show_name(event_name, show_name);
    let (heading, label) = match rest {
        None => (event_name.to_string(), None),
        Some(rest) if rest.contains(event_name) => (rest.to_string(), None),
        Some(rest) => (event_name.to_string(), Some(rest.to_string())),
    };
    let short = match rest {
        Some(rest) => ShortName::Name(rest.to_string()),
        None => ShortName::Date(short_with_weekday(date)),
    };
    ShowIdentity { heading, label, short }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_leads_with_the_event_and_falls_back_to_the_date() {
        let day2 = show_identity("ML 2ndLIVE", "ML 2ndLIVE Day2", "2015-04-05");
        assert_eq!(day2.heading, "ML 2ndLIVE");
        assert_eq!(day2.label.as_deref(), Some("Day2"));
        assert_eq!(day2.short, ShortName::Name("Day2".to_string()));
        assert_eq!(day2.title(), "ML 2ndLIVE Day2");

        // 公演名がライブ名そのもの: 見分けは無く、行やチップは日付で見分ける。
        let same = show_identity("SideM 11th STAGE", "SideM 11th STAGE", "2026-09-13");
        assert_eq!(same.label, None);
        assert_eq!(same.short, ShortName::Date("9/13 (日)".to_string()));
        assert_eq!(same.title(), "SideM 11th STAGE");

        // 公演名がライブ名を丸ごと含む稀な形: 公演名そのものが本体で、行には公演名の見分けが残る。
        let odd = show_identity("24magic", "24magic ★フィナーレ★(24magic 生放送)", "2020-01-01");
        assert_eq!(odd.heading, "★フィナーレ★(24magic 生放送)");
        assert_eq!(odd.label, None);
        assert_eq!(odd.short.text(), "★フィナーレ★(24magic 生放送)");
        assert!(odd.short.is_name());
    }

    #[test]
    fn width_variants_of_at_sign_still_overlap() {
        // 実データ: ライブ名は `IDOLM@STER`、公演名は `IDOLM＠STER` (全角)。
        let event = "THE IDOLM@STER MR ST@GE!! MUSIC♪GROOVE☆ENCORE";
        let show = "THE IDOLM＠STER MR ST@GE!! MUSIC♪GROOVE☆ENCORE 第三部(2/24日替わり主演アイドル：双海亜美・真美)";
        assert_eq!(
            distinguishing_show_name(event, show),
            Some("第三部(2/24日替わり主演アイドル：双海亜美・真美)")
        );
        // 返るのは元の綴りのまま (折った形を返さない)。
        assert_eq!(distinguishing_show_name("Ｌｉｖｅ", "Live　ＤＡＹ１"), Some("ＤＡＹ１"));
    }

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
