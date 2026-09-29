//! セトリ 1 行の読み方 — 区切り (`setlist_items.section`) と曲順。
//!
//! 「アンコール」の綴りは入力者ごとに揺れる (`encore` / `ENCORE` / `アンコール`)。
//! 画面に 3 通りの見出しが並ばないよう、ここで 1 つに畳む。空文字は「区切り無し」。
//! それ以外の区切り (`LL` / `CROSS` / `アイマス×μ\'s`) はそのライブ固有の言葉なので
//! そのまま出す。
//!
//! 曲順 ([`track_number`]) を同居させているのは、どちらも「セトリの 1 行を読むとき、
//! 生の列をそのまま出してはいけない」という同じ種類の知識だから。

/// アンコールの見出し。綴りが違っても全部これになる。
pub const ENCORE_LABEL: &str = "アンコール";

/// 区切り無しの塊にアプリが付ける見出し (Web は見出しを出さない)。
pub const MAIN_SECTION_HEADING: &str = "本編";

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

/// セトリ 1 行の区切り。アプリは `starts` の行の前に `heading` の見出しを置くだけにする
/// (綴りの畳み方も塊の切り方も画面に持たせない)。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RowSection {
    /// 見出しの文言。区切り無しは [`MAIN_SECTION_HEADING`]。
    pub heading: String,
    /// この行から新しい塊が始まるか (先頭行は必ず true)。
    pub starts: bool,
}

/// 並び順の `setlist_items.section` から、各行の区切り。塊の切り方は
/// [`group_consecutive`] と同じで、畳んだ後の見出しが隣と同じなら 1 つの塊にする
/// (`encore` と `ENCORE`、`NULL` と空文字は同じ塊)。
pub fn row_sections<'a>(raws: impl IntoIterator<Item = Option<&'a str>>) -> Vec<RowSection> {
    let mut previous: Option<Option<String>> = None;
    raws.into_iter()
        .map(|raw| {
            let label = section_label(raw);
            let starts = previous.as_ref() != Some(&label);
            let heading = label.clone().unwrap_or_else(|| MAIN_SECTION_HEADING.to_string());
            previous = Some(label);
            RowSection { heading, starts }
        })
        .collect()
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

// ---------------------------------------------------------------------------
// 曲順
// ---------------------------------------------------------------------------

/// 公演のセトリ行を「公演内の曲順 (1 始まり)」つきで並べる。
///
/// **`setlist_items.position` をそのまま曲順として出してはいけない。** あれは公演を
/// またいだ通し番号で、実データでは 4〜5 桁になる (「お願い！シンデレラ」のある披露は
/// `position: 12852`)。そのまま読むと「12852 曲目」という文になる。
///
/// 公演内の並びは `setlist_items_by_show` が position 昇順に前計算してあるので、
/// その添字がそのまま曲順になる。**この 1 段を呼ぶ側に数えさせない** —
/// LLM 向けツールの 2 ファイルがそれぞれ `enumerate()` を書いていて、片方だけ
/// 生の position を出していた時期がある。
pub fn numbered_setlist(
    snap: &crate::domain::snapshot::Snapshot,
    show: u32,
) -> impl Iterator<Item = (usize, u32)> + '_ {
    snap.setlist_items_by_show[show as usize]
        .iter()
        .enumerate()
        .map(|(rank, &item)| (rank + 1, item))
}

/// その披露が、その公演の何曲目か (1 始まり)。
///
/// 披露 (`setlist_items` の添字) の側から曲順を知りたいとき用。公演の全行を並べたい
/// ときは [`numbered_setlist`] を使う (こちらは 1 行ぶん探すので線形に走る)。
pub fn track_number(snap: &crate::domain::snapshot::Snapshot, item: u32) -> usize {
    let show = snap.setlist_items[item as usize].show;
    numbered_setlist(snap, show).find(|&(_, i)| i == item).map_or(0, |(rank, _)| rank)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

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

    #[test]
    fn row_sections_fold_spellings_and_mark_where_a_block_starts() {
        let raws = [None, Some(""), Some("encore"), Some("ENCORE"), Some("LL"), None, Some("LL")];
        let sections = row_sections(raws);
        let headings: Vec<&str> = sections.iter().map(|s| s.heading.as_str()).collect();
        let starts: Vec<bool> = sections.iter().map(|s| s.starts).collect();
        assert_eq!(headings, ["本編", "本編", "アンコール", "アンコール", "LL", "本編", "LL"]);
        assert_eq!(starts, [true, false, true, false, true, true, true]);
        assert!(row_sections(Vec::<Option<&str>>::new()).is_empty());
    }

    #[test]
    fn row_sections_split_exactly_where_group_consecutive_does() {
        let raws = [Some("encore"), None, Some(" "), Some("CROSS"), Some("CROSS"), Some("アンコール")];
        let blocks = group_consecutive(raws.iter().map(|&raw| (section_label(raw), ())));
        let starts = row_sections(raws).iter().filter(|s| s.starts).count();
        assert_eq!(starts, blocks.len());
    }

    // ---- 曲順 (実データで固定する) ----

    #[test]
    fn 曲順は公演内で_1_始まりの連番になる() {
        let snap = bundle_snapshot();
        let mut checked = 0;
        for show in 0..snap.shows.len() as u32 {
            let numbers: Vec<usize> = numbered_setlist(snap, show).map(|(n, _)| n).collect();
            if numbers.is_empty() {
                continue;
            }
            let expected: Vec<usize> = (1..=numbers.len()).collect();
            assert_eq!(numbers, expected, "{} の曲順が連番でない", snap.shows[show as usize].id);
            checked += 1;
        }
        assert!(checked > 1000, "セトリのある公演が少なすぎる: {checked}");
    }

    #[test]
    fn 曲順は生の_position_とは別物() {
        let snap = bundle_snapshot();
        // 生の position は公演をまたぐ通し番号なので、公演内で 1 から始まらない。
        // ここが崩れたら (position が公演内連番に変わったら) この層は要らなくなる。
        let raw_starts_at_one = (0..snap.shows.len() as u32)
            .filter_map(|show| snap.setlist_items_by_show[show as usize].first().copied())
            .all(|item| snap.setlist_items[item as usize].position == 1);
        assert!(!raw_starts_at_one, "生の position が公演内連番になっている");

        // それでも曲順は必ず 1 から始まる。通し番号が 1 でない公演で確かめる
        // (いちばん古い 1 公演だけは通し番号も 1 から始まるので、そこは避ける)。
        let show = (0..snap.shows.len() as u32)
            .find(|&s| {
                snap.setlist_items_by_show[s as usize]
                    .first()
                    .is_some_and(|&i| snap.setlist_items[i as usize].position != 1)
            })
            .expect("通し番号が 1 で始まらない公演がある");
        let (first_rank, first_item) = numbered_setlist(snap, show).next().unwrap();
        assert_eq!(first_rank, 1);
        assert!(
            snap.setlist_items[first_item as usize].position > 1,
            "通し番号をそのまま曲順にしている"
        );
    }
}
