//! 「自分の回収」— セトリ 1 行を**自分の参加記録から見た**ときの事実。
//!
//! [`crate::domain::performance_gap`] が扱うのは世の中の披露 (「通算 4 回目」
//! 「3 年 10 か月ぶり」)。ここが扱うのは同じ行を自分だけの目盛りで見たもの
//! (「初回収」「回収 3 回目」「2 年ぶりの回収」「未回収」)。
//!
//! # 回収とは何か (ここが正本)
//!
//! **参加した「リアルライブ」(`events.kind` が `live` / `festival`) で披露された曲**を
//! 回収したと数える。歌枠・配信番組・ラジオ・リリイベは数えない — これは
//! 一覧の回収バッジ ([`crate::domain::song_list_queries::collected_counts_by_song`])
//! と同じ定義で、**両方ともここの [`attended_real_live_shows`] を通る**。
//! 定義を 2 か所に書くと、一覧が「回収済み」でセトリが「未回収」と言う日が来る。
//!
//! 現地参加だけを数えるか配信参加も数えるかは**ユーザー設定**で、参加マークを
//! id 列に解決する時点で効く ([`collection_attended_show_ids`])。
//!
//! # 「その公演時点」と「今」を使い分ける (意図的)
//!
//! - **参加した公演の行** … その公演時点で数える。2016 年に参加した公演を開いて
//!   「初回収」と出るのは、2022 年にもう一度聴いていても正しい
//!   (その日は確かに初めてだった)。
//! - **参加していない公演の行** … 今から見て一度も回収していない曲にだけ「未回収」。
//!   古いセトリを眺めて知りたいのは「この曲、自分はまだ持っていない」であって、
//!   「2016 年の時点では持っていなかった」ではない。
//!
//! 片方だけの流儀に揃えると、どちらかが嘘になる。**この非対称は意図であって
//! 抜け漏れではない**ので、揃えたくなったらこの段落を先に読むこと。
//!
//! # 同じ公演で 2 回歌われた曲
//!
//! 回収は**公演の異なり数**で数える (アンコールの再披露は 1 回)。一覧の回収数
//! (`COUNT(DISTINCT show_id)`) と同じ数え方。行としては 2 行とも同じ札が付く。

// 参加マークの射影は一覧側と同じ型を使う (同じものを 2 つ定義しない)。
pub use crate::domain::event_list_queries::AttendanceMarkRecord;
use crate::domain::event_detail_queries::{
    NON_PERFORMANCE_PERFORMER_TYPES, NON_PERFORMANCE_VENUE_MODES,
};
use crate::domain::performance_gap::{months_between, notable_interval_label};
use crate::domain::snapshot::Snapshot;
use std::collections::HashSet;


/// 参加形態を持たない古いマークの扱い。**現地参加**とみなす
/// (形態を選べるようにする前のマークはすべて現地参加の意味で付いている)。
const LOCAL_ATTENDANCE: &str = "live";

/// 回収の対象になる催し (`events.kind`)。歌枠・配信番組・ラジオ・リリイベは入らない。
pub const REAL_LIVE_KINDS: [&str; 2] = ["live", "festival"];

/// 回収の対象になる催しの `events.kind`。
///
/// **SQL 経路 (`AppDatabase+UserMarks`) が IN 句を組むためにこれを引く。**
/// 同じ値を Swift のリテラルで持つと、対象を足したときに片方だけ古いまま残る。
pub fn collection_real_live_kinds() -> Vec<String> {
    REAL_LIVE_KINDS.iter().map(|k| k.to_string()).collect()
}

/// 催しがリアルライブでも回収に数えない公演の `shows.performer_type` (上映会) と
/// `shows.venue_mode` (会場の舞台が無い配信ライブ)。
///
/// SQL 経路が `NOT IN` を組むために引く ([`collection_real_live_kinds`] と同じ理由)。
/// どちらの列も NULL の公演は対象のまま — `NOT IN` に NULL を渡すと全部落ちるので、
/// 呼び手は `COALESCE(列, '')` で比べること。
pub fn non_performance_performer_types() -> Vec<String> {
    NON_PERFORMANCE_PERFORMER_TYPES.iter().map(|t| t.to_string()).collect()
}

