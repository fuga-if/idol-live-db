//! 一覧の絞り込みの選択肢 (出面の島が並べるもの)。
//!
//! どの値を選択肢に出すか・その並び・並べ替えの一覧と既定を、**ここで 1 回だけ**決める。
//! 出面の島は wasm 越しにこれを受け取って並べるだけで、選択肢の型も ts-rs が出す
//! (以前は wasm の crate が選択肢を組み、TS が型を手書きしていた — D-WEB-07 / D-CORE-16)。
//!
//! 値の集合と並びはアプリのピッカーと同じ関数 (`brand_records` / `all_idols_for_picker` /
//! `album_summaries` / `series_group_names`) を通す。ここで snap を自前で走査すると、
//! 並びだけが他の画面と違う一覧になる (アイドルが rowid 順・シリーズが辞書順になっていた)。

use crate::domain::idol_list_filtering::{sort_order_table, IdolListEntry, IdolSortKind};
use crate::domain::snapshot::Snapshot;
use crate::domain::song_list_queries::{
    filter_song_indexes, song_list_sort_options_without_user_marks, SongListSort, SongQuery,
};
use crate::domain::{idol_queries, song_detail_queries, vocabulary};
use std::collections::{BTreeSet, HashSet};

/// 選択肢 1 件。`value` は絞り込みの条件 (`SongQuery` / `IdolQuery`) にそのまま渡す文字列。
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
#[cfg_attr(
    feature = "web-export",
    derive(ts_rs::TS),
    ts(export, export_to = "../../web/src/lib/schema/")
)]
pub struct FacetOption {
    pub value: String,
    pub label: String,
}

/// 並べ替え 1 件。既定の向きもここが持つ (出面は矢印の初期値に使う)。
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
#[cfg_attr(
    feature = "web-export",
    derive(ts_rs::TS),
    ts(export, export_to = "../../web/src/lib/schema/")
)]
pub struct SortOption {
    /// `SongListSort::key` / `IdolSortKind::key`。
    pub key: String,
    pub label: String,
    pub default_ascending: bool,
}

/// 楽曲一覧の選択肢。
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
#[cfg_attr(
    feature = "web-export",
    derive(ts_rs::TS),
    ts(export, export_to = "../../web/src/lib/schema/")
)]
pub struct SongFacets {
    /// 一覧に実際に居るアイドルのブランドだけ (外部ゲストしか居ない `other` は出さない)。
    pub brands: Vec<FacetOption>,
    pub idols: Vec<FacetOption>,
    pub cd_series: Vec<FacetOption>,
    pub series_groups: Vec<FacetOption>,
    /// 曲種別。一覧に実在する種別だけを、`vocabulary::SONG_TYPES` の並びと正式な形で (Q-08f)。
    pub song_types: Vec<FacetOption>,
    /// ログインもユーザーデータも持たない出面で選べる並べ替え。
    pub sorts: Vec<SortOption>,
    /// 既定の並べ替え (未指定・未知の鍵が倒れる先)。
    pub default_sort: String,
}

/// アイドル一覧の選択肢。
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
#[cfg_attr(
    feature = "web-export",
    derive(ts_rs::TS),
    ts(export, export_to = "../../web/src/lib/schema/")
)]
pub struct IdolFacets {
    /// 一覧に実際に居るアイドルのブランドだけ。
    pub brands: Vec<FacetOption>,
    /// 属性は実データに出てくるものだけ (ブランドごとに語彙が違う)。
    pub attributes: Vec<FacetOption>,
    /// 誕生月 (1〜12)。値は `IdolQuery.birth_month` の数を文字列にしたもの。
    pub birth_months: Vec<FacetOption>,
    pub sorts: Vec<SortOption>,
    /// 既定の並べ替え (公式順)。
    pub default_sort: String,
}

