//! 一覧を塊に分ける規則: 会場の都道府県ごとの塊と、公演の年ごとの塊。
//!
//! どちらも両 OS に写経されていた (iOS `VenuePickerView.grouped` / `FilteredShowsView.groupedByYear`、
//! Android `VenuePickerSheet` / `FilteredShowsViewModel`)。iOS は Dictionary を並べ替えていたので、
//! 塊の並びの同順位が起動ごとに変わりえた。ここでは同順位を名前順で決める (§8 P5-10)。
//!
//! 入力は OS が絞り込んだ後の並びの射影、出力は「見出し + 入力への添字」
//! (呼び出し側は自分の配列を添字で引き直す)。

use crate::domain::event_grouping::year_key;
use std::collections::HashMap;

/// 都道府県が分からない会場 (海外・非公開) の塊の見出し。いつも末尾。
pub const OTHER_AREA_LABEL: &str = "その他";

/// 年が分からない公演の塊の見出し。いつも末尾。
pub const UNKNOWN_YEAR_LABEL: &str = "日程未定";

/// 塊 1 つ: 見出しと、入力への添字 (入力の並びのまま)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct IndexGroup {
    pub label: String,
    pub indices: Vec<u32>,
}

/// 会場 1 件の射影。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct VenueAreaEntry {
    pub prefecture: Option<String>,
    /// 会場の並び順 (公演数の多い順に振ってある)。
    pub sort_order: i64,
}

/// 会場を都道府県ごとの塊にする。塊の並びは「塊の中でいちばん前の会場の並び順」の昇順
/// (公演数の多い地域が上)、同じなら見出しの名前順。都道府県が無い会場は末尾の「その他」。
pub fn group_venues_by_area(venues: &[VenueAreaEntry]) -> Vec<IndexGroup> {
    let mut order: Vec<String> = Vec::new();
    let mut groups: HashMap<String, (i64, Vec<u32>)> = HashMap::new();
    for (i, venue) in venues.iter().enumerate() {
        let area = venue
            .prefecture
            .as_deref()
            .filter(|p| !p.is_empty())
            .unwrap_or(OTHER_AREA_LABEL)
            .to_string();
        let entry = groups.entry(area.clone()).or_insert_with(|| {
            order.push(area);
            (i64::MAX, Vec::new())
        });
        entry.0 = entry.0.min(venue.sort_order);
        entry.1.push(i as u32);
    }
    order.sort_by(|a, b| {
        let key = |area: &String| (area == OTHER_AREA_LABEL, groups[area].0);
        key(a).cmp(&key(b)).then_with(|| a.cmp(b))
    });
    order
        .into_iter()
        .map(|area| {
            let indices = groups.remove(&area).map(|(_, idx)| idx).unwrap_or_default();
            IndexGroup { label: area, indices }
        })
        .collect()
}

/// 日付を年ごとの塊にする (新しい年が上)。塊の中は入力の並びのまま。
/// 見出しは `2026年`。年が読めない日付は末尾の「日程未定」。
pub fn group_indices_by_year_desc(dates: &[String]) -> Vec<IndexGroup> {
    let mut groups: Vec<(Option<String>, Vec<u32>)> = Vec::new();
    for (i, date) in dates.iter().enumerate() {
        let key = year_key(Some(date));
        match groups.iter_mut().find(|(k, _)| *k == key) {
            Some((_, indices)) => indices.push(i as u32),
            None => groups.push((key, vec![i as u32])),
        }
    }
    // None (日程未定) は末尾、ほかは年の降順。
    groups.sort_by(|(a, _), (b, _)| match (a, b) {
        (Some(a), Some(b)) => b.cmp(a),
        (a, b) => a.is_none().cmp(&b.is_none()),
    });
    groups
        .into_iter()
        .map(|(key, indices)| IndexGroup {
            label: key.map_or_else(|| UNKNOWN_YEAR_LABEL.to_string(), |y| format!("{y}年")),
            indices,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn venue(prefecture: Option<&str>, sort_order: i64) -> VenueAreaEntry {
        VenueAreaEntry { prefecture: prefecture.map(str::to_string), sort_order }
    }

    #[test]
    fn venues_group_by_prefecture_busiest_area_first_and_other_last() {
        let venues = [
            venue(Some("千葉県"), 5),
            venue(None, 0),
            venue(Some("東京都"), 1),
            venue(Some("千葉県"), 2),
            venue(Some(""), 3),
            venue(Some("東京都"), 9),
        ];
        let groups = group_venues_by_area(&venues);
        let labels: Vec<&str> = groups.iter().map(|g| g.label.as_str()).collect();
        assert_eq!(labels, ["東京都", "千葉県", "その他"]);
        assert_eq!(groups[0].indices, vec![2, 5], "塊の中は入力の並びのまま");
        assert_eq!(groups[1].indices, vec![0, 3]);
        assert_eq!(groups[2].indices, vec![1, 4], "都道府県が無い・空の会場はその他");
    }

    /// iOS は同順位の塊の並びが起動ごとに変わりえた。名前順で決める。
    #[test]
    fn ties_between_areas_are_broken_by_name() {
        let venues = [venue(Some("大阪府"), 1), venue(Some("愛知県"), 1)];
        let labels: Vec<String> = group_venues_by_area(&venues).into_iter().map(|g| g.label).collect();
        let mut sorted = labels.clone();
        sorted.sort();
        assert_eq!(labels, sorted);
    }

    #[test]
    fn shows_group_by_year_newest_first() {
        let dates: Vec<String> = ["2024-05-01", "2026-01-02", "2024-12-31", "", "2026-09-19"]
            .iter()
            .map(|d| d.to_string())
            .collect();
        let groups = group_indices_by_year_desc(&dates);
        let labels: Vec<&str> = groups.iter().map(|g| g.label.as_str()).collect();
        assert_eq!(labels, ["2026年", "2024年", "日程未定"]);
        assert_eq!(groups[0].indices, vec![1, 4]);
        assert_eq!(groups[1].indices, vec![0, 2]);
        assert!(group_indices_by_year_desc(&[]).is_empty());
    }
}
