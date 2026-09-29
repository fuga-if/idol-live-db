//! 公演 (1 日ぶん) を条件で絞る規則。
//!
//! 曲は [`crate::domain::song_list_filtering`]、イベントは
//! [`crate::domain::event_list_filtering`]、アイドルは
//! [`crate::domain::idol_list_filtering`] が絞り込みの正本になっているのに、
//! **公演だけ正本が無かった**。「出演者が 8 人以下の公演」「主演公演」のような
//! 判断が、LLM 向けツールの中に直書きされていた。
//!
//! ここに置くのは軸の**組み合わせ方**だけで、軸ごとの当たり方は既存の正本に委ねる:
//!
//! - ブランド (合同ライブ込み) … [`crate::domain::event_list_filtering::filter_event_indices`]
//! - 会場 (読み・旧名込み) … [`crate::domain::event_list_queries::show_indexes_at_venue`]
//! - 今後 / 過去 … [`crate::domain::event_grouping::Timeframe`] + `is_upcoming_on`
//! - 誰がいたか … [`crate::domain::event_detail_queries::show_presence`]
//!   (出演者表 ∪ 歌唱メンバー。出演者表が未入力で歌唱だけ入っている公演がある)
//! - 役割 … [`crate::domain::snapshot::Snapshot::show_cast_role`]
//!
//! 並びは (date ASC, sort_order ASC, 添字) の前計算列 `shows_in_date_order` から
//! 絞り込むので、同日 2 公演 (昼夜・DAY1/DAY2) の順序がカレンダーやイベント詳細と
//! 必ず一致する。**ここで日付を並べ替え直さない**。

use crate::domain::event_detail_queries::show_presence;
use crate::domain::event_grouping::{is_upcoming_on, Timeframe};
use crate::domain::event_list_filtering::{filter_event_indices, EventFilterCriteria, EventFilterItem};
use crate::domain::event_list_queries::show_indexes_at_venue;
use crate::domain::snapshot::Snapshot;
use std::collections::HashSet;

/// 公演の絞り込み条件。`None` / 空 = その軸では絞らない。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ShowFilterCriteria {
    /// ブランド id。合同ライブは参加ブランドどれでも当たる。
    pub brand_id: Option<String>,
    /// 公演日の年 (`"2026"`)。
    pub year: Option<String>,
    /// 会場名。読み・旧名でも当たる。
    pub venue: Option<String>,
    /// 親イベントの id。
    pub event_id: Option<String>,
    /// 親イベントの種別 (`live` / `festival` / `release_event`)。
    pub event_kind: Option<String>,
    /// その人が出ていた公演だけ (idols の添字)。
    pub idol: Option<u32>,
    /// 出演の役割 (`lead` / `member` …)。`idol` と併せるとその人の役割、
    /// 単独なら「その役割の人がいた公演」。
    pub cast_role: Option<String>,
    /// 出演者数の下限 / 上限。人数の定義は `show_presence`。
    pub min_cast: Option<u32>,
    pub max_cast: Option<u32>,
    /// セトリが入っている / 入っていない公演だけ。
    pub has_setlist: Option<bool>,
    /// 今後 / 過去 / 全部。
    pub when: Timeframe,
    /// 今日 (`YYYY-MM-DD`)。`when` が `All` のときは読まれない。
    pub today_key: String,
}