/// 楽曲一覧の既定の並び。`SongListSort::from_key` が未知の鍵を倒す先と同じ。
pub const SONG_DEFAULT_SORT: SongListSort = SongListSort::TitleKana;
/// アイドル一覧の既定の並び。`IdolSortKind::from_key` が未知の鍵を倒す先と同じ。
pub const IDOL_DEFAULT_SORT: IdolSortKind = IdolSortKind::Official;

fn option(value: impl Into<String>, label: impl Into<String>) -> FacetOption {
    FacetOption { value: value.into(), label: label.into() }
}

/// 表示名がそのまま条件になる列 (CD シリーズ・シリーズ) の選択肢。
fn same_value_options(names: Vec<String>) -> Vec<FacetOption> {
    names.into_iter().map(|v| option(v.clone(), v)).collect()
}

/// 一覧に実際に居るアイドルのブランドだけ (外部ゲストしか居ないブランドを選べても 0 件になるだけ)。
fn present_brands(snap: &Snapshot, idol_entries: &[IdolListEntry]) -> Vec<FacetOption> {
    let present: HashSet<&str> = idol_entries.iter().map(|e| e.brand_id.as_str()).collect();
    idol_queries::brand_records(snap)
        .into_iter()
        .filter(|b| present.contains(b.id.as_str()))
        .map(|b| option(b.id, b.name))
        .collect()
}

/// 一覧 (`SongQuery::default()` の母集団) に実在する曲種別だけを、語彙の並びで
/// (ブランドと同じ規則。一覧に居ない種別を選べても 0 件になるだけ)。
fn present_song_types(snap: &Snapshot) -> Vec<FacetOption> {
    let present: HashSet<&str> = filter_song_indexes(snap, &SongQuery::default().to_filter())
        .into_iter()
        .filter_map(|i| snap.songs[i as usize].song_type.as_deref())
        .collect();
    vocabulary::SONG_TYPES
        .iter()
        .filter(|t| present.contains(t.value))
        .map(|t| option(t.value, t.label))
        .collect()
}

/// 楽曲一覧の選択肢。`idol_entries` は `idol_list_entries(snap)` (出面の島が 1 度だけ組むもの)。
pub fn song_facets(snap: &Snapshot, idol_entries: &[IdolListEntry]) -> SongFacets {
    SongFacets {
        brands: present_brands(snap, idol_entries),
        idols: idol_queries::all_idols_for_picker(snap)
            .into_iter()
            .map(|i| option(i.id, i.name))
            .collect(),
        cd_series: same_value_options(
            song_detail_queries::album_summaries(snap, &[], None)
                .into_iter()
                .map(|a| a.cd_series)
                .collect(),
        ),
        series_groups: same_value_options(song_detail_queries::series_group_names(snap, &[])),
        song_types: present_song_types(snap),
        sorts: song_list_sort_options_without_user_marks()
            .into_iter()
            .map(|o| SortOption { key: o.key, label: o.label, default_ascending: o.default_ascending })
            .collect(),
        default_sort: SONG_DEFAULT_SORT.key().to_string(),
    }
}

