//! 「いつぶりの披露か」— セトリ 1 行に添える、その曲の希少さ。
//!
//! ファンが一番ざわつくのは「10 年ぶり」「初披露」で、それは曲の属性ではなく
//! **その披露の属性**。同じ曲でも 2016 年の公演では「2 年ぶり」、2026 年の公演では
//! 「3 年 10 か月ぶり」になる。
//!
//! # その公演時点で数える (これが肝)
//!
//! 「今から数えていちばん新しい披露」を出すと、過去のセトリを開いたときに嘘になる。
//! 2016 年の公演を開いて「2022 年にもやりました」と出てはいけない。ここが扱うのは
//! **その披露より前の履歴だけ**で、[`performance_gap`] は必ずその行の時点から見る。
//!
//! # 絞れる余地
//!
//! [`performance_gap_filtered`] は「数に入れる披露」を述語で受ける。
//! 「オケマスを除けば 10 年ぶり」のような軸 (`events.event_type` で絞る) を
//! 足すときは、この述語に条件を渡すだけで通算回数も間隔も一緒に付いてくる。
//! 絞ったら通算回数も絞った世界のものになる — 片方だけ元の世界の数を出すと、
//! 「3 回目なのに初披露」のような行ができる。

use crate::domain::event_detail_queries::is_screening;
use crate::domain::snapshot::Snapshot;
use crate::domain::song_detail_queries::performance_ordinal_label;
use std::collections::HashSet;

/// 行に出すほど珍しいと見なす間隔 (か月)。
///
/// 実データ (13,312 披露) の内訳は「6 か月未満 55% / 6〜11 か月 12% / 1 年以上 18% /
/// 初披露 15%」。6 か月で線を引くと半分近い行に札が付いて、ただの賑やかしになる。
/// 1 年で引くと、札が付くのは 1/3 (うち半分は初披露) で、目に留まる。
pub const NOTABLE_GAP_MONTHS: u32 = 12;

/// その披露の「何回目か」と「いつぶりか」。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PerformanceGap {
    /// 通算何回目か (1 = 初披露)。数える対象は [`performance_gap_filtered`] の述語次第。
    pub ordinal: u32,
    /// `初披露` / `4 回目`。
    pub ordinal_label: String,
    pub is_first: bool,
    /// **その披露の直前**の披露の日 (`YYYY-MM-DD`)。初披露なら `None`。
    pub previous_date: Option<String>,
    /// 前回からの間隔 (か月)。初披露なら `None`。同日 (昼夜公演) は `Some(0)`。
    pub months_since: Option<u32>,
    /// 行に出す札 (`3 年 10 か月ぶり`)。[`NOTABLE_GAP_MONTHS`] に届かない間隔と
    /// 初披露では `None` (初披露は `ordinal_label` が言う)。
    pub since_label: Option<String>,
}

/// `YYYY-MM-DD` 2 つの間の満か月。日付として読めない入力は `None`。
///
/// 「満」で数える — 2022-11-13 → 2026-09-19 は 46 か月 (3 年 10 か月) で、
/// 日が 13 → 19 と進んでいるので切り下げない。2022-11-13 → 2026-09-05 なら 45 か月。
pub fn months_between(from: &str, to: &str) -> Option<u32> {
    let (fy, fm, fd) = parse_ymd(from)?;
    let (ty, tm, td) = parse_ymd(to)?;
    let months = (ty - fy) * 12 + (tm - fm) - i32::from(td < fd);
    u32::try_from(months).ok()
}

fn parse_ymd(date: &str) -> Option<(i32, i32, i32)> {
    let mut parts = date.split('-');
    let y = parts.next()?.parse().ok()?;
    let m = parts.next()?.parse().ok()?;
    let d = parts.next()?.parse().ok()?;
    parts.next().is_none().then_some((y, m, d))
}