/// [`non_performance_performer_types`] の `venue_mode` 版。
pub fn non_performance_venue_modes() -> Vec<String> {
    NON_PERFORMANCE_VENUE_MODES.iter().map(|m| m.to_string()).collect()
}

/// 回収に数える参加形態 (`user_marks.text_value`)。**空なら形態を問わない。**
///
/// SQL 経路が `text_value IS NULL OR text_value IN (…)` を組むために引く。
/// `NULL` を現地扱いにする規則は [`collection_attended_show_ids`] と同じで、
/// 絞るときは必ず [`LOCAL_ATTENDANCE`] が並びに入るので両者は同じ集合を選ぶ。
pub fn collection_attendance_types(include_stream: bool) -> Vec<String> {
    if include_stream {
        Vec::new()
    } else {
        vec![LOCAL_ATTENDANCE.to_string()]
    }
}

/// 回収に数える参加マークを選ぶ。**この規則の正本はここ 1 つ。**
///
/// 既定は現地参加のみ。`include_stream` (設定「配信参加も回収に含める」) が真なら
/// 形態を問わない — 地方勢のための設定なので、LV も配信もまとめて含める。
///
/// 以前はこの規則が iOS の `AppDatabase+UserMarks.attendedTypeCondition` と
/// `CoreSongRepository` に 2 つ書かれていて、片方が private という理由で
/// 「変更時は両方を揃えること」という但し書きまで付いていた。Android を足せば 3 つ目になる。
pub fn collection_attended_show_ids(
    marks: Vec<AttendanceMarkRecord>,
    include_stream: bool,
) -> Vec<String> {
    let kept = collection_attendance_types(include_stream);
    marks
        .into_iter()
        .filter(|m| {
            // 形態を持たない古いマークは現地参加として扱う。
            let attendance = m.attendance_type.as_deref().unwrap_or(LOCAL_ATTENDANCE);
            kept.is_empty() || kept.iter().any(|k| k == attendance)
        })
        .map(|m| m.entity_id)
        .collect()
}

/// その公演は回収の対象か (リアルライブか)。歌枠・配信番組・ラジオ・リリイベは対象外。
///
/// 催しがライブでも、その中の上映会 (MV 上映会など、誰も歌わない公演) は対象外
/// ([`crate::domain::snapshot::Show::counts_as_performance`])。
pub fn is_real_live(snap: &Snapshot, show: u32) -> bool {
    let show = &snap.shows[show as usize];
    let kind = snap.events[show.event as usize].kind.as_str();
    REAL_LIVE_KINDS.contains(&kind) && show.counts_as_performance()
}

/// 参加マークの id 列 → 参加した公演 (スナップショット添字) の集合。
///
/// - `attended_show_ids`: show 単位の参加マーク (参加形態の条件は解決済みで渡す)。
/// - `attended_event_ids`: event 単位の参加マーク。配下の全公演に展開する
///   (`shows` はマスタなので展開はコアの仕事)。
/// - `real_live_only`: 回収の定義どおり `live` / `festival` だけに絞るか。
///   一覧の並び替えだけは「参加した公演」を種別で絞らずに数える (既存挙動) ため、
///   そこだけ `false` で呼ぶ。
pub fn attended_real_live_shows(
    snap: &Snapshot,
    attended_show_ids: &[String],
    attended_event_ids: &[String],
    real_live_only: bool,
) -> HashSet<u32> {
    let mut attended: HashSet<u32> = attended_show_ids
        .iter()
        .filter_map(|id| snap.show_index_by_id.get(id).copied())
        .collect();
    for event_id in attended_event_ids {
        if let Some(&e) = snap.event_index_by_id.get(event_id) {
            attended.extend(snap.shows_by_event[e as usize].iter().copied());
        }
    }
    if real_live_only {
        attended.retain(|&show| is_real_live(snap, show));
    }
    attended
}