/// アイドル一覧の選択肢。
pub fn idol_facets(snap: &Snapshot, idol_entries: &[IdolListEntry]) -> IdolFacets {
    let attributes: BTreeSet<&str> = idol_entries
        .iter()
        .filter_map(|e| e.attribute.as_deref().filter(|a| !a.is_empty()))
        .collect();
    IdolFacets {
        brands: present_brands(snap, idol_entries),
        attributes: attributes.into_iter().map(|a| option(a, a)).collect(),
        birth_months: (1..=12u32).map(|m| option(m.to_string(), format!("{m}月"))).collect(),
        sorts: sort_order_table()
            .into_iter()
            .map(|m| SortOption {
                key: m.kind.key().to_string(),
                label: m.display_name,
                default_ascending: m.default_ascending,
            })
            .collect(),
        default_sort: IDOL_DEFAULT_SORT.key().to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_sorts_are_where_unknown_keys_fall() {
        assert_eq!(SongListSort::from_key("まだ無い並び"), SONG_DEFAULT_SORT);
        assert_eq!(IdolSortKind::from_key("まだ無い並び"), IDOL_DEFAULT_SORT);
    }

    #[test]
    fn empty_snapshot_still_offers_the_fixed_choices() {
        let snap = Snapshot::default();
        let songs = song_facets(&snap, &[]);
        assert!(songs.brands.is_empty() && songs.idols.is_empty() && songs.song_types.is_empty());
        assert_eq!(songs.default_sort, "kana");
        assert!(songs.sorts.iter().any(|s| s.key == songs.default_sort));
        // ユーザーデータの要る並び (回収数・回収率) は出面に出さない。
        assert!(songs.sorts.iter().all(|s| !SongListSort::from_key(&s.key).requires_user_marks()));

        let idols = idol_facets(&snap, &[]);
        assert_eq!(idols.birth_months.len(), 12);
        assert_eq!((idols.birth_months[0].value.as_str(), idols.birth_months[0].label.as_str()), ("1", "1月"));
        assert_eq!(idols.default_sort, "official");
        assert!(idols.sorts.iter().any(|s| s.key == idols.default_sort));
    }

    #[test]
    fn brands_and_attributes_come_only_from_the_idols_in_the_list() {
        let snap = crate::test_support::bundle_snapshot();
        let all = crate::domain::idol_list_filtering::idol_list_entries(snap);
        let ml: Vec<IdolListEntry> = all.iter().filter(|e| e.brand_id == "ml").cloned().collect();
        assert!(!ml.is_empty(), "ミリオンのアイドルが居ないと確かめたことにならない");

        // 一覧に居ないブランドは、選べても 0 件になるだけなので出さない。
        let brands: Vec<String> = idol_facets(snap, &ml).brands.into_iter().map(|b| b.value).collect();
        assert_eq!(brands, ["ml"]);
        assert_eq!(song_facets(snap, &ml).brands, idol_facets(snap, &ml).brands);

        // 属性はその一覧に出てくるものだけ (ブランドごとに語彙が違う)。
        let attributes: Vec<String> = idol_facets(snap, &ml).attributes.into_iter().map(|a| a.value).collect();
        let mut want: Vec<String> = ml.iter().filter_map(|e| e.attribute.clone()).filter(|a| !a.is_empty()).collect();
        want.sort();
        want.dedup();
        assert_eq!(attributes, want);

        // 全員を渡せば、ブランドはアプリのピッカーの並びのまま全部出る。
        let every: Vec<String> = idol_facets(snap, &all).brands.into_iter().map(|b| b.value).collect();
        let picker: Vec<String> = idol_queries::brand_records(snap)
            .into_iter()
            .map(|b| b.id)
            .filter(|id| all.iter().any(|e| &e.brand_id == id))
            .collect();
        assert_eq!(every, picker);
        assert!(every.len() > 1);
    }

    #[test]
    fn song_types_are_those_the_list_actually_has_in_vocabulary_order() {
        let snap = crate::test_support::bundle_snapshot();
        let listed = filter_song_indexes(snap, &SongQuery::default().to_filter());
        let got: Vec<String> = song_facets(snap, &[]).song_types.into_iter().map(|t| t.value).collect();
        assert!(!got.is_empty());
        // 語彙の並びの部分列で、どの種別も一覧に 1 曲以上ある (選んで 0 件の選択肢を出さない)。
        let order: Vec<&str> =
            vocabulary::SONG_TYPES.iter().map(|t| t.value).filter(|v| got.iter().any(|g| g == v)).collect();
        assert_eq!(got, order);
        for t in &got {
            assert!(listed.iter().any(|&i| snap.songs[i as usize].song_type.as_deref() == Some(t.as_str())), "{t}");
        }
    }
}