/// 間隔の言い回し。**言い方はここ 1 箇所**で、画面ごとに「ぶり」を組み立てない。
///
/// - 12 か月以上 … `1 年ぶり` / `3 年 10 か月ぶり`
/// - 6 か月 … `半年ぶり` (日本語でこの長さだけ数えずに言う)
/// - 1〜11 か月 … `7 か月ぶり`
/// - 0 か月 (同月・同日) … `None` — 「0 か月ぶり」は言わない
pub fn interval_label(months: u32) -> Option<String> {
    match months {
        0 => None,
        6 => Some("半年ぶり".to_string()),
        1..=11 => Some(format!("{months} か月ぶり")),
        _ => Some(match (months / 12, months % 12) {
            (years, 0) => format!("{years} 年ぶり"),
            (years, rest) => format!("{years} 年 {rest} か月ぶり"),
        }),
    }
}

/// 行に出す札。[`NOTABLE_GAP_MONTHS`] に届かない間隔では出さない。
pub fn notable_interval_label(months: u32) -> Option<String> {
    (months >= NOTABLE_GAP_MONTHS).then(|| interval_label(months)).flatten()
}

/// その披露 (`setlist_items` の添字) の、その時点から見た回数と間隔。
pub fn performance_gap(snap: &Snapshot, item: u32) -> PerformanceGap {
    performance_gap_filtered(snap, item, |_, _| true)
}

/// 数に入れる披露を選べる版。`include` が `false` を返した披露は、回数にも
/// 間隔にも入らない (自分自身は常に入る — 自分を外したら答えが無い)。
pub fn performance_gap_filtered(
    snap: &Snapshot,
    item: u32,
    include: impl Fn(&Snapshot, u32) -> bool,
) -> PerformanceGap {
    let song = snap.setlist_items[item as usize].song;
    let mut history: Vec<u32> = snap.setlist_items_by_song[song as usize]
        .iter()
        .copied()
        .filter(|&i| i == item || include(snap, i))
        .collect();
    // 保存されている並びは履歴表示用 (日付 DESC・同日は昇順)。数えるには古い順に直す。
    history.sort_by_key(|&i| chronological_key(snap, i));

    let position = history.iter().position(|&i| i == item).unwrap_or(0);
    let previous = position.checked_sub(1).map(|p| history[p]);
    let previous_date =
        previous.map(|i| snap.shows[snap.setlist_items[i as usize].show as usize].date.clone());
    let date = &snap.shows[snap.setlist_items[item as usize].show as usize].date;
    let months_since =
        previous_date.as_deref().map(|prev| months_between(prev, date).unwrap_or(0));
    let ordinal = position as u32 + 1;
    PerformanceGap {
        ordinal,
        ordinal_label: performance_ordinal_label(ordinal),
        is_first: ordinal == 1,
        previous_date,
        months_since,
        since_label: months_since.and_then(notable_interval_label),
    }
}

/// その行は披露か。上映会 (誰も歌わない公演) の行は披露でないので、回数も間隔も持たない
/// ([`crate::domain::event_detail_queries::is_screening`])。**披露でない行に
/// [`performance_gap`] を当てないこと** — 履歴に居ないので「初披露」に化ける。
pub fn is_performance(snap: &Snapshot, item: u32) -> bool {
    let show = &snap.shows[snap.setlist_items[item as usize].show as usize];
    !is_screening(show.performer_type.as_deref())
}

/// 原唱者 (オリメン) 1 人ぶんの、その曲を歌うのが何回目か。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OriginalSingerOrdinal {
    /// 表示用の短い名 ([`crate::domain::snapshot::Idol::short_name`])。
    pub name: String,
    /// この披露がその人にとって何回目か (1 = 初めて歌った)。その公演の時点から数える。
    pub ordinal: u32,
}