/// セトリ 1 行を自分の参加記録から見た事実。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct CollectionGap {
    /// この行の公演に自分が参加しているか (= この行は回収そのもの)。
    pub attended: bool,
    /// 自分にとって何回目の回収か (1 = 初回収)。参加していない行では 0。
    pub ordinal: u32,
    /// `初回収` / `回収 3 回目`。参加していない行では `None`。
    pub ordinal_label: Option<String>,
    pub is_first: bool,
    /// 自分が前にこの曲を回収した公演の日。初回収と未参加の行では `None`。
    pub previous_date: Option<String>,
    /// 前の回収からの間隔 (か月)。
    pub months_since: Option<u32>,
    /// これまでに回収した回数 (公演の異なり数)。**参加の有無によらず「今」から見た数**
    /// (参加した行では、その行より後の回収も入る)。0 なら一度も回収していない。
    /// 「その公演時点で何回目か」を知りたいときは [`Self::ordinal`] を見ること。
    pub collected_count: u32,
}

/// 回収の回数の言い回し。**言い方はここ 1 箇所**。
///
/// 「回収 3 回目」とは言わない — 行では「回収」という軸のラベルの右に出るので、
/// 値の側でもう一度「回収」と言うと同じ語が 2 度並ぶ
/// (`crate::domain::screen_composition::setlist_row_note_groups`)。
pub fn collection_ordinal_label(ordinal: u32) -> String {
    if ordinal <= 1 {
        "初回収".to_string()
    } else {
        format!("{ordinal} 回目")
    }
}

/// 前の回収からの間隔の言い回し。線引きは披露の「3 年 10 か月ぶり」と同じ (1 年以上)。
pub fn collection_interval_label(gap: &CollectionGap) -> Option<String> {
    gap.months_since.and_then(notable_interval_label)
}

/// その披露 (`setlist_items` の添字) を、自分の参加記録から見る。
///
/// `attended` は [`attended_real_live_shows`] で解決した公演集合。
pub fn collection_gap(snap: &Snapshot, item: u32, attended: &HashSet<u32>) -> CollectionGap {
    let row = &snap.setlist_items[item as usize];
    let here = row.show;

    // この曲を回収した公演を古い順に (同じ公演での再披露は 1 回)。
    let mut collected: Vec<u32> = snap.setlist_items_by_song[row.song as usize]
        .iter()
        .map(|&i| snap.setlist_items[i as usize].show)
        .filter(|show| attended.contains(show))
        .collect();
    collected.sort_by_key(|&show| chronological_key(snap, show));
    collected.dedup();

    if !attended.contains(&here) {
        return CollectionGap {
            attended: false,
            collected_count: collected.len() as u32,
            ..CollectionGap::default()
        };
    }

    let position = collected.iter().position(|&show| show == here).unwrap_or(0);
    let previous_date =
        position.checked_sub(1).map(|p| snap.shows[collected[p] as usize].date.clone());
    let date = &snap.shows[here as usize].date;
    let months_since =
        previous_date.as_deref().map(|prev| months_between(prev, date).unwrap_or(0));
    let ordinal = position as u32 + 1;
    CollectionGap {
        attended: true,
        ordinal,
        ordinal_label: Some(collection_ordinal_label(ordinal)),
        is_first: ordinal == 1,
        previous_date,
        months_since,
        collected_count: collected.len() as u32,
    }
}

/// 公演を古い順に並べるキー。同じ日の昼夜は `shows.sort_order` の順。
fn chronological_key(snap: &Snapshot, show: u32) -> (&str, i64, u32) {
    let s = &snap.shows[show as usize];
    (s.date.as_str(), s.sort_order, show)
}

// =============================================================================
// 公演 1 つぶんの要約
// =============================================================================

