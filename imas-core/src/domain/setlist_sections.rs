//! セトリの区切り (`setlist_items.section`) の解釈。
//!
//! 「アンコール」の綴りは入力者ごとに揺れる (`encore` / `ENCORE` / `アンコール`)。
//! 画面に 3 通りの見出しが並ばないよう、ここで 1 つに畳む。空文字は「区切り無し」。
//! それ以外の区切り (`LL` / `CROSS` / `アイマス×μ's`) はそのライブ固有の言葉なので
//! そのまま出す。

/// アンコールの見出し。綴りが違っても全部これになる。
pub const ENCORE_LABEL: &str = "アンコール";

/// 区切りの見出し。`None` = 区切り無し (本編)。
pub fn section_label(raw: Option<&str>) -> Option<String> {
    let label = raw?.trim();
    if label.is_empty() {
        return None;
    }
    if label.eq_ignore_ascii_case("encore") {
        return Some(ENCORE_LABEL.to_string());
    }
    Some(label.to_string())
}

/// 隣り合う同じ区切りをひとまとめにする。並びは保つ。
///
/// 同じ見出しが離れて 2 回出るライブ (合同ライブで `LL` と本編が交互に来る) は
/// そのまま 2 つの塊になる。並べ替えて寄せると披露順が壊れる。
pub fn group_consecutive<K: PartialEq, T>(
    items: impl IntoIterator<Item = (K, T)>,
) -> Vec<(K, Vec<T>)> {
    let mut groups: Vec<(K, Vec<T>)> = Vec::new();
    for (key, item) in items {
        match groups.last_mut() {
            Some((last, rows)) if *last == key => rows.push(item),
            _ => groups.push((key, vec![item])),
        }
    }
    groups
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encore_spellings_collapse_to_one_label() {
        for raw in ["encore", "ENCORE", "Encore", "アンコール", " encore "] {
            assert_eq!(section_label(Some(raw)).as_deref(), Some(ENCORE_LABEL), "{raw:?}");
        }
    }

    #[test]
    fn blank_means_no_section() {
        assert_eq!(section_label(None), None);
        assert_eq!(section_label(Some("")), None);
        assert_eq!(section_label(Some("   ")), None);
    }

    #[test]
    fn other_labels_pass_through_trimmed() {
        assert_eq!(section_label(Some(" LL ")).as_deref(), Some("LL"));
        assert_eq!(section_label(Some("アイマス×μ's")).as_deref(), Some("アイマス×μ's"));
        // 「ダブルアンコール」は別物なので畳まない。
        assert_eq!(section_label(Some("ダブルアンコール")).as_deref(), Some("ダブルアンコール"));
    }

    #[test]
    fn consecutive_rows_share_a_group_and_gaps_split_them() {
        let rows = [(None, 1), (None, 2), (Some("LL"), 3), (None, 4), (Some("LL"), 5), (Some("LL"), 6)];
        assert_eq!(
            group_consecutive(rows),
            vec![
                (None, vec![1, 2]),
                (Some("LL"), vec![3]),
                (None, vec![4]),
                (Some("LL"), vec![5, 6]),
            ]
        );
        assert!(group_consecutive(Vec::<(Option<&str>, i32)>::new()).is_empty());
    }
}
