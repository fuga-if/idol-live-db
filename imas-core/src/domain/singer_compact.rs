//! 全体曲の歌唱者表記を 1 行に畳む。
//!
//! # なぜ要るか (2026-10-31 fuga の報告「全体曲で全員分の名前が表示されて見た目が悪い」)
//!
//! `songs.singer_label` には公式クレジットがそのまま入っていて、全体曲は
//! `765 MILLION ALLSTARS 天海春香、春日未来、…` のように **50 人を超える名前**を抱える。
//! 一覧の副題・詳細の歌唱者行・セトリの名義・再生中バーがこれを生で出すと、
//! 名前が行を埋めて肝心の名義が読めない。
//!
//! 全員の名前は捨てない。詳細の「歌唱アイドル」(アイコンの並び) が全員を持っているので、
//! 1 行で見せる場所だけ畳む。**元の値を変えるのではなく、見せるときに畳む**
//! (検索・群分け・照合は生の `singer_label` を使い続ける)。
//!
//! # 畳み方 (上から順に当てる)
//!
//! 1. 名義 + 括弧の中に個人名: `シャイニーカラーズ（櫻木真乃、…）` → `シャイニーカラーズ`。
//!    括弧が複数あれば全部外す: `Café Parade（…）、Altessimo（…）` → `Café Parade、Altessimo`。
//!    括弧の中に `、` が無いもの (`315 STARS(インテリVer.)`) は版の注記なので残す。
//! 2. 英字の名義 + 空白 + 個人名: `765 MILLION ALLSTARS 天海春香、…` → `765 MILLION ALLSTARS`。
//! 3. 先頭だけ英字の名義で残りが個人名: `IM@S ALLSTARS、星井美希、…` → `IM@S ALLSTARS`。
//! 4. 個人名が [`COMPACT_FROM`] 人以上: `島村卯月・大石泉・夢見りあむ ほか 7 人`。
//!
//! どれにも当たらなければそのまま返す (ソロ・少人数の曲は今の見え方のまま)。

use crate::domain::display_join::join_capped;

/// この人数から名前の列挙を畳む。5 人までのユニット曲はこれまでどおり全員の名前を出す。
pub const COMPACT_FROM: usize = 6;

/// 畳んだときに先頭から出す人数。
const SHOWN: usize = 3;

/// 畳んだ列挙の区切り。一覧の名義 (`performer_label`) と同じ詰めた中黒。
const SEPARATOR: &str = "・";

/// `singer_label` の名前の区切り。公式クレジットは読点で並べている。
/// 中黒 (`・`) では切らない: `イヴ・サンタクロース` のように名前の中に入っている。
const NAME_SEPARATOR: char = '、';

fn opens(c: char) -> Option<char> {
    match c {
        '（' => Some('）'),
        '(' => Some(')'),
        '[' => Some(']'),
        '［' => Some('］'),
        '【' => Some('】'),
        _ => None,
    }
}

fn is_close(c: char) -> bool {
    matches!(c, '）' | ')' | ']' | '］' | '】')
}

/// 1. 個人名を抱えた括弧を外す。外すものが無ければ `None`。
///
/// 括弧は入れ子になる (`315 STARS（DRAMATIC STARS（天道輝、…）、…）`) ので深さで数える。
/// 閉じが無い (途中で切れた) 括弧は末尾までを中身とみなす。
fn strip_member_brackets(label: &str) -> Option<String> {
    let chars: Vec<char> = label.chars().collect();
    let mut out = String::new();
    let mut stripped = false;
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if opens(c).is_none() {
            // 対になっていない閉じ (`…上田麗奈））`) は、括弧を外した跡に残すと浮くので落とす。
            if !is_close(c) {
                out.push(c);
            }
            i += 1;
            continue;
        }
        // 対応する閉じを探す。
        let mut depth = 0usize;
        let mut j = i;
        while j < chars.len() {
            if opens(chars[j]).is_some() {
                depth += 1;
            } else if is_close(chars[j]) {
                depth -= 1;
                if depth == 0 {
                    break;
                }
            }
            j += 1;
        }
        let end = j.min(chars.len());
        let inner: String = chars[i + 1..end].iter().collect();
        if inner.contains(NAME_SEPARATOR) {
            stripped = true;
        } else {
            out.extend(&chars[i..(end + 1).min(chars.len())]);
        }
        i = end + 1;
    }
    if !stripped {
        return None;
    }
    // 括弧を外した跡の空白・読点の重なりを均す。
    let parts: Vec<&str> = out
        .split(NAME_SEPARATOR)
        .map(str::trim)
        .filter(|p| !p.is_empty())
        .collect();
    (!parts.is_empty()).then(|| parts.join("、"))
}