/// セトリの頭に出す「自分の回収」の要約。出すものが無ければ [`show_collection_summary`]
/// が `None` を返す。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ShowCollectionRecord {
    /// この公演に自分が参加しているか。
    pub attended: bool,
    /// この公演で回収した曲数 (曲の異なり数)。参加していなければ 0。
    pub collected_songs: u32,
    /// そのうち初回収だった曲数。
    pub first_collected_songs: u32,
    /// まだ回収していない曲数 (参加していない公演のときだけ数える)。
    pub uncollected_songs: u32,
    /// セトリの曲数 (曲の異なり数)。
    pub total_songs: u32,
    /// 1 行で出す文言。
    pub label: String,
}

/// 行ごとの [`CollectionGap`] から公演 1 つぶんの要約を組む。
///
/// `has_marks` が偽 (参加記録を 1 件も付けていない) のときは `None` —
/// 使い始めの人に「未回収 35 曲」と言っても何の情報でもない。
/// `is_real_live` が偽 (回収の対象でない催し) のときも `None`。
///
/// 引数は `(song_id, gap)` の列で、**セトリの並びそのまま**渡してよい
/// (同じ曲が 2 行あっても曲の異なり数で数える)。
pub fn show_collection_summary(
    rows: &[(String, CollectionGap)],
    has_marks: bool,
    is_real_live: bool,
) -> Option<ShowCollectionRecord> {
    if rows.is_empty() || !has_marks || !is_real_live {
        return None;
    }
    let mut seen: HashSet<&str> = HashSet::new();
    let mut total = 0u32;
    let mut collected = 0u32;
    let mut first = 0u32;
    let mut uncollected = 0u32;
    let mut attended = false;
    for (song_id, gap) in rows {
        if !seen.insert(song_id.as_str()) {
            continue;
        }
        total += 1;
        attended |= gap.attended;
        if gap.attended {
            collected += 1;
            if gap.is_first {
                first += 1;
            }
        } else if gap.collected_count == 0 {
            uncollected += 1;
        }
    }
    let label = if attended {
        let mut text = format!("この公演で {collected} 曲回収");
        if first > 0 {
            text.push_str(&format!("・初回収 {first} 曲"));
        }
        text
    } else if uncollected > 0 {
        format!("このセトリに未回収 {uncollected} 曲")
    } else {
        "このセトリは全曲回収済み".to_string()
    };
    Some(ShowCollectionRecord {
        attended,
        collected_songs: collected,
        first_collected_songs: first,
        uncollected_songs: uncollected,
        total_songs: total,
        label,
    })
}