/// 条件に当たる公演の添字。並びは (date ASC, sort_order ASC)、
/// `when` が `Upcoming` 以外なら新しい順に反転する。
///
/// 会場に 1 件も当たらない・イベント id が無いといった「指定はあるが該当が無い」場合は
/// 空を返す。語彙外を突き返すかどうかは呼び手 (ツール面) の判断なので、ここでは決めない。
pub fn filter_show_indexes(snap: &Snapshot, c: &ShowFilterCriteria) -> Vec<u32> {
    // 安い軸から順に落として、高い軸 (出演者の集合を作るもの) に渡す数を減らす。
    let mut shows: Vec<u32> = snap.shows_in_date_order.clone();

    if let Some(year) = &c.year {
        shows.retain(|&s| snap.shows[s as usize].date.starts_with(year.as_str()));
    }
    if let Some(event_id) = &c.event_id {
        match snap.event_index_by_id.get(event_id) {
            Some(&event) => shows.retain(|&s| snap.shows[s as usize].event == event),
            None => return Vec::new(),
        }
    }
    if let Some(kind) = &c.event_kind {
        shows.retain(|&s| &snap.events[snap.shows[s as usize].event as usize].kind == kind);
    }
    if let Some(has_setlist) = c.has_setlist {
        shows.retain(|&s| !snap.setlist_items_by_show[s as usize].is_empty() == has_setlist);
    }
    if c.when != Timeframe::All {
        shows.retain(|&s| {
            c.when.accepts(is_upcoming_on(&snap.shows[s as usize].date, &c.today_key))
        });
    }
    if let Some(brand_id) = &c.brand_id {
        let events = events_of_brand(snap, brand_id);
        shows.retain(|&s| events.contains(&snap.shows[s as usize].event));
    }
    if let Some(venue) = &c.venue {
        let at_venue: HashSet<u32> = show_indexes_at_venue(snap, venue).into_iter().collect();
        shows.retain(|s| at_venue.contains(s));
    }

    // 役割は show_cast の行を見るだけなので、出演者の集合より先に落とす。
    match (c.idol, c.cast_role.as_deref()) {
        (Some(i), Some(role)) => shows.retain(|&s| snap.show_cast_role(s, i) == Some(role)),
        (None, Some(role)) => {
            shows.retain(|&s| snap.cast_by_show[s as usize].iter().any(|l| l.cast_role == role))
        }
        // 役割を問わず「その人がいたか」。集合を作らずに短絡で見る
        // (全公演ぶん HashSet を作ると 1 回の絞り込みで千数百本確保することになる)。
        (Some(i), None) => shows.retain(|&s| was_present(snap, s, i)),
        (None, None) => {}
    }

    if c.min_cast.is_some() || c.max_cast.is_some() {
        shows.retain(|&s| {
            let n = show_presence(snap, s).len() as u32;
            c.min_cast.is_none_or(|m| n >= m) && c.max_cast.is_none_or(|m| n <= m)
        });
    }

    if c.when.newest_first() {
        shows.reverse();
    }
    shows
}

/// その人がその公演にいたか。[`show_presence`] と同じ定義 (出演者表 ∪ 歌唱メンバー) を、
/// 集合を作らずに判定する。
pub fn was_present(snap: &Snapshot, show: u32, idol: u32) -> bool {
    snap.cast_by_show[show as usize].iter().any(|l| l.idol == idol)
        || snap.setlist_items_by_show[show as usize]
            .iter()
            .any(|&item| snap.performers_by_item[item as usize].contains(&idol))
}

