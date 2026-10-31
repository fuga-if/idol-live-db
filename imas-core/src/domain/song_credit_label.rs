//! 曲の一覧の行に出す名義 (歌唱者の表記) を 1 つに決める。
//!
//! 全体曲は歌唱者が 50 人を超えることがあり、個人名を連ねると行が画面を埋める。
//! ユニット名・名義があればそれを出し、無いときだけ個人名を連ねる。
//!
//! 優先: `unit_name` → `singer_label` → 個人名の並びの括弧前 (「MILLIONSTARS（…）」) → 個人名の並び。
//! `singer_label` と個人名の並びは [`compact_singer_label`] で畳んでから出す
//! (`765 MILLION ALLSTARS 天海春香、…` → `765 MILLION ALLSTARS`)。

use crate::domain::singer_compact::compact_singer_label;

/// 行に出す名義。どれも無ければ空文字。
pub fn song_credit_label(unit_name: Option<&str>, singer_label: Option<&str>, artist_names: &str) -> String {
    if let Some(unit) = unit_name.map(str::trim).filter(|t| !t.is_empty()) {
        return unit.to_string();
    }
    if let Some(label) = singer_label.map(str::trim).filter(|t| !t.is_empty()) {
        return compact_singer_label(label);
    }
    let names = artist_names.trim();
    for sep in ['（', '('] {
        if let Some(i) = names.find(sep) {
            let prefix = names[..i].trim();
            if !prefix.is_empty() {
                return prefix.to_string();
            }
        }
    }
    compact_singer_label(names)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unit_name_first_then_singer_label() {
        assert_eq!(song_credit_label(Some("トライアドプリムス"), Some("渋谷凛"), "渋谷凛・神谷奈緒"), "トライアドプリムス");
        assert_eq!(song_credit_label(Some(" "), Some("765 MILLION ALLSTARS"), "天海春香・如月千早"), "765 MILLION ALLSTARS");
    }

    #[test]
    fn falls_back_to_prefix_then_names() {
        assert_eq!(song_credit_label(None, None, "MILLIONSTARS（春日未来、最上静香）"), "MILLIONSTARS");
        assert_eq!(song_credit_label(None, Some(""), "天海春香・如月千早"), "天海春香・如月千早");
        assert_eq!(song_credit_label(None, None, ""), "");
    }

    /// 回帰 (2026-10-31): 全体曲は名義の後ろに全員の名前が付いていて、一覧の行を埋めていた。
    #[test]
    fn whole_cast_credits_are_compacted() {
        let label = "765 MILLION ALLSTARS 天海春香、春日未来、如月千早、木下ひなた、四条貴音、ジュリア";
        assert_eq!(song_credit_label(None, Some(label), ""), "765 MILLION ALLSTARS");
        assert_eq!(
            song_credit_label(None, Some("天海春香、星井美希、如月千早、高槻やよい、萩原雪歩、菊地真"), ""),
            "天海春香・星井美希・如月千早 ほか 3 人"
        );
    }
}

// =============================================================================
// 曲の詳細の歌唱者行
// =============================================================================

/// 曲の詳細 (ヒーロー) に出す歌唱者の 1 行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SongArtistLine {
    /// 画面に出す文字。全体曲は名義 (`765 MILLION ALLSTARS`) か `A・B・C ほか N 人`。
    pub text: String,
    /// 畳む前の全員ぶん。コピーに使う (コピーした人は全員の名前が欲しい)。
    pub full_text: String,
    /// 畳んだか。畳んだときだけ、画面は「歌唱アイドル」(全員のアイコン) への導線を付ける。
    pub is_compact: bool,
}

/// 原唱者の名前を並べる区切り (詳細の既存表示)。
const DETAIL_SEPARATOR: &str = " / ";

/// 曲の詳細の歌唱者行。出せるものが無ければ `None`。
///
/// 原唱者 (`artist_names`) が分かっていれば名前を並べる (これまでどおり)。
/// ただし [`crate::domain::singer_compact::COMPACT_FROM`] 人以上なら名義に畳む:
/// ユニット名 → `singer_label` の名義 → `A・B・C ほか N 人`。
pub fn song_artist_line(
    unit_name: Option<&str>,
    singer_label: Option<&str>,
    artist_names: &[String],
) -> Option<SongArtistLine> {
    use crate::domain::singer_compact::{cap_names, COMPACT_FROM};
    let names: Vec<&str> = artist_names.iter().map(|n| n.trim()).filter(|n| !n.is_empty()).collect();
    if !names.is_empty() {
        let full_text = names.join(DETAIL_SEPARATOR);
        if names.len() < COMPACT_FROM {
            return Some(SongArtistLine { text: full_text.clone(), full_text, is_compact: false });
        }
        let credit = song_credit_label(unit_name, singer_label, "");
        let text = if credit.is_empty() || credit.contains(" ほか ") {
            // 名義が無い (か名義も名前の列) なら、原唱者の並びを畳む。
            cap_names(&names).unwrap_or_else(|| full_text.clone())
        } else {
            credit
        };
        return Some(SongArtistLine { text, full_text, is_compact: true });
    }
    let full = [singer_label, unit_name]
        .into_iter()
        .flatten()
        .map(str::trim)
        .find(|t| !t.is_empty())?
        .to_string();
    let text = match singer_label.map(str::trim).filter(|t| !t.is_empty()) {
        Some(label) => compact_singer_label(label),
        None => full.clone(),
    };
    let is_compact = text != full;
    Some(SongArtistLine { text, full_text: full, is_compact })
}

#[cfg(test)]
mod artist_line_tests {
    use super::*;

    fn names(n: &[&str]) -> Vec<String> {
        n.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn few_originals_are_listed_as_before() {
        let got = song_artist_line(Some("Team.Sol"), None, &names(&["八宮めぐる", "白瀬咲耶"])).unwrap();
        assert_eq!(got.text, "八宮めぐる / 白瀬咲耶");
        assert!(!got.is_compact);
    }

    /// 回帰 (2026-10-31): 全体曲の詳細で 50 人の名前が並んでいた。
    #[test]
    fn whole_cast_originals_show_the_group_name() {
        let cast = names(&["天海春香", "春日未来", "如月千早", "木下ひなた", "四条貴音", "ジュリア"]);
        let label = "765 MILLION ALLSTARS 天海春香、春日未来、如月千早、木下ひなた、四条貴音、ジュリア";
        let got = song_artist_line(None, Some(label), &cast).unwrap();
        assert_eq!(got.text, "765 MILLION ALLSTARS");
        assert_eq!(got.full_text, "天海春香 / 春日未来 / 如月千早 / 木下ひなた / 四条貴音 / ジュリア");
        assert!(got.is_compact);
        // 名義が無ければ名前を畳む。
        let got = song_artist_line(None, None, &cast).unwrap();
        assert_eq!(got.text, "天海春香・春日未来・如月千早 ほか 3 人");
    }

    const LONG: &str = "765PRO ALLSTARS（天海春香、如月千早、星井美希、高槻やよい、萩原雪歩、菊地真）";

    #[test]
    fn without_originals_falls_back_to_the_credit() {
        let got = song_artist_line(None, Some(LONG), &[]).unwrap();
        assert_eq!(got.text, "765PRO ALLSTARS");
        assert_eq!(got.full_text, LONG);
        assert!(got.is_compact);
        assert_eq!(song_artist_line(Some(" "), None, &[]), None);
        let unit = song_artist_line(Some("Torico"), None, &[]).unwrap();
        assert_eq!(unit.text, "Torico");
        assert!(!unit.is_compact);
    }
}
