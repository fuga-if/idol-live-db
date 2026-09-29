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
/// 「不参加」だけだと「そのライブに出ていない」と読まれる (ファン用語の不参加は欠席)。
/// ここに並ぶのは **出演しているのにこの曲は歌っていない** 原唱者なので、曲を主語にする。
pub const MISSING_LABEL: &str = "この曲は不参加";

/// 原唱者との関係。JSON にはそのまま camelCase の名前で出る (`partial` 等。CSS の見分け用)。
/// アプリには FFI (`inbound::event_detail_queries::setlist_lineup`) で同じ enum が渡る。
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum, serde::Serialize, serde::Deserialize)]
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

/// 1 行ぶんの答え。札の文言と「いたのに歌わなかった人」を、Web とアプリが同じ形で受け取る。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LineupSummary<'a> {
    pub lineup: Lineup,
    /// 原唱者のうち歌っている人数 / 原唱者の人数。
    pub present: usize,
    pub total: usize,
    /// 歌っていない原唱者のうち、その公演には出ている人 (原唱者の並び順)。
    pub absent_in_cast: Vec<&'a str>,
}

impl LineupSummary<'_> {
    pub fn label(&self) -> String {
        self.lineup.label(self.present, self.total)
    }

    /// アプリへ渡す形 (Web は Ref に解決した `LineupNote` を別に組む)。
    pub fn note(&self) -> SetlistLineupNote {
        SetlistLineupNote {
            kind: self.lineup,
            label: self.label(),
            absent_in_cast_ids: self.absent_in_cast.iter().map(|id| id.to_string()).collect(),
            missing_label: MISSING_LABEL.to_string(),
        }
    }
}

/// セトリ 1 行の歌唱者と原唱者 (オリメン) の関係。Web の公演ページと同じ規則・同じ文言。
///
/// 札の見出し (`オリメン 4/5`) と、歌っていない原唱者のうち**その公演には出ている人**
/// (「いたのに歌わなかった」は出演者一覧からは読めない。公演にいない人は数に任せる)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistLineupNote {
    pub kind: Lineup,
    /// `オリメン` / `オリメン+α` / `オリメン 4/5` / `オリメン不在`。
    pub label: String,
    /// 原唱者の並び順の idol_id。空なら名前の行は出さない。
    pub absent_in_cast_ids: Vec<String>,
    /// `absent_in_cast_ids` の前に置く言葉 ([`MISSING_LABEL`])。
    pub missing_label: String,
}

/// 札を付ける行なら、その 1 行ぶんの答え。`full_cast` は [`is_full_cast`] の結果
/// (呼び出し側が「全員」の札のために既に求めているので、ここで比べ直さない)。
pub fn summarize<'a>(
    original: &[&'a str],
    performers: &BTreeSet<&str>,
    cast: &BTreeSet<&str>,
    full_cast: bool,
) -> Option<LineupSummary<'a>> {
    let original_set: BTreeSet<&str> = original.iter().copied().collect();
    let lineup = lineup_note(&original_set, performers, full_cast)?;
    let missing = missing_originals(original, performers);
    Some(LineupSummary {
        lineup,
        present: original.len() - missing.len(),
        total: original.len(),
        absent_in_cast: absent_in_cast(&missing, cast),
    })
}

/// 1 行ぶんの「全員」と「オリメン」の答え。
///
/// **アプリ (セトリの行の添え物) と Web (公演ページ) はどちらもこの関数を通す。** 別々に組むと
/// 「全員」を見る集合がずれて、片方にだけ「オリメン n/m」が出たり、「全員」のチップと
/// 部分一致の札が同時に出たりする (2026-09 に同梱 DB でそれぞれ 61 行・3 行あった)。
///
/// `presence` は公演に「いた」人 = 登録した出演者 ∪ 歌唱メンバー
/// ([`crate::domain::event_detail_queries::show_presence`])。「全員で歌ったか」も
/// 「公演には出ているのに歌っていないか」も、同じこの集合で見る。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RowLineup<'a> {
    /// 出演者全員で歌う行 (`全員` の札)。
    pub is_full_cast: bool,
    /// オリメンの札。付けない行は `None` ([`summarize`])。
    pub summary: Option<LineupSummary<'a>>,
}

pub fn row_lineup<'a>(
    original: &[&'a str],
    performers: &BTreeSet<&str>,
    presence: &BTreeSet<&str>,
) -> RowLineup<'a> {
    let is_full_cast = is_full_cast(presence, performers);
    RowLineup { is_full_cast, summary: summarize(original, performers, presence, is_full_cast) }
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
    fn summary_has_the_ratio_and_only_in_cast_absentees() {
        let performers = set(&["a", "x"]);
        let cast = set(&["a", "c", "x"]);
        let summary = summarize(&["a", "b", "c"], &performers, &cast, false).unwrap();
        assert_eq!(summary.lineup, Lineup::Partial);
        assert_eq!((summary.present, summary.total), (1, 3));
        assert_eq!(summary.absent_in_cast, vec!["c"]);
        assert_eq!(summary.label(), "オリメン 1/3");
        // 札を付けない行は答えも無い。
        assert_eq!(summarize(&["a"], &set(&["a"]), &cast, false), None);
    }

    /// 「全員」の判定と札が同じ集合を見るので、全員の行に部分一致の札は付かない。
    #[test]
    fn row_lineup_sees_full_cast_and_absentees_through_the_same_presence() {
        // 公演にいたのは a, b, c (b は登録漏れでも歌っていれば presence に入る)。
        let presence = set(&["a", "b", "c"]);
        let everyone = row_lineup(&["a", "z"], &set(&["a", "b", "c"]), &presence);
        assert!(everyone.is_full_cast);
        assert_eq!(everyone.summary, None, "全員曲の部分一致は札にしない");

        let some = row_lineup(&["a", "c"], &set(&["a", "b"]), &presence);
        assert!(!some.is_full_cast);
        let summary = some.summary.expect("一部の札");
        assert_eq!(summary.label(), "オリメン 1/2");
        assert_eq!(summary.absent_in_cast, vec!["c"], "公演にいて歌わなかった人");
    }
}
