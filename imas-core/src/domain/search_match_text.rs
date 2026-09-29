//! 検索で絞った曲の行に、「なぜ出ているか」を添える文 (Q-08n / R-B-03)。
//!
//! 両 OS に写経されていて、割り方と人数の数え方が違っていた
//! (iOS `SongRowView.performerText` / `matchedCreatorText`、Android `SongRow.kt` の
//! `matchedPerformerText` / `performerNames` / `matchedCreatorText`)。
//!
//! - 連名は読点 (`、` `，` `,`) でだけ割る。**中黒 `・` では割らない** — `高垣楓・川島瑞樹` の
//!   区切りでもあるが、`キャシー・グラハム` のように名前の一部でもあり、割ると人名が半分になる。
//! - 「ほか N 人」の N は**表記に並んでいる人数** (当たった 1 人を除く)。
//! - 当たったかどうかは検索と同じ照合 ([`FoldedNeedle`]) で決める (一覧に載せる判定と食い違わない)。

use crate::domain::text_search_index::FoldedNeedle;

/// 連名表記から歌唱者名を取り出す。「ユニット名（A、B、C）」は全角括弧の中が歌唱者
/// (ユニット名側にも半角括弧が入ることがあるので、全角の最後の開きから後ろを見る)。
pub fn performer_names(label: &str) -> Vec<String> {
    let body = match label.rfind('（') {
        Some(open) => {
            let inner = &label[open + '（'.len_utf8()..];
            inner.strip_suffix('）').unwrap_or(inner)
        }
        None => label,
    };
    body.split(['、', '，', ','])
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .map(str::to_string)
        .collect()
}

/// 歌唱者で絞っているときの行の文: 当たった 1 人を先頭に出し、表記にほかの人がいれば
/// `ほか N 人` を添える (`田中琴葉 ほか51人`)。
///
/// `labels` は歌唱者の表記を優先順に (ユニット名 → 歌唱者表記 → 歌唱アイドル名の連結)。
/// どの表記にも当たらなければ `None` (行はふだんの表記のまま)。
pub fn performer_match_text(labels: &[String], needle: &str) -> Option<String> {
    performer_match_text_folded(labels, &fold_query(needle)?)
}

fn performer_match_text_folded(labels: &[String], needle: &FoldedNeedle) -> Option<String> {
    labels.iter().find_map(|label| {
        let names = performer_names(label);
        let matched = names.iter().find(|name| needle.matches(name))?;
        let others = names.len() - 1;
        Some(if others > 0 { format!("{matched} ほか{others}人") } else { matched.clone() })
    })
}

/// 作家で絞っているときの行の文: 当たった役割と名前 (`作詞 A / 作曲 B`)。並びは 作詞 → 作曲 → 編曲。
pub fn creator_match_text(
    lyricist: Option<&str>,
    composer: Option<&str>,
    arranger: Option<&str>,
    needle: &str,
) -> Option<String> {
    creator_match_text_folded(lyricist, composer, arranger, &fold_query(needle)?)
}

fn creator_match_text_folded(
    lyricist: Option<&str>,
    composer: Option<&str>,
    arranger: Option<&str>,
    needle: &FoldedNeedle,
) -> Option<String> {
    let parts: Vec<String> = [("作詞", lyricist), ("作曲", composer), ("編曲", arranger)]
        .into_iter()
        .filter_map(|(role, name)| name.filter(|n| needle.matches(n)).map(|n| format!("{role} {n}")))
        .collect();
    (!parts.is_empty()).then(|| parts.join(" / "))
}

/// どの欄で絞っているか。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SearchMatchScope {
    /// 歌唱者。
    Performer,
    /// 作詞・作曲・編曲。
    Creator,
}

/// 行 1 つぶんの材料。
#[derive(uniffi::Record, Clone, Debug, Default, PartialEq, Eq)]
pub struct SearchMatchRowInput {
    /// 歌唱者の表記を優先順に (ユニット名 → 歌唱者表記 → 歌唱アイドル名の連結)。
    pub performer_labels: Vec<String>,
    pub lyricist: Option<String>,
    pub composer: Option<String>,
    pub arranger: Option<String>,
}

