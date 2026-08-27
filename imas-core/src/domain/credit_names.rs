//! 作詞・作曲・編曲のクレジット表記を、人ごとに割る。
//!
//! `songs.composer` 等は「BNEI(中川浩二・小林啓樹)」「AYATOMO (MAYSON's PARTY)、木村孝明」
//! のような自由文字列で、1 つの欄に複数人が入る。人ごとの読みを持たせるにも、
//! 「この人が作った曲」で絞り込むにも、人単位に割る必要がある。
//!
//! # 括弧の中は一律に割れない
//!
//! `X(Y)` が「所属(人)」と「人(所属)」の両方に使われている:
//!
//! - `BNEI(中川浩二・小林啓樹)` — 会社が前、中が人。**割りたい**
//! - `佐高陵平(Hifumi,Inc.)` — 人が前、中が社名。**割ってはいけない**
//!
//! 実データを見ると、括弧の中の区切りは次のように分かれていた:
//!
//! - `・` `、` … すべて人の並び (BNEI/NBGI/NBSI の連名、Massive New Krew の構成員)
//! - `,` `/` … すべて社名や別表記の一部 (`Digz, Inc. Group` / `Hifumi,inc.` /
//!   `Relic Lyric, inc.` / `m-flo,block.fm` / `Heo Jeongjoo/허정주`)
//!
//! そこで **括弧の外では 5 種類すべてで割り、括弧の中では `・` と `、` だけで割る**。
//! 構造では区別できないので、実データに沿った規則にしている。
//!
//! 割るときは前置の所属を配る (`BNEI(中川浩二・小林啓樹)` →
//! `BNEI(中川浩二)` と `BNEI(小林啓樹)`)。所属を落とすと、単独で入っている
//! `BNEI(椎名豪)` と表記が揃わず、同じ会社の人が二通りに分かれてしまう。

/// 括弧の外で人を分ける区切り。
const OUTER_SEPARATORS: [char; 5] = ['/', '／', ',', '、', '・'];
/// 括弧の中で人を分ける区切り (`,` と `/` は社名の一部なので入れない)。
const INNER_SEPARATORS: [char; 2] = ['、', '・'];

/// クレジット表記を人ごとに割る。空白だけの断片は落とす。
pub fn split_credits(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    for part in split_outside_parens(text) {
        match split_inside_parens(&part) {
            Some(people) => out.extend(people),
            None => out.push(part),
        }
    }
    out
}

/// 括弧の深さが 0 のところだけで割る。
fn split_outside_parens(text: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut buf = String::new();
    let mut depth = 0i32;
    for ch in text.chars() {
        match ch {
            '(' | '（' => {
                depth += 1;
                buf.push(ch);
            }
            ')' | '）' => {
                depth -= 1;
                buf.push(ch);
            }
            c if depth == 0 && OUTER_SEPARATORS.contains(&c) => {
                push_trimmed(&mut parts, &buf);
                buf.clear();
            }
            c => buf.push(c),
        }
    }
    push_trimmed(&mut parts, &buf);
    parts
}

/// `所属(人1・人2)` を `所属(人1)` `所属(人2)` に開く。開けない形なら None。
fn split_inside_parens(part: &str) -> Option<Vec<String>> {
    let open = part.find(['(', '（'])?;
    // 閉じ括弧が末尾でないもの (人(所属)つき の後ろに何か続く形) は触らない。
    let close = part.rfind([')', '）'])?;
    if close + part[close..].chars().next()?.len_utf8() != part.len() {
        return None;
    }
    let prefix = part[..open].trim();
    let open_len = part[open..].chars().next()?.len_utf8();
    let inner = &part[open + open_len..close];
    if !inner.contains(INNER_SEPARATORS) {
        return None;
    }
    // 所属が前置されていない `(人1・人2)` は、所属を配りようがないので中身だけ返す。
    let mut people = Vec::new();
    for name in inner.split(INNER_SEPARATORS) {
        let name = name.trim();
        if name.is_empty() {
            continue;
        }
        people.push(if prefix.is_empty() {
            name.to_string()
        } else {
            format!("{prefix}({name})")
        });
    }
    (!people.is_empty()).then_some(people)
}

fn push_trimmed(parts: &mut Vec<String>, buf: &str) {
    let t = buf.trim();
    if !t.is_empty() {
        parts.push(t.to_string());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_plain_lists() {
        assert_eq!(split_credits("ArmySlick、Lauren Kaori"), ["ArmySlick", "Lauren Kaori"]);
        assert_eq!(split_credits("Ayaka Miyake, TAKAROT"), ["Ayaka Miyake", "TAKAROT"]);
        assert_eq!(split_credits("古屋真"), ["古屋真"]);
    }

    /// 所属が前置された連名は、所属を配って人ごとに割る。
    #[test]
    fn distributes_the_company_prefix() {
        assert_eq!(
            split_credits("BNEI(中川浩二・小林啓樹)"),
            ["BNEI(中川浩二)", "BNEI(小林啓樹)"]
        );
        assert_eq!(
            split_credits("NBGI(大上昌子、おおくぼひろし)"),
            ["NBGI(大上昌子)", "NBGI(おおくぼひろし)"]
        );
    }

    /// 社名に含まれる `,` や `/` では割らない。
    ///
    /// ここで割ると「佐高陵平(Hifumi」と「Inc.)」のような壊れた人名が生まれる。
    #[test]
    fn does_not_split_inside_a_company_name() {
        assert_eq!(split_credits("佐高陵平(Hifumi,Inc.)"), ["佐高陵平(Hifumi,Inc.)"]);
        assert_eq!(
            split_credits("Dirty Orange (Digz, Inc. Group)"),
            ["Dirty Orange (Digz, Inc. Group)"]
        );
        assert_eq!(
            split_credits("☆Taku Takahashi (m-flo,block.fm)"),
            ["☆Taku Takahashi (m-flo,block.fm)"]
        );
        assert_eq!(
            split_credits("ジョンジュ(Heo Jeongjoo/허정주)"),
            ["ジョンジュ(Heo Jeongjoo/허정주)"]
        );
    }

    /// 括弧つきの人が並んでいる形は、括弧の外の区切りで割れる。
    #[test]
    fn splits_between_people_who_each_have_an_affiliation() {
        assert_eq!(
            split_credits("Mitsu.J(Digz, Inc. Group)、ladyhood(Digz, Inc. Group)"),
            ["Mitsu.J(Digz, Inc. Group)", "ladyhood(Digz, Inc. Group)"]
        );
        assert_eq!(
            split_credits("AYATOMO (MAYSON's PARTY)、木村孝明"),
            ["AYATOMO (MAYSON's PARTY)", "木村孝明"]
        );
    }

    /// ユニット名 + 構成員も同じ形で割れる。
    #[test]
    fn splits_unit_members() {
        assert_eq!(
            split_credits("invisible manners(平山大介・福山整)"),
            ["invisible manners(平山大介)", "invisible manners(福山整)"]
        );
    }

    #[test]
    fn drops_empty_fragments() {
        assert_eq!(split_credits(""), Vec::<String>::new());
        assert_eq!(split_credits("  、 "), Vec::<String>::new());
        assert_eq!(split_credits("古屋 真、"), ["古屋 真"]);
    }
}

