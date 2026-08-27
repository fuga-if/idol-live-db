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
///
/// 全角スペース (U+3000) も入っている。実データの 6 例すべてが人の区切りで、
/// 名前の中に現れたことは一度も無かった (`夕野ヨシミ (IOSYS)　狐夢想 (COOL＆CREATE)` /
/// `星銀乃丈　ストリングスアレンジ：松田彬人`)。半角スペースは逆に名前の中でしか
/// 使われていない (`古屋 真` `TAKT (TRYTONELABO)` `Lauren Kaori`) ので入れない。
///
/// `×` は共作を表す 1 例だけ (`渡辺徹×日比野裕史`)。両名とも単独でも入っていて、
/// 割らないと同じ人が「連名の 1 人」として二重に持たれる。
///
/// `＆` は入れない。人の区切り (`リスナーP有志＆ミンゴス＆ちあking`) とユニット名
/// (`原紗友里＆青木瑠璃子 from CINDERELLA PARTY！`) の両方に使われていて、
/// 構造でも実データでも見分けが付かない。
const OUTER_SEPARATORS: [char; 7] = ['/', '／', ',', '、', '・', '\u{3000}', '\u{00D7}'];
/// 括弧の中で人を分ける区切り (`,` と `/` は社名の一部なので入れない)。
const INNER_SEPARATORS: [char; 2] = ['、', '・'];

/// 名前ではなく役割を表す語。`ストリングスアレンジ：松田彬人` の前半。
///
/// 役割注記は前の人と**全角スペースで区切られて**並ぶ (`家原正樹　　弦管編曲：森悠也`)。
/// 区切ってから注記を外すので、前の人 (家原正樹) が落ちない。
/// 区切りに入れる前は 1 断片として扱われ、`：` の後ろだけが残って前の人が消えていた。
const ROLE_MARK: char = '：';

/// 名前として扱わない値。「不明」の代わりに置かれた記号。
const PLACEHOLDERS: [&str; 3] = ["-", "ー", "―"];

/// クレジット表記を人ごとに割る。空白だけの断片と、名前でない値は落とす。
pub fn split_credits(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    for part in split_outside_parens(text) {
        // 役割注記が付いていたら、名前はその後ろ (`弦編曲：森悠也` → `森悠也`)。
        let part = match part.rsplit_once(ROLE_MARK) {
            Some((_, person)) if !person.trim().is_empty() => person.trim().to_string(),
            _ => part,
        };
        if PLACEHOLDERS.contains(&part.as_str()) {
            continue;
        }
        match split_inside_parens(&part) {
            Some(people) => out.extend(people),
            None => out.push(part),
        }
    }
    out
}

/// `・` が名前の一部か、人の区切りかを見分ける。
///
/// `R・O・N` `m.c.A・T` は中黒ごと 1 人の名前で、割ると `R` `O` `N` という
/// 存在しない作家が生まれる。人の並びなら各断片は姓名の長さになるので、
/// **1 文字の断片が出る割り方はしない**。
fn nakaguro_is_part_of_the_name(text: &str) -> bool {
    text.split('\u{30FB}').any(|p| p.trim().chars().count() <= 1)
}