/// 検索語を 1 回だけ畳む。空 (空白だけ) なら `None` = 文を添えない。
fn fold_query(needle: &str) -> Option<FoldedNeedle> {
    Some(FoldedNeedle::new(needle.trim())).filter(|n| !n.is_empty())
}

/// 画面に出ている行ぶんを 1 回で (行ごとに FFI を呼ばない)。入力と同じ並び・同じ数。
/// 検索語は最初に 1 回だけ畳む (行ごとに畳み直さない)。
pub fn search_match_texts(rows: &[SearchMatchRowInput], scope: SearchMatchScope, needle: &str) -> Vec<Option<String>> {
    let Some(needle) = fold_query(needle) else { return vec![None; rows.len()] };
    rows.iter()
        .map(|row| match scope {
            SearchMatchScope::Performer => performer_match_text_folded(&row.performer_labels, &needle),
            SearchMatchScope::Creator => creator_match_text_folded(
                row.lyricist.as_deref(),
                row.composer.as_deref(),
                row.arranger.as_deref(),
                &needle,
            ),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(values: &[&str]) -> Vec<String> {
        values.iter().map(|v| v.to_string()).collect()
    }

    #[test]
    fn names_come_from_the_last_full_width_bracket_and_are_split_only_on_commas() {
        assert_eq!(
            performer_names("315 STARS(フィジカルVer.)（天ヶ瀬冬馬、伊集院北斗，御手洲周介）"),
            s(&["天ヶ瀬冬馬", "伊集院北斗", "御手洲周介"])
        );
        assert_eq!(performer_names("キャシー・グラハム"), s(&["キャシー・グラハム"]), "中黒では割らない");
        assert_eq!(performer_names("天海春香、 春日未来 ,"), s(&["天海春香", "春日未来"]));
    }

    #[test]
    fn performer_text_leads_with_the_hit_and_counts_the_notated_names() {
        let labels = s(&["", "765 MILLION ALLSTARS（田中琴葉、春日未来、最上静香）"]);
        assert_eq!(performer_match_text(&labels, " 琴葉 ").as_deref(), Some("田中琴葉 ほか2人"));
        assert_eq!(performer_match_text(&s(&["田中琴葉"]), "田中").as_deref(), Some("田中琴葉"));
        assert_eq!(performer_match_text(&labels, "存在しない"), None);
        assert_eq!(performer_match_text(&labels, "  "), None);
        // 中黒で繋いだ表記は 1 人ぶんとして出す (割らない)。
        assert_eq!(performer_match_text(&s(&["高垣楓・川島瑞樹"]), "川島").as_deref(), Some("高垣楓・川島瑞樹"));
    }

    #[test]
    fn creator_text_lists_every_matching_role_in_order() {
        assert_eq!(
            creator_match_text(Some("佐藤貴文"), Some("佐藤貴文"), Some("別の人"), "佐藤").as_deref(),
            Some("作詞 佐藤貴文 / 作曲 佐藤貴文")
        );
        assert_eq!(creator_match_text(None, Some("A"), None, "b"), None);
        assert_eq!(creator_match_text(Some("A"), None, None, ""), None);
    }

    #[test]
    fn batch_keeps_the_row_order() {
        let rows = vec![
            SearchMatchRowInput { performer_labels: s(&["A、B"]), ..Default::default() },
            SearchMatchRowInput::default(),
            SearchMatchRowInput { composer: Some("Bさん".into()), ..Default::default() },
        ];
        assert_eq!(
            search_match_texts(&rows, SearchMatchScope::Performer, "b"),
            vec![Some("B ほか1人".to_string()), None, None]
        );
        assert_eq!(
            search_match_texts(&rows, SearchMatchScope::Creator, "b"),
            vec![None, None, Some("作曲 Bさん".to_string())]
        );
    }
}