/// 原唱者のうち、この披露で歌った人の回数。
///
/// 曲の通算回数 ([`PerformanceGap::ordinal`]) は**誰が歌っても**増える
/// (他ブランドのカバー、別ユニットの歌唱)。「オリメンとしては何回目か」は
/// それとは別の問いなので、歌った原唱者ごとに数える。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct OriginalSingers {
    /// その曲の原唱者の人数 (この披露で歌ったかを問わない)。
    pub original_count: usize,
    /// この披露で歌った原唱者 (原唱者の並び順)。歌った原唱者がいなければ空。
    pub sung: Vec<OriginalSingerOrdinal>,
}

/// その披露 (`setlist_items` の添字) で歌った原唱者それぞれの、その時点での回数。
/// 数える世界は [`performance_gap`] と同じ (上映会は入らない・同日は公演順)。
pub fn original_singers(snap: &Snapshot, item: u32) -> OriginalSingers {
    let row = &snap.setlist_items[item as usize];
    let mut seen = HashSet::new();
    let originals: Vec<u32> = snap.artists_by_song[row.song as usize]
        .iter()
        .filter(|l| l.role == "original")
        .map(|l| l.idol)
        .filter(|&idol| seen.insert(idol))
        .collect();
    let performers = &snap.performers_by_item[item as usize];
    let key = chronological_key(snap, item);
    let history = &snap.setlist_items_by_song[row.song as usize];
    let sung = originals
        .iter()
        .filter(|idol| performers.contains(idol))
        .map(|&idol| OriginalSingerOrdinal {
            name: snap.idols[idol as usize].short_name().to_string(),
            ordinal: history
                .iter()
                .filter(|&&i| {
                    chronological_key(snap, i) <= key
                        && snap.performers_by_item[i as usize].contains(&idol)
                })
                .count() as u32,
        })
        .collect();
    OriginalSingers { original_count: originals.len(), sung }
}