fn is_ascii_name(s: &str) -> bool {
    !s.is_empty() && s.is_ascii()
}

/// 1 行に出す歌唱者表記。畳む必要が無ければ元の値 (前後の空白だけ落とす) を返す。
pub fn compact_singer_label(label: &str) -> String {
    let label = label.trim();
    // 少人数の表記 (`Altessimo（都築圭、神楽麗）`) は畳まない。今ある名前を消さないため、
    // 畳むのは名前が [`COMPACT_FROM`] 人以上並ぶ (= 行を埋める) ときだけ。
    if label.matches(NAME_SEPARATOR).count() + 1 < COMPACT_FROM {
        return label.to_string();
    }
    if let Some(stripped) = strip_member_brackets(label) {
        // 括弧を外しても名義が大勢並ぶ (ユニットを 8 つ並べた曲など) ことはあるが、
        // それは「名義の並び」で、人の名前ではない。ここで止める。
        return stripped;
    }
    let names: Vec<&str> = label
        .split(NAME_SEPARATOR)
        .map(str::trim)
        .filter(|n| !n.is_empty())
        .collect();
    if names.len() < COMPACT_FROM {
        return label.to_string();
    }
    // 2. `765 MILLION ALLSTARS 天海春香` — 英字の名義と 1 人目の間が空白。
    //    `エミリー スチュアート` のような空白入りの名前は、前半が英字でないので当たらない。
    if let Some((group, first)) = names[0].rsplit_once(' ') {
        let group = group.trim();
        if is_ascii_name(group) && !first.is_ascii() {
            return group.to_string();
        }
    }
    // 3. `IM@S ALLSTARS、星井美希、…` — 先頭だけが英字。ユニット名の並び
    //    (`DRAMATIC STARS、Jupiter、…`) は 2 つめ以降も英字なので当たらない。
    if is_ascii_name(names[0]) && names[1..].iter().all(|n| !n.is_ascii()) {
        return names[0].to_string();
    }
    // ユニット名の並び (英字の名前が 2 つ以上) は人数で畳まない。「ほか 4 人」と数えると嘘になる。
    if names.iter().filter(|n| n.is_ascii()).count() >= 2 {
        return label.to_string();
    }
    cap_names(&names).unwrap_or_else(|| label.to_string())
}

/// 4. 名前の列を畳む。[`COMPACT_FROM`] 人未満なら `None` (呼ぶ側は今の並べ方のまま出す)。
pub fn cap_names<S: AsRef<str>>(names: &[S]) -> Option<String> {
    cap_names_with(names, SEPARATOR)
}