/// そのブランドのイベント添字。合同ライブの扱いを含めて
/// `event_list_filtering` が正本 (一覧と同じ集合になる)。
fn events_of_brand(snap: &Snapshot, brand_id: &str) -> HashSet<u32> {
    let items: Vec<EventFilterItem> = snap
        .events
        .iter()
        .map(|e| EventFilterItem {
            id: e.id.clone(),
            brand_id: e.brand_id.clone(),
            joint_brand_ids: e.joint_brand_ids.clone(),
            name: e.name.clone(),
            kind: e.kind.clone(),
            event_type: e.event_type.clone(),
        })
        .collect();
    // ブランド以外の軸は使わない (uniffi::Record なので Default が無く、全欄を書く)。
    let criteria = EventFilterCriteria {
        selected_brand_ids: vec![brand_id.to_string()],
        excluded_kinds: Vec::new(),
        search_text: String::new(),
        attendance_filter: "all".to_string(),
        attended_event_ids: Vec::new(),
        require_favorite: false,
        favorite_ids: Vec::new(),
        require_note: false,
        note_ids: Vec::new(),
        venue: String::new(),
        venue_event_ids: Vec::new(),
        exclude_broadcast: false,
    };
    filter_event_indices(&items, &criteria).into_iter().collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    const TODAY: &str = "2026-09-19";

    fn criteria() -> ShowFilterCriteria {
        ShowFilterCriteria { today_key: TODAY.to_string(), ..ShowFilterCriteria::default() }
    }

    #[test]
    fn 同日の並びは前計算列と同じ() {
        let s = bundle_snapshot();
        // 反転しない (= 近い順の) 枠なら shows_in_date_order そのまま。
        let c = ShowFilterCriteria { when: Timeframe::Upcoming, ..criteria() };
        let got = filter_show_indexes(s, &c);
        let expected: Vec<u32> = s
            .shows_in_date_order
            .iter()
            .copied()
            .filter(|&i| is_upcoming_on(&s.shows[i as usize].date, TODAY))
            .collect();
        assert_eq!(got, expected, "同日の並びが前計算列とズレている");
        assert!(!got.is_empty(), "今後の公演が 1 件も無い");
    }

    #[test]
    fn 主演は役割で引ける() {
        let s = bundle_snapshot();
        let c = ShowFilterCriteria { cast_role: Some("lead".into()), ..criteria() };
        let lead = filter_show_indexes(s, &c);
        assert!(lead.len() >= 6, "主演公演が少なすぎる: {}", lead.len());
        assert!(lead
            .iter()
            .all(|&i| s.cast_by_show[i as usize].iter().any(|l| l.cast_role == "lead")));

        // 人と役割を組み合わせると、その人が主演の公演だけ。
        let idol = s.cast_by_show[lead[0] as usize]
            .iter()
            .find(|l| l.cast_role == "lead")
            .map(|l| l.idol)
            .unwrap();
        let mine = filter_show_indexes(
            s,
            &ShowFilterCriteria { idol: Some(idol), cast_role: Some("lead".into()), ..criteria() },
        );
        assert!(!mine.is_empty() && mine.len() <= lead.len());
        assert!(mine.iter().all(|&i| lead.contains(&i)));
    }

    #[test]
    fn 出演の判定は歌唱だけの公演も拾う() {
        let s = bundle_snapshot();
        // 出演者表に行が無く、歌唱者としてだけ出ている公演が実データにある。
        let found = (0..s.shows.len() as u32).find_map(|show| {
            s.setlist_items_by_show[show as usize].iter().find_map(|&item| {
                s.performers_by_item[item as usize]
                    .iter()
                    .copied()
                    .find(|&idol| !s.cast_by_show[show as usize].iter().any(|l| l.idol == idol))
                    .map(|idol| (show, idol))
            })
        });
        let Some((show, idol)) = found else { return };
        assert!(was_present(s, show, idol), "歌唱だけの出演を取りこぼしている");
        assert_eq!(was_present(s, show, idol), show_presence(s, show).contains(&idol));

        let got = filter_show_indexes(s, &ShowFilterCriteria { idol: Some(idol), ..criteria() });
        assert!(got.contains(&show));
    }

    #[test]
    fn 人数とセトリ有無で絞れる() {
        let s = bundle_snapshot();
        let c = ShowFilterCriteria {
            max_cast: Some(8),
            has_setlist: Some(true),
            ..criteria()
        };
        let got = filter_show_indexes(s, &c);
        assert!(!got.is_empty());
        for &i in &got {
            assert!(show_presence(s, i).len() <= 8);
            assert!(!s.setlist_items_by_show[i as usize].is_empty());
        }
        // セトリ無しの側と足すと、絞らないときの件数になる。
        let without = filter_show_indexes(
            s,
            &ShowFilterCriteria { max_cast: Some(8), has_setlist: Some(false), ..criteria() },
        );
        let both = filter_show_indexes(s, &ShowFilterCriteria { max_cast: Some(8), ..criteria() });
        assert_eq!(got.len() + without.len(), both.len());
    }

    #[test]
    fn 知らないイベント_id_は空() {
        let s = bundle_snapshot();
        let c = ShowFilterCriteria { event_id: Some("無いイベント".into()), ..criteria() };
        assert!(filter_show_indexes(s, &c).is_empty());
    }

    #[test]
    fn ブランドは合同ライブ込みでイベント一覧と同じ集合() {
        let s = bundle_snapshot();
        let c = ShowFilterCriteria { brand_id: Some("ml".into()), ..criteria() };
        let got = filter_show_indexes(s, &c);
        assert!(!got.is_empty());
        let events = events_of_brand(s, "ml");
        assert!(got.iter().all(|&i| events.contains(&s.shows[i as usize].event)));
        // 合同ライブ (joint_brand_ids に ml を含み brand_id は別) も入る。
        let joint = s.events.iter().enumerate().find(|(_, e)| {
            e.brand_id.as_deref() != Some("ml")
                && e.joint_brand_ids.as_deref().is_some_and(|j| j.contains("ml"))
        });
        if let Some((i, _)) = joint {
            assert!(events.contains(&(i as u32)), "合同ライブが落ちている");
        }
    }
}