/// 曲詳細の「現地回収 N 公演」: その曲を回収した公演 (Q-08c)。
///
/// 一覧の回収バッジ・セトリの「未回収」と**同じ規則で絞る**: 催しはリアルライブ
/// ([`REAL_LIVE_KINDS`]) だけ、参加マークは [`collection_attended_show_ids`] を通したもの
/// (show 単位・event 単位のどちらも) を渡す。新しい公演から (同じ日は sort_order → 公演 id)。
pub fn song_collected_shows(
    snap: &Snapshot,
    song_id: &str,
    attended_show_ids: &[String],
    attended_event_ids: &[String],
) -> Vec<crate::domain::event_detail_queries::ShowWithEventNameRecord> {
    let Some(&song) = snap.song_index_by_id.get(song_id) else { return Vec::new() };
    let attended = attended_real_live_shows(snap, attended_show_ids, attended_event_ids, true);
    let mut shows: Vec<u32> = snap.setlist_items_by_song[song as usize]
        .iter()
        .map(|&item| snap.setlist_items[item as usize].show)
        .filter(|show| attended.contains(show))
        .collect();
    shows.sort_by(|&a, &b| {
        let (sa, sb) = (&snap.shows[a as usize], &snap.shows[b as usize]);
        sb.date.cmp(&sa.date).then(sa.sort_order.cmp(&sb.sort_order)).then_with(|| sa.id.cmp(&sb.id))
    });
    shows.dedup();
    shows
        .into_iter()
        .map(|show| crate::domain::event_detail_queries::show_with_event_name_at(snap, show))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    /// 曲 × 公演日 から披露 (`setlist_items` 添字) を引く。
    fn item_of(song_id: &str, date: &str) -> u32 {
        let snap = bundle_snapshot();
        let si = snap.song_index_by_id[song_id];
        snap.setlist_items_by_song[si as usize]
            .iter()
            .copied()
            .find(|&i| snap.shows[snap.setlist_items[i as usize].show as usize].date == date)
            .unwrap_or_else(|| panic!("{song_id} の {date} の披露"))
    }

    fn show_id_of(item: u32) -> String {
        let snap = bundle_snapshot();
        snap.shows[snap.setlist_items[item as usize].show as usize].id.clone()
    }

    /// 参加した公演の集合を show id から組む。
    fn attending(show_ids: &[String]) -> HashSet<u32> {
        attended_real_live_shows(bundle_snapshot(), show_ids, &[], true)
    }

    // ---- 参加マークの選び方 ----

    /// 既定は現地だけ。形態を持たない古いマークは現地として残す。
    #[test]
    fn 既定では現地参加だけを回収に数える() {
        let marks = vec![
            AttendanceMarkRecord { entity_id: "a".into(), attendance_type: Some("live".into()) },
            AttendanceMarkRecord { entity_id: "b".into(), attendance_type: Some("stream".into()) },
            AttendanceMarkRecord {
                entity_id: "c".into(),
                attendance_type: Some("live_viewing".into()),
            },
            AttendanceMarkRecord { entity_id: "d".into(), attendance_type: None },
        ];
        assert_eq!(collection_attended_show_ids(marks.clone(), false), vec!["a", "d"]);
        // 設定を入れた人は形態を問わない (LV も配信も含む)。
        assert_eq!(collection_attended_show_ids(marks, true), vec!["a", "b", "c", "d"]);
    }

    /// SQL 経路 (`AppDatabase+UserMarks`) が IN 句に使う値は、Rust の判定と同じ集合を指す。
    #[test]
    fn sql_経路に配る値は判定と同じものを指す() {
        let snap = bundle_snapshot();
        // 催しの種別と公演の区分: collection_real_live_kinds の並びにあり、
        // non_performance_* のどちらにも当たらない公演だけが is_real_live を通る。
        let kinds = collection_real_live_kinds();
        let (types, modes) = (non_performance_performer_types(), non_performance_venue_modes());
        let mut excluded = 0;
        for show in 0..snap.shows.len() as u32 {
            let s = &snap.shows[show as usize];
            let kind = &snap.events[s.event as usize].kind;
            let by_sql = kinds.contains(kind)
                && !types.iter().any(|t| Some(t.as_str()) == s.performer_type.as_deref())
                && !modes.iter().any(|m| Some(m.as_str()) == s.venue_mode.as_deref());
            assert_eq!(is_real_live(snap, show), by_sql, "{}", s.id);
            excluded += usize::from(kinds.contains(kind) && !by_sql);
        }
        assert!(excluded > 10, "上映会・配信だけのライブが外れている: {excluded}");
        // 参加形態: 絞るときは必ず「現地」が並びに入る (NULL を現地扱いにする規則と揃う)。
        assert_eq!(collection_attendance_types(false), vec!["live".to_string()]);
        assert!(collection_attendance_types(true).is_empty(), "設定 ON では形態を問わない");
    }

    // ---- 1 行ぶんの事実 ----

    /// 参加した公演の行は、その公演時点で数える。
    #[test]
    fn 参加した公演では何回目の回収かをその日時点で数える() {
        let snap = bundle_snapshot();
        let song = "765as_初恋_一章_片想いの桜";
        // 4 回の披露: 2014-10-05 / 2016-04-30 / 2022-11-13 / 2026-09-19。
        let (a, b, c) = (
            item_of(song, "2014-10-05"),
            item_of(song, "2016-04-30"),
            item_of(song, "2022-11-13"),
        );
        // 2014 と 2022 に参加したことにする。
        let attended = attending(&[show_id_of(a), show_id_of(c)]);

        let first = collection_gap(snap, a, &attended);
        assert!(first.attended);
        assert_eq!(first.ordinal, 1);
        assert_eq!(first.ordinal_label.as_deref(), Some("初回収"));
        assert!(first.is_first);
        assert_eq!(first.previous_date, None);

        // 行っていない 2016 の行は回収ではない。ただし 2014 に回収済みなので「未回収」でもない。
        let skipped = collection_gap(snap, b, &attended);
        assert!(!skipped.attended);
        assert_eq!(skipped.ordinal, 0);
        assert_eq!(skipped.collected_count, 2, "今から見た回収数 (2014 と 2022)");

        let second = collection_gap(snap, c, &attended);
        assert!(second.attended);
        assert_eq!(second.ordinal, 2);
        assert!(!second.is_first);
        assert_eq!(second.previous_date.as_deref(), Some("2014-10-05"));
        assert_eq!(second.ordinal_label.as_deref(), Some("2 回目"));
        assert_eq!(collection_interval_label(&second).as_deref(), Some("8 年 1 か月ぶり"));
    }

    /// 回収はリアルライブだけ。参加マークが付いていても歌枠等は数えない。
    #[test]
    fn リアルライブ以外の参加は回収に数えない() {
        let snap = bundle_snapshot();
        let non_live = snap
            .shows
            .iter()
            .enumerate()
            .find(|(i, s)| {
                !s.date.is_empty()
                    && !is_real_live(snap, *i as u32)
                    && !snap.setlist_items_by_show[*i].is_empty()
            })
            .map(|(i, s)| (i as u32, s.id.clone()));
        let Some((index, id)) = non_live else { return };
        assert!(attending(&[id.clone()]).is_empty(), "{id} は回収の対象外");
        // 種別を絞らない呼び方 (一覧の並び替え) では残る。
        assert!(attended_real_live_shows(snap, &[id], &[], false).contains(&index));
    }

    /// イベント単位の参加マークは配下の公演に展開される。
    #[test]
    fn イベントの参加マークは配下の公演に広がる() {
        let snap = bundle_snapshot();
        let (event, shows) = snap
            .events
            .iter()
            .enumerate()
            .map(|(i, e)| (e.id.clone(), snap.shows_by_event[i].clone()))
            .find(|(_, shows)| {
                shows.len() >= 2 && shows.iter().all(|&s| is_real_live(snap, s))
            })
            .expect("公演が 2 つ以上のリアルライブがある");
        let attended = attended_real_live_shows(snap, &[], &[event], true);
        for show in shows {
            assert!(attended.contains(&show));
        }
    }

    /// 言い回し。
    #[test]
    fn 回数と間隔の言い方は_1_箇所で決まる() {
        // 「回収」は行の軸ラベルが言うので、値の側では言わない。
        assert_eq!(collection_ordinal_label(1), "初回収");
        assert_eq!(collection_ordinal_label(2), "2 回目");

        let with_gap = CollectionGap { months_since: Some(46), ..CollectionGap::default() };
        assert_eq!(collection_interval_label(&with_gap).as_deref(), Some("3 年 10 か月ぶり"));
        // 1 年未満の間隔は言わない。
        let recent = CollectionGap { months_since: Some(11), ..CollectionGap::default() };
        assert_eq!(collection_interval_label(&recent), None);
        assert_eq!(collection_interval_label(&CollectionGap::default()), None);
    }

    // ---- 公演 1 つぶんの要約 ----

    fn gap(attended: bool, ordinal: u32, collected: u32) -> CollectionGap {
        CollectionGap {
            attended,
            ordinal,
            ordinal_label: attended.then(|| collection_ordinal_label(ordinal)),
            is_first: attended && ordinal == 1,
            collected_count: collected,
            ..CollectionGap::default()
        }
    }

    #[test]
    fn 参加した公演の要約は回収数と初回収数を言う() {
        let rows = vec![
            ("a".to_string(), gap(true, 1, 1)),
            ("b".to_string(), gap(true, 3, 3)),
            ("c".to_string(), gap(true, 1, 1)),
        ];
        let summary = show_collection_summary(&rows, true, true).expect("要約が出る");
        assert!(summary.attended);
        assert_eq!(summary.collected_songs, 3);
        assert_eq!(summary.first_collected_songs, 2);
        assert_eq!(summary.label, "この公演で 3 曲回収・初回収 2 曲");
    }

    /// 同じ公演で 2 回歌われた曲は 1 曲として数える。
    #[test]
    fn 同じ曲が_2_行あっても_1_曲と数える() {
        let rows = vec![("a".to_string(), gap(true, 1, 1)), ("a".to_string(), gap(true, 1, 1))];
        let summary = show_collection_summary(&rows, true, true).expect("要約が出る");
        assert_eq!(summary.total_songs, 1);
        assert_eq!(summary.collected_songs, 1);
        assert_eq!(summary.first_collected_songs, 1);
    }

    #[test]
    fn 参加していない公演の要約は未回収の曲数を言う() {
        let rows = vec![
            ("a".to_string(), gap(false, 0, 0)),
            ("b".to_string(), gap(false, 0, 2)),
            ("c".to_string(), gap(false, 0, 0)),
        ];
        let summary = show_collection_summary(&rows, true, true).expect("要約が出る");
        assert!(!summary.attended);
        assert_eq!(summary.uncollected_songs, 2);
        assert_eq!(summary.label, "このセトリに未回収 2 曲");

        // 全部回収済みなら、そう言う。
        let all = vec![("a".to_string(), gap(false, 0, 1))];
        assert_eq!(
            show_collection_summary(&all, true, true).expect("要約が出る").label,
            "このセトリは全曲回収済み"
        );
    }

    /// 参加記録が 1 件も無い人、回収の対象でない催し、空のセトリでは何も出さない。
    #[test]
    fn 出すものが無ければ要約を出さない() {
        let rows = vec![("a".to_string(), gap(false, 0, 0))];
        assert_eq!(show_collection_summary(&rows, false, true), None, "参加記録が無い人");
        assert_eq!(show_collection_summary(&rows, true, false), None, "回収の対象でない催し");
        assert_eq!(show_collection_summary(&[], true, true), None, "セトリが空");
    }

    #[test]
    fn song_collected_shows_keeps_only_attended_real_lives_newest_first() {
        let snap = crate::test_support::bundle_snapshot();
        // セトリの行がいちばん多い曲。
        let song = (0..snap.songs.len()).max_by_key(|&s| snap.setlist_items_by_song[s].len()).unwrap();
        let song_id = snap.songs[song].id.clone();
        let performed: Vec<u32> =
            snap.setlist_items_by_song[song].iter().map(|&i| snap.setlist_items[i as usize].show).collect();
        let real = performed.iter().copied().find(|&s| is_real_live(snap, s)).expect("リアルライブで披露");
        let other = snap.shows.iter().position(|s| !REAL_LIVE_KINDS.contains(&snap.events[s.event as usize].kind.as_str()));
        let mut ids: Vec<String> = performed.iter().take(20).map(|&s| snap.shows[s as usize].id.clone()).collect();
        if let Some(o) = other {
            ids.push(snap.shows[o].id.clone());
        }
        ids.push(snap.shows[real as usize].id.clone());
        let got = song_collected_shows(snap, &song_id, &ids, &[]);
        assert!(!got.is_empty());
        let got_ids: HashSet<&str> = got.iter().map(|r| r.id.as_str()).collect();
        assert_eq!(got_ids.len(), got.len(), "同じ公演は 1 行");
        for r in &got {
            let show = snap.show_index_by_id[&r.id];
            assert!(is_real_live(snap, show), "リアルライブだけ");
            assert!(performed.contains(&show));
        }
        assert!(got.windows(2).all(|w| w[0].date >= w[1].date), "新しい順");
        // event 単位の参加は配下の公演に広がる。
        let event_id = snap.events[snap.shows[real as usize].event as usize].id.clone();
        let by_event = song_collected_shows(snap, &song_id, &[], &[event_id]);
        assert!(by_event.iter().any(|r| r.id == snap.shows[real as usize].id));
        assert!(song_collected_shows(snap, "存在しない", &ids, &[]).is_empty());
    }
}