/// 古い順に並べるキー。同じ日の昼夜は `shows.sort_order` → セトリ内の `position` の順。
fn chronological_key(snap: &Snapshot, item: u32) -> (&str, i64, i64, u32) {
    let row = &snap.setlist_items[item as usize];
    let show = &snap.shows[row.show as usize];
    (show.date.as_str(), show.sort_order, row.position, item)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    // ---- 満か月 ----

    /// 依頼の実例。14thLIVE の『初恋 〜一章 片想いの桜〜』の前回は 2022 年の
    /// オーケストラ公演で、そこからちょうど 3 年 10 か月。
    #[test]
    fn counts_whole_months() {
        assert_eq!(months_between("2022-11-13", "2026-09-19"), Some(46));
        // 日が届かない月は切り下げる。
        assert_eq!(months_between("2022-11-13", "2026-09-05"), Some(45));
        assert_eq!(months_between("2026-09-19", "2026-09-19"), Some(0));
        assert_eq!(months_between("2014-10-05", "2016-04-30"), Some(18));
    }

    /// 日付として読めないもの (部分日付・空) は捏造しない。
    #[test]
    fn unparsable_dates_have_no_distance() {
        assert_eq!(months_between("2024", "2026-09-19"), None);
        assert_eq!(months_between("", "2026-09-19"), None);
        assert_eq!(months_between("2024-08", "2026-09-19"), None);
        // 逆順 (未来 → 過去) は負なので答えない。
        assert_eq!(months_between("2026-09-19", "2022-11-13"), None);
    }

    // ---- 言い回し ----

    #[test]
    fn spells_out_the_interval() {
        assert_eq!(interval_label(46).as_deref(), Some("3 年 10 か月ぶり"));
        assert_eq!(interval_label(12).as_deref(), Some("1 年ぶり"));
        assert_eq!(interval_label(120).as_deref(), Some("10 年ぶり"));
        assert_eq!(interval_label(6).as_deref(), Some("半年ぶり"));
        assert_eq!(interval_label(7).as_deref(), Some("7 か月ぶり"));
        assert_eq!(interval_label(1).as_deref(), Some("1 か月ぶり"));
        assert_eq!(interval_label(0), None, "「0 か月ぶり」とは言わない");
    }

    /// 行に出すのは 1 年から。半年ぶりまで札にすると、ライブの半分の行に札が付く。
    #[test]
    fn only_a_year_or_more_earns_a_badge() {
        assert_eq!(notable_interval_label(11), None);
        assert_eq!(notable_interval_label(12).as_deref(), Some("1 年ぶり"));
    }

    // ---- 実データ ----

    fn item_of(snap: &Snapshot, song_id: &str, date: &str) -> u32 {
        let si = snap.song_index_by_id[song_id];
        snap.setlist_items_by_song[si as usize]
            .iter()
            .copied()
            .find(|&i| snap.shows[snap.setlist_items[i as usize].show as usize].date == date)
            .unwrap_or_else(|| panic!("{song_id} の {date} の披露"))
    }

    /// **過去のセトリを開いても、その時点から数える。** これが崩れると
    /// 2016 年の公演に「2022 年以来」と出る。
    #[test]
    fn a_past_setlist_looks_only_at_its_own_past() {
        let snap = bundle_snapshot();
        let song = "765as_初恋_一章_片想いの桜";
        // 4 回の披露: 2014-10-05 / 2016-04-30 / 2022-11-13 / 2026-09-19。
        let first = performance_gap(snap, item_of(snap, song, "2014-10-05"));
        assert_eq!(first.ordinal, 1);
        assert!(first.is_first);
        assert_eq!(first.ordinal_label, "初披露");
        assert_eq!(first.previous_date, None);
        assert_eq!(first.since_label, None);

        let second = performance_gap(snap, item_of(snap, song, "2016-04-30"));
        assert_eq!(second.ordinal, 2);
        assert_eq!(second.previous_date.as_deref(), Some("2014-10-05"));
        assert_eq!(second.since_label.as_deref(), Some("1 年 6 か月ぶり"));

        let third = performance_gap(snap, item_of(snap, song, "2022-11-13"));
        assert_eq!(third.ordinal, 3);
        assert_eq!(third.previous_date.as_deref(), Some("2016-04-30"));
        assert_eq!(third.since_label.as_deref(), Some("6 年 6 か月ぶり"));

        let fourth = performance_gap(snap, item_of(snap, song, "2026-09-19"));
        assert_eq!(fourth.ordinal, 4);
        assert_eq!(fourth.ordinal_label, "4 回目");
        assert_eq!(fourth.previous_date.as_deref(), Some("2022-11-13"));
        assert_eq!(fourth.since_label.as_deref(), Some("3 年 10 か月ぶり"));
    }

    /// 回数はスナップショット構築時の `ordinal_by_item` と同じ答えになる
    /// (曲ページの「N 回目」とセトリの札が違う数を出さない)。
    #[test]
    fn ordinals_agree_with_the_snapshot() {
        let snap = bundle_snapshot();
        let mut checked = 0usize;
        for item in (0..snap.setlist_items.len() as u32).step_by(37) {
            assert_eq!(
                performance_gap(snap, item).ordinal,
                snap.ordinal_by_item[item as usize],
                "item {} の回数",
                snap.setlist_items[item as usize].id
            );
            checked += 1;
        }
        assert!(checked > 300, "標本が少なすぎる: {checked}");
    }

    /// 絞ると、回数も間隔も**絞った世界のもの**になる (「オケマスを除けば」の軸の足場)。
    #[test]
    fn a_filter_moves_the_count_and_the_interval_together() {
        let snap = bundle_snapshot();
        let song = "765as_初恋_一章_片想いの桜";
        let latest = item_of(snap, song, "2026-09-19");
        // 2022 年の 1 回を数に入れないと、前回は 2016 年・通算 3 回目になる。
        let gap = performance_gap_filtered(snap, latest, |s, i| {
            s.shows[s.setlist_items[i as usize].show as usize].date != "2022-11-13"
        });
        assert_eq!(gap.ordinal, 3);
        assert_eq!(gap.ordinal_label, "3 回目");
        assert_eq!(gap.previous_date.as_deref(), Some("2016-04-30"));
        assert_eq!(gap.since_label.as_deref(), Some("10 年 4 か月ぶり"));

        // 全部外しても自分だけは残る = 初披露。
        let alone = performance_gap_filtered(snap, latest, |_, _| false);
        assert_eq!(alone.ordinal, 1);
        assert!(alone.is_first);
    }

    /// **上映会 (MV 上映会) は披露に数えない。** 初星文化祭 後夜祭は MV を流しただけで、
    /// 数えると『Unhappy Light』が「7 回目」になっていた。セトリには並ぶ。
    #[test]
    fn a_screening_is_not_a_performance() {
        let snap = bundle_snapshot();
        let show = snap.show_index_by_id["sh_L1250"];
        let items = &snap.setlist_items_by_show[show as usize];
        assert!(!items.is_empty(), "上映会のセトリ自体は残る");
        for &item in items {
            assert!(!is_performance(snap, item));
            assert_eq!(snap.ordinal_by_item[item as usize], 0, "上映会の行は何回目も持たない");
            let song = snap.setlist_items[item as usize].song;
            let history = &snap.setlist_items_by_song[song as usize];
            assert!(!history.contains(&item), "曲の披露履歴に入らない");
            assert_eq!(snap.performance_counts[song as usize] as usize, history.len());
            // 残った披露は 1 から欠けずに数えられている。
            let mut ordinals: Vec<u32> =
                history.iter().map(|&i| snap.ordinal_by_item[i as usize]).collect();
            ordinals.sort_unstable();
            assert_eq!(ordinals, (1..=history.len() as u32).collect::<Vec<_>>());
            for &idol in &snap.performers_by_item[item as usize] {
                assert!(
                    !snap.performed_items_by_idol[idol as usize].contains(&item),
                    "アイドルの歌唱履歴にも入らない"
                );
            }
        }
    }

    /// 通算回数はカバーでも増えるが、オリメンの回数は本人が歌った披露だけで数える。
    /// 『ミラーボール・ラブ』は 2025 年の上水流宇宙のソロライブで通算 11 回目だが、
    /// そこにオリメンはいない。2021 年に比奈が歌ったのは比奈にとって 3 回目。
    #[test]
    fn originals_count_only_their_own_singing() {
        let snap = bundle_snapshot();
        let song = "cg_ミラーボールラブ";

        let cover = item_of(snap, song, "2025-09-12");
        assert_eq!(performance_gap(snap, cover).ordinal, 11);
        let singers = original_singers(snap, cover);
        assert_eq!(singers.original_count, 5);
        assert!(singers.sung.is_empty(), "オリメンが歌っていない行には何も言わない");

        let hina = original_singers(snap, item_of(snap, song, "2021-12-26"));
        assert_eq!(
            hina.sung,
            vec![OriginalSingerOrdinal { name: "比奈".to_string(), ordinal: 3 }]
        );
    }

    /// 同じ日の昼夜公演は「0 か月」= 札を出さない (「同日ぶり」とは言わない)。
    #[test]
    fn same_day_shows_get_no_badge() {
        let snap = bundle_snapshot();
        let same_day = (0..snap.setlist_items.len() as u32)
            .map(|i| (i, performance_gap(snap, i)))
            .find(|(i, g)| {
                g.previous_date.as_deref()
                    == Some(&snap.shows[snap.setlist_items[*i as usize].show as usize].date)
            });
        let (_, gap) = same_day.expect("同日 2 公演で同じ曲を歌った例がある");
        assert_eq!(gap.months_since, Some(0));
        assert_eq!(gap.since_label, None);
        assert!(!gap.is_first);
    }
}

