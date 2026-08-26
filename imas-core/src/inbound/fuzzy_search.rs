//! あいまい検索の FFI 口。

use crate::domain::fuzzy_search::{fuzzy_matches as one, fuzzy_matches_multi as multi, FuzzyHit};

/// 候補群からあいまい一致を拾う (1 件 = 1 綴り)。
///
/// 返る `index` は渡した配列の添字 (0 起点)。並びは
/// 「部分一致 → 編集距離が小さい順 → 元の並び順」なのでそのまま出せばよい。
#[uniffi::export]
pub fn fuzzy_matches(haystacks: Vec<String>, needle: String, limit: u32) -> Vec<FuzzyHit> {
    one(&haystacks, &needle, limit)
}

/// 1 件につき複数の綴りを持てる版 (曲名・読み仮名・別名など)。
///
/// **曲の検索ではこちらを使い、[曲名, 読み] を渡すこと。**
/// 曲名だけだと、ひらがなで打っても漢字の曲名には当たらない
/// (編集距離では 願 と ねが を同一視できないため)。
#[uniffi::export]
pub fn fuzzy_matches_multi(
    haystacks: Vec<Vec<String>>,
    needle: String,
    limit: u32,
) -> Vec<FuzzyHit> {
    multi(&haystacks, &needle, limit)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn delegates_without_logic() {
        let h = vec!["シャイニーカラーズ".to_string(), "Star!!".to_string()];
        assert_eq!(fuzzy_matches(h.clone(), "しゃいにー".into(), 5), one(&h, "しゃいにー", 5));
    }

    #[test]
    fn multi_spelling_reaches_kanji_titles_via_reading() {
        let items = vec![
            vec!["お願い！シンデレラ".to_string(), "おねがいシンデレラ".to_string()],
            vec!["Star!!".to_string()],
        ];
        let got = fuzzy_matches_multi(items, "おねがいしんでれら".into(), 5);
        assert_eq!(got.first().map(|h| h.index), Some(0), "{got:?}");
    }
}
