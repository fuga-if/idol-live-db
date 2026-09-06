//! セトリ 1 行の歌唱者と原唱者 (オリメン) の関係。
//!
//! 規則は iOS の `SetlistView.classifyCover` / `SetlistRowView.isAllPerformers` と同じ
//! (あちらは今も Swift に自前で持っている。Web はこちらを使う)。
//!
//! 「誰が揃っていないか」はファンが一番知りたいことの 1 つで、集合の差そのもの。
//! ここで求めて Ref に解決するのは呼び出し側に任せる (この層は id しか見ない)。

use std::collections::BTreeSet;

/// 出演者全員で歌う行の札。
pub const FULL_CAST_LABEL: &str = "全員";
/// 「公演には出ているのにこの行では歌っていない原唱者」の並びの前に置く言葉。
pub const MISSING_LABEL: &str = "不参加";

/// 原唱者との関係。JSON にはそのまま camelCase の名前で出る (`partial` 等。CSS の見分け用)。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
#[cfg_attr(
    feature = "web-export",
    derive(ts_rs::TS),
    ts(export, export_to = "../../web/src/lib/schema/")
)]
pub enum Lineup {
    /// 原唱者と歌唱者が完全一致。
    Original,
    /// 原唱者は全員いて、ほかの人も歌っている。
    OriginalPlus,
    /// 原唱者の一部だけがいる。
    Partial,
    /// 原唱者が 1 人もいない。
    Cover,
}

impl Lineup {
    /// 集合の関係だけで決める。原唱者か歌唱者が分からない行は判定しない。
    pub fn classify(original: &BTreeSet<&str>, performers: &BTreeSet<&str>) -> Option<Self> {
        if original.is_empty() || performers.is_empty() {
            return None;
        }
        Some(if original == performers {
            Self::Original
        } else if original.is_subset(performers) {
            Self::OriginalPlus
        } else if !original.is_disjoint(performers) {
            Self::Partial
        } else {
            Self::Cover
        })
    }

    /// 札の文言。全部「オリメン」の言葉で揃える — 曲種別の「カバー (曲)」と混ざらないように。
    /// 一部のときは「何人中何人いるか」を札が持つ (名前を並べない行でも数は分かる)。
    pub fn label(self, present: usize, total: usize) -> String {
        match self {
            Self::Original => "オリメン".to_string(),
            Self::OriginalPlus => "オリメン+α".to_string(),
            Self::Partial => format!("オリメン {present}/{total}"),
            Self::Cover => "オリメン不在".to_string(),
        }
    }
}

/// 公演の出演者全員が歌う行か。
/// `show_cast` が 2 人以上あって、歌唱者の集合とちょうど一致するときだけ。
pub fn is_full_cast(cast: &BTreeSet<&str>, performers: &BTreeSet<&str>) -> bool {
    cast.len() >= 2 && cast == performers
}

/// 行に付ける札。付けない場合が 3 つある:
/// - 原唱者か歌唱者が分からない (判定できない)
/// - 原唱者 1 人のオリメン一致 — ソロ曲を本人が歌うのは当たり前で、札にすると全行に付く
/// - 出演者全員で歌う行 (`full_cast`) の「一部」— 新メンバーの追加や一部欠席で部分一致に
///   なるだけで、カバーではない (全員曲の通常形)
pub fn lineup_note(
    original: &BTreeSet<&str>,
    performers: &BTreeSet<&str>,
    full_cast: bool,
) -> Option<Lineup> {
    match Lineup::classify(original, performers)? {
        Lineup::Original if original.len() < 2 => None,
        Lineup::Partial if full_cast => None,
        lineup => Some(lineup),
    }
}

/// 原唱者のうち、この行で歌っていない人 (`original` の並び順のまま)。
pub fn missing_originals<'a>(original: &[&'a str], performers: &BTreeSet<&str>) -> Vec<&'a str> {
    original
        .iter()
        .copied()
        .filter(|id| !performers.contains(id))
        .collect()
}