/// [`cap_names`] の区切り違い。セトリ行は公式のセトリ画像に合わせて `／` で並べる。
pub fn cap_names_with<S: AsRef<str>>(names: &[S], separator: &str) -> Option<String> {
    let names: Vec<&str> = names
        .iter()
        .map(|n| n.as_ref().trim())
        .filter(|n| !n.is_empty())
        .collect();
    if names.len() < COMPACT_FROM {
        return None;
    }
    join_capped(&names, separator, SHOWN, "人")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn group_with_members_in_brackets_keeps_the_group() {
        assert_eq!(
            compact_singer_label("765 MILLION ALLSTARS（天海春香、春日未来、如月千早、木下ひなた、四条貴音、ジュリア）"),
            "765 MILLION ALLSTARS"
        );
        assert_eq!(
            compact_singer_label("CINDERELLA PROJECT [島村卯月、渋谷凛、本田未央、双葉杏、三村かな子、城ヶ崎莉嘉]"),
            "CINDERELLA PROJECT"
        );
    }

    /// 括弧の中に読点が無いのは版の注記。名義の一部として残す。
    #[test]
    fn version_notes_in_brackets_stay() {
        assert_eq!(
            compact_singer_label("315 STARS(インテリVer.)（伊集院北斗、桜庭薫、神楽麗、鷹城恭二、蒼井悠介、華村翔真）"),
            "315 STARS(インテリVer.)"
        );
        assert_eq!(compact_singer_label("315 STARS (インテリ Ver.)"), "315 STARS (インテリ Ver.)");
    }

    #[test]
    fn nested_and_multiple_groups_keep_every_group_name() {
        assert_eq!(
            compact_singer_label("315 STARS（DRAMATIC STARS（天道輝、桜庭薫、柏木翼）、Beit（鷹城恭二、ピエール、渡辺みのり））"),
            "315 STARS"
        );
        assert_eq!(
            compact_singer_label("Café Parade（神谷幸広、東雲荘一郎、卯月巻緒）、Altessimo（神楽麗、都築圭）、Legenders"),
            "Café Parade、Altessimo、Legenders"
        );
    }

    /// 途中で切れた括弧 (閉じが無い) でも名義だけ残る。
    #[test]
    fn unterminated_bracket_still_strips() {
        assert_eq!(
            compact_singer_label("シャイニーカラーズ（櫻木真乃、風野灯織、八宮めぐる、月岡恋鐘、田中摩美々、白瀬咲耶"),
            "シャイニーカラーズ"
        );
    }

    #[test]
    fn ascii_group_then_space_then_names() {
        let label = "765 MILLION ALLSTARS 天海春香、春日未来、如月千早、木下ひなた、四条貴音、ジュリア";
        assert_eq!(compact_singer_label(label), "765 MILLION ALLSTARS");
        let five = "THE IDOLM@STER FIVE STARS!!!!! 天海春香、如月千早、星井美希、島村卯月、渋谷凛、本田未央";
        assert_eq!(compact_singer_label(five), "THE IDOLM@STER FIVE STARS!!!!!");
    }

    #[test]
    fn leading_ascii_group_before_names() {
        let label = "IM@S ALLSTARS、星井美希、如月千早、高槻やよい、萩原雪歩、菊地真";
        assert_eq!(compact_singer_label(label), "IM@S ALLSTARS");
    }

    /// ユニット名の並びは人の名前ではないので、英字の先頭を名義と取り違えない。
    #[test]
    fn a_list_of_unit_names_is_not_mistaken_for_a_group() {
        let label = "DRAMATIC STARS、Jupiter、Beit、High×Joker、Café Parade、もふもふえん、F-LAGS";
        assert_eq!(compact_singer_label(label), label);
    }

    #[test]
    fn many_names_are_capped() {
        let label = "島村卯月、大石泉、夢見りあむ、早坂美玲、西園寺琴歌、大槻唯、森久保乃々";
        assert_eq!(compact_singer_label(label), "島村卯月・大石泉・夢見りあむ ほか 4 人");
    }

    /// 空白入りの名前 (`エミリー スチュアート`) を英字の名義と取り違えない。
    #[test]
    fn a_name_with_a_space_is_not_a_group() {
        let label = "エミリー スチュアート、徳川まつり、春日未来、最上静香、伊吹翼、北沢志保";
        assert_eq!(compact_singer_label(label), "エミリー スチュアート・徳川まつり・春日未来 ほか 3 人");
    }

    /// 少人数のユニット表記は名前ごと残す (今ある名前を消さない)。
    #[test]
    fn small_unit_credits_keep_their_members() {
        assert_eq!(compact_singer_label("Altessimo（都築圭、神楽麗）"), "Altessimo（都築圭、神楽麗）");
        assert_eq!(
            compact_singer_label("マイティーセーラーズ（伊吹翼×高坂海美、上田麗奈））"),
            "マイティーセーラーズ（伊吹翼×高坂海美、上田麗奈））"
        );
    }

    #[test]
    fn small_credits_are_untouched() {
        assert_eq!(compact_singer_label("天海春香、如月千早、高槻やよい、菊地真、星井美希"), "天海春香、如月千早、高槻やよい、菊地真、星井美希");
        assert_eq!(compact_singer_label(" 如月千早 "), "如月千早");
        assert_eq!(compact_singer_label("765PRO ALLSTARS"), "765PRO ALLSTARS");
        assert_eq!(compact_singer_label("イヴ・サンタクロース"), "イヴ・サンタクロース");
        assert_eq!(compact_singer_label(""), "");
    }

    #[test]
    fn cap_names_only_from_the_threshold() {
        assert_eq!(cap_names(&["a", "b", "c", "d", "e"]), None);
        assert_eq!(cap_names(&["a", "b", "", "c", "d", "e", "f"]).as_deref(), Some("a・b・c ほか 3 人"));
    }
}