/// 括弧の深さが 0 のところだけで割る。
fn split_outside_parens(text: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut buf = String::new();
    let mut depth = 0i32;
    let keep_nakaguro = nakaguro_is_part_of_the_name(text);
    for ch in text.chars() {
        match ch {
            '(' | '（' | '[' | '［' => {
                depth += 1;
                buf.push(ch);
            }
            ')' | '）' | ']' | '］' => {
                depth -= 1;
                buf.push(ch);
            }
            '\u{30FB}' if keep_nakaguro => buf.push(ch),
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
    let open = part.find(['(', '（', '[', '［'])?;
    // 閉じ括弧が末尾でないもの (人(所属)つき の後ろに何か続く形) は触らない。
    let close = part.rfind([')', '）', ']', '］'])?;
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

    /// `・` が名前の一部のときは割らない。
    ///
    /// `R・O・N` を割ると `R` `O` `N` という存在しない作家が 3 人生まれる。
    #[test]
    fn a_stylised_name_is_not_split_at_the_nakaguro() {
        assert_eq!(split_credits("R・O・N"), ["R・O・N"]);
        assert_eq!(split_credits("m.c.A・T"), ["m.c.A・T"]);
        // 人の並びは今までどおり割る。
        assert_eq!(split_credits("中川浩二・小林啓樹"), ["中川浩二", "小林啓樹"]);
    }

    /// 役割の注記が付いていたら、名前はその後ろ。
    #[test]
    fn a_role_annotation_is_dropped() {
        assert_eq!(split_credits("ストリングスアレンジ：松田彬人"), ["松田彬人"]);
        assert_eq!(
            split_credits("堀江晶太、Orchestra Arrangement：Evan Call"),
            ["堀江晶太", "Evan Call"]
        );
    }

    /// 全角スペースは人の区切り。半角スペースは名前の一部。
    ///
    /// 区切らないと役割注記の規則に飲まれ、前の人が丸ごと消える
    /// (`家原正樹　　弦管編曲：森悠也` が `森悠也` だけになっていた)。
    #[test]
    fn an_ideographic_space_separates_people() {
        assert_eq!(
            split_credits("夕野ヨシミ (IOSYS)\u{3000}狐夢想 (COOL＆CREATE)"),
            ["夕野ヨシミ (IOSYS)", "狐夢想 (COOL＆CREATE)"]
        );
        assert_eq!(
            split_credits("家原正樹\u{3000}\u{3000}弦管編曲：森悠也"),
            ["家原正樹", "森悠也"]
        );
        assert_eq!(
            split_credits("星銀乃丈\u{3000}ストリングスアレンジ：松田彬人"),
            ["星銀乃丈", "松田彬人"]
        );
        // 末尾の全角スペースは空断片になるだけ。
        assert_eq!(split_credits("Cocoro.(Dream Monster)\u{3000}"), ["Cocoro.(Dream Monster)"]);
        // 半角スペースでは割らない。
        assert_eq!(split_credits("TAKT (TRYTONELABO)"), ["TAKT (TRYTONELABO)"]);
        assert_eq!(split_credits("古屋 真"), ["古屋 真"]);
    }

    /// 共作を表す `×` も人の区切り。
    #[test]
    fn a_multiplication_sign_separates_collaborators() {
        assert_eq!(split_credits("渡辺徹×日比野裕史"), ["渡辺徹", "日比野裕史"]);
    }

    /// `＆` では割らない。ユニット名にも使われていて見分けが付かない。
    #[test]
    fn an_ampersand_is_not_a_separator() {
        assert_eq!(
            split_credits("原紗友里＆青木瑠璃子 from CINDERELLA PARTY！"),
            ["原紗友里＆青木瑠璃子 from CINDERELLA PARTY！"]
        );
    }

    /// 角括弧の中の並びも開く (韓国の作家陣がこの形で入っている)。
    #[test]
    fn a_bracketed_list_is_opened_too() {
        assert_eq!(
            split_credits("Gamenrider［서용배、박우상］"),
            ["Gamenrider(서용배)", "Gamenrider(박우상)"]
        );
    }

    /// 「不明」の代わりに置かれた記号は名前として扱わない。
    #[test]
    fn placeholders_are_not_names() {
        assert_eq!(split_credits("-"), Vec::<String>::new());
        assert_eq!(split_credits("ー"), Vec::<String>::new());
    }

    #[test]
    fn drops_empty_fragments() {
        assert_eq!(split_credits(""), Vec::<String>::new());
        assert_eq!(split_credits("  、 "), Vec::<String>::new());
        assert_eq!(split_credits("古屋 真、"), ["古屋 真"]);
    }
}

/// 所属を前に置く会社の略称。
///
/// `X(Y)` は「所属(人)」と「人(所属)」の両方に使われていて構造では区別できない。
/// 前に置く側は実データではバンダイナムコの社名変遷だけで、それ以外
/// (`ARM(IOSYS)` `TAKT(...)` 等) はすべて「人(所属)」だった。
const COMPANY_PREFIXES: [&str; 5] = ["BNSI", "NBGI", "BNEI", "BNGI", "NBSI"];

/// 名前の末尾に付く所属の括弧。書き手によって種類が揺れる
/// (`ARM(IOSYS)` `ARM (IOSYS)` `ARM（IOSYS）` `Asu [The New Classics]`
/// `Apis［TRYTONELABO］` `BNSI〈Jesahm〉`)。
const BRACKET_PAIRS: [(char, char); 5] =
    [('(', ')'), ('（', '）'), ('[', ']'), ('［', '］'), ('〈', '〉')];

/// 表記の揺れを落として、同じ人を 1 つに寄せるための鍵を作る。
///
/// 同じ作家が社名の変遷と括弧の揺れで最大 9 通りに割れていた:
/// `BNEI(佐藤貴文)` `BNSI (佐藤貴文)` `BNSI（佐藤貴文）` `NBGI(佐藤貴文)` `佐藤貴文`
/// `佐藤貴文(Bandai Namco Studios Inc.)` …。曲詳細から作家で絞り込むと、
/// 同じ人が別人として何通りにも分かれてしまう。
///
/// 所属を落として人名だけを取り出す。`X(Y)` の向きは、前が**会社の略称**なら中が人、
/// それ以外は前が人 (実データでは前に置く側はバンダイナムコの略称だけだった)。
/// 日本語名は空白も落とす (`グシミヤギ ヒデユキ` と `グシミヤギヒデユキ` が
/// 別人にならないように)。英字名の空白は残す — 落とすと別の名前になる。
pub fn canonical_credit_key(name: &str) -> String {
    let trimmed = name.trim().trim_end_matches('.').trim();
    let person = strip_affiliation(trimmed);
    // 引用符の字体ゆれ (K's と K’s) を寄せる。
    let person: String = person.chars().map(|c| if c == '\u{2019}' { '\'' } else { c }).collect();
    if person.chars().any(is_japanese) {
        person.chars().filter(|c| !matches!(c, ' ' | '\u{3000}')).collect()
    } else {
        person
    }
}

/// 所属を落として人名だけを返す。
fn strip_affiliation(name: &str) -> &str {
    // ① 会社の略称が前に置かれている形は、括弧の中が人。
    for open in ['(', '（'] {
        if let Some(i) = name.find(open) {
            let outer = name[..i].trim();
            if COMPANY_PREFIXES.contains(&outer) {
                let open_len = name[i..].chars().next().map_or(1, char::len_utf8);
                let inner = &name[i + open_len..];
                let inner = inner.strip_suffix([')', '）']).unwrap_or(inner);
                return inner.trim();
            }
        }
    }
    // ② それ以外は、末尾に付いた括弧を所属として落とす。
    if let Some(head) = strip_trailing_bracket(name) {
        return head;
    }
    // ③ 閉じ忘れ (`酒井拓也(Arte Refact`)。開いたところから後ろを落とす。
    if let Some(i) = first_unclosed_bracket(name) {
        let head = name[..i].trim();
        if !head.is_empty() {
            return head;
        }
    }
    name
}

/// 末尾の括弧を、入れ子を数えて落とす。
///
/// 単純に最後の開き括弧を探すと入れ子で壊れる
/// (`Gamenrider(서용배(Seo Yong Bae))` が `Gamenrider(서용배` になる)。
///
/// 開きと閉じの**種類は照合しない**。クレジットは人が手で打った文字列で、
/// 実際に `滝澤俊輔(TRYTONELABO]` のような打ち間違いが入っている。同種ペアだけを
/// 対応させると、この形は所属を落とせず括弧ごと人名になり、正しく打たれた
/// `滝澤俊輔(TRYTONELABO)` と別人に分かれてしまう。
/// 閉じ忘れを見る `first_unclosed_bracket` も同じ規則 (どの閉じでも 1 つ戻す)。
fn strip_trailing_bracket(name: &str) -> Option<&str> {
    let (_, last) = name.char_indices().next_back()?;
    if !is_closing_bracket(last) {
        return None;
    }
    let mut depth = 0i32;
    for (i, ch) in name.char_indices().rev() {
        if is_closing_bracket(ch) {
            depth += 1;
        } else if is_opening_bracket(ch) {
            depth -= 1;
            if depth == 0 {
                let head = name[..i].trim();
                return (!head.is_empty()).then_some(head);
            }
        }
    }
    None
}

fn is_opening_bracket(c: char) -> bool {
    BRACKET_PAIRS.iter().any(|(o, _)| *o == c)
}

fn is_closing_bracket(c: char) -> bool {
    BRACKET_PAIRS.iter().any(|(_, c2)| *c2 == c)
}

/// 閉じられていない開き括弧の位置。
fn first_unclosed_bracket(name: &str) -> Option<usize> {
    let mut stack: Vec<usize> = Vec::new();
    for (i, ch) in name.char_indices() {
        if is_opening_bracket(ch) {
            stack.push(i);
        } else if is_closing_bracket(ch) {
            stack.pop();
        }
    }
    stack.first().copied()
}

fn is_japanese(c: char) -> bool {
    matches!(c, '\u{3040}'..='\u{309F}' | '\u{30A0}'..='\u{30FF}' | '\u{4E00}'..='\u{9FFF}')
}

#[cfg(test)]
mod canonical_tests {
    use super::*;

    /// 社名の変遷と括弧の揺れを越えて同じ鍵になる。
    #[test]
    fn the_same_person_gets_one_key() {
        for n in [
            "BNEI(佐藤貴文)", "BNSI (佐藤貴文)", "BNSI(佐藤貴文）", "BNSI（佐藤貴文）",
            "NBGI(佐藤貴文)", "佐藤貴文", "佐藤貴文(Bandai Namco Studios Inc.)",
            "BNSI(佐藤貴文).",
        ] {
            assert_eq!(canonical_credit_key(n), "佐藤貴文", "{n}");
        }
    }

    /// 日本語名の空白は落とす (所属の書き方で入ったり入らなかったりする)。
    #[test]
    fn spaces_in_japanese_names_are_dropped() {
        assert_eq!(canonical_credit_key("グシミヤギ ヒデユキ"), "グシミヤギヒデユキ");
        assert_eq!(canonical_credit_key("グシミヤギヒデユキ(Hifumi,inc.)"), "グシミヤギヒデユキ");
    }

    /// 英字名の空白は残す (落とすと別の名前になる)。
    #[test]
    fn spaces_in_latin_names_are_kept() {
        assert_eq!(canonical_credit_key("BNSI (Taku Inoue)"), "Taku Inoue");
        assert_eq!(canonical_credit_key("Taku Inoue"), "Taku Inoue");
    }

    /// 「人(所属)」を取り違えない。ARM は人で IOSYS が所属。
    ///
    /// 括弧の種類・空白の有無は書き手によって揺れるので、そこも寄せる。
    #[test]
    fn a_person_with_an_affiliation_is_not_inverted() {
        for n in ["ARM(IOSYS)", "ARM (IOSYS)", "ARM（IOSYS）", "ARM"] {
            assert_eq!(canonical_credit_key(n), "ARM", "{n}");
        }
        assert_eq!(canonical_credit_key("Mitsu.J (Digz, Inc. Group)"), "Mitsu.J");
    }

    /// 開きと閉じが食い違う打ち間違いも、所属として落とす。
    ///
    /// `滝澤俊輔(TRYTONELABO]` は実データにあった表記。同種ペアだけを対応させると
    /// 括弧ごと人名になり、`滝澤俊輔` と別人に分かれる (実際に分かれていた)。
    #[test]
    fn a_mistyped_bracket_pair_still_drops_the_affiliation() {
        for n in [
            "滝澤俊輔(TRYTONELABO)",
            "滝澤俊輔（TRYTONELABO）",
            "滝澤俊輔[TRYTONELABO]",
            "滝澤俊輔［TRYTONELABO］",
            "滝澤俊輔(TRYTONELABO]",
        ] {
            assert_eq!(canonical_credit_key(n), "滝澤俊輔", "{n}");
        }
        assert_eq!(canonical_credit_key("TAKT(TRYTONELABO]"), "TAKT");
        // 角括弧・山括弧も所属として落とす。
        assert_eq!(canonical_credit_key("Asu [The New Classics]"), "Asu");
        assert_eq!(canonical_credit_key("Apis［TRYTONELABO］"), "Apis");
    }

    /// 入れ子の括弧でも所属だけを落とす。
    #[test]
    fn nested_brackets_do_not_break_the_key() {
        assert_eq!(canonical_credit_key("Gamenrider(서용배(Seo Yong Bae))"), "Gamenrider");
    }

    /// 閉じ忘れの括弧も所属として落とす (データ側の打ち間違い)。
    #[test]
    fn an_unclosed_bracket_is_still_an_affiliation() {
        assert_eq!(canonical_credit_key("酒井拓也(Arte Refact"), "酒井拓也");
        assert_eq!(canonical_credit_key("酒井拓也(Arte Refact)"), "酒井拓也");
        assert_eq!(canonical_credit_key("酒井拓也 (Arte Refact)"), "酒井拓也");
        assert_eq!(canonical_credit_key("酒井拓也（Arte Refact）"), "酒井拓也");
    }

    /// 引用符の字体ゆれを寄せる (K's と K’s)。
    #[test]
    fn curly_and_straight_apostrophes_are_the_same_person() {
        assert_eq!(canonical_credit_key("K's"), canonical_credit_key("K’s"));
    }
}