/// 歌っていない原唱者のうち、**その公演には出ている人**。名前で示す価値があるのはこちら
/// (「いたのに歌わなかった」は出演者一覧からは読めない)。公演にいない人は出演者一覧を
/// 見れば分かるので、数 (`4/5`) だけに任せる — 全体曲でその公演にいない 30 人を並べても
/// 「その公演にいない人」の羅列にしかならない。
pub fn absent_in_cast<'a>(missing: &[&'a str], cast: &BTreeSet<&str>) -> Vec<&'a str> {
    missing
        .iter()
        .copied()
        .filter(|id| cast.contains(id))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn set(ids: &[&'static str]) -> BTreeSet<&'static str> {
        ids.iter().copied().collect()
    }

    #[test]
    fn classifies_by_set_relation() {
        let original = set(&["a", "b"]);
        assert_eq!(Lineup::classify(&original, &set(&["a", "b"])), Some(Lineup::Original));
        assert_eq!(Lineup::classify(&original, &set(&["a", "b", "c"])), Some(Lineup::OriginalPlus));
        assert_eq!(Lineup::classify(&original, &set(&["a", "c"])), Some(Lineup::Partial));
        assert_eq!(Lineup::classify(&original, &set(&["c"])), Some(Lineup::Cover));
    }

    #[test]
    fn unknown_when_either_side_is_missing() {
        assert_eq!(Lineup::classify(&set(&[]), &set(&["a"])), None);
        assert_eq!(Lineup::classify(&set(&["a"]), &set(&[])), None);
    }

    #[test]
    fn full_cast_needs_two_or_more_and_exact_match() {
        assert!(is_full_cast(&set(&["a", "b"]), &set(&["a", "b"])));
        assert!(!is_full_cast(&set(&["a"]), &set(&["a"])), "1 人では「全員」と言わない");
        assert!(!is_full_cast(&set(&["a", "b", "c"]), &set(&["a", "b"])));
        assert!(!is_full_cast(&set(&[]), &set(&["a", "b"])));
    }

    #[test]
    fn solo_original_match_is_not_worth_a_note() {
        assert_eq!(lineup_note(&set(&["a"]), &set(&["a"]), false), None);
        assert_eq!(lineup_note(&set(&["a", "b"]), &set(&["a", "b"]), false), Some(Lineup::Original));
    }

    #[test]
    fn partial_is_suppressed_when_the_whole_cast_sings() {
        let original = set(&["a", "b", "z"]);
        assert_eq!(lineup_note(&original, &set(&["a", "b", "c"]), true), None);
        // 全員でなければ一部のまま。
        assert_eq!(lineup_note(&original, &set(&["a", "c"]), false), Some(Lineup::Partial));
        // 全員曲でも「不在」(原唱者ゼロ) は隠さない。
        assert_eq!(lineup_note(&set(&["z"]), &set(&["a", "b", "c"]), true), Some(Lineup::Cover));
    }

    #[test]
    fn missing_originals_keep_original_order() {
        assert_eq!(missing_originals(&["c", "a", "b"], &set(&["a"])), vec!["c", "b"]);
        assert!(missing_originals(&["a"], &set(&["a", "b"])).is_empty());
    }

    #[test]
    fn only_absentees_who_were_at_the_show_are_named() {
        // c は公演に出ているのに歌っていない → 名前で示す。b は公演にいない → 数だけ。
        let cast = set(&["a", "c", "x"]);
        assert_eq!(absent_in_cast(&["b", "c"], &cast), vec!["c"]);
        assert!(absent_in_cast(&["b"], &cast).is_empty());
    }

    #[test]
    fn partial_label_carries_the_ratio() {
        assert_eq!(Lineup::Partial.label(4, 5), "オリメン 4/5");
        assert_eq!(Lineup::Original.label(5, 5), "オリメン");
        assert_eq!(Lineup::Cover.label(0, 5), "オリメン不在");
    }

    #[test]
    fn kind_serializes_as_camel_case() {
        assert_eq!(serde_json::to_string(&Lineup::OriginalPlus).unwrap(), "\"originalPlus\"");
    }
}
