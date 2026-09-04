//! 楽曲一覧の絞り込み素材 (`index/songs-filter*.json`)。
//!
//! ブラウザは静的サイトなので core を実行できない (uniffi と SQLite を必須依存に
//! 持つため、クレート丸ごとの wasm 化は成立しない)。そこで**絞り込みの判断は
//! ここで済ませ、受け手には「どの行がどの値に属するか」と「並び順そのもの」だけ**を
//! 渡す。ブラウザがやるのは軸をまたいだ積 (AND)・軸内の和 (OR) と、渡された順列を
//! 当てることだけで、条件も並び順の規則も持たない。
//!
//! 各値の行集合は **core 自身のフィルタ (`song_list_indexes`) に計算させる**。
//! ここで条件を書き直すと、アプリと web で絞り込み結果が食い違う余地ができる。
//! 軸ごとの集合の積が元のフィルタと一致するのは、`SongListFilter` が独立な述語の
//! 論理積だから (`filters_compose` のテストで固定してある)。
//!
//! 自由入力 (曲名など) は事前計算できないので、行ごとの照合対象 (`haystacks`) を
//! 渡して判定はブラウザに任せる。ただし**畳むのは Rust 側**で、載せるのは
//! `Snapshot` が読み込み時に組んだ `TextSearchIndex` の写し (`emit::search` と同じ流儀)。
//! どのフィールドが照合対象かという判断がコアの外に漏れないようにするため。
//! ブラウザは検索語だけを同じ `imas-text-fold` の wasm で畳んで部分一致を見る。

use std::collections::{BTreeMap, HashMap};

use crate::domain::snapshot::Snapshot;
use crate::domain::text_search_index::TextSearchIndex;
use crate::domain::song_list_queries::{song_list_indexes, SongListFilter, SongListSort};
use crate::web_export::dto::index::{SongFacet, SongFacetValue, SongListFilterData, SongListOrder};
use crate::web_export::dto::SCHEMA_VERSION;

/// 一覧 1 枚ぶんの絞り込み素材を組む。
///
/// `base` はその一覧を作ったときのフィルタ。ファセットはこの土台の上に 1 条件だけ
/// 足した結果で作るので、「その一覧に実際に並んでいる行」だけが対象になる。
/// `rows` は `SongListPage.items` と同じ並びの曲添字列。
pub fn song_filter_data(
    snap: &Snapshot,
    path: &str,
    base: &SongListFilter,
    rows: &[u32],
) -> SongListFilterData {
    // 曲添字 → 行番号。core が返す添字を受け手の行番号へ移すのに使う。
    let row_of: HashMap<u32, u32> =
        rows.iter().enumerate().map(|(i, &song)| (song, i as u32)).collect();

    let facets = vec![
        brand_facet(snap, path, base, &row_of),
        song_type_facet(snap, base, &row_of),
        artist_facet(snap, base, &row_of),
        cd_series_facet(snap, base, &row_of),
        series_group_facet(snap, base, &row_of),
    ]
    .into_iter()
    .flatten()
    .collect();

    SongListFilterData {
        schema_version: SCHEMA_VERSION,
        path: path.to_string(),
        row_count: rows.len() as u32,
        facets,
        orders: orders(snap, base, &row_of, rows.len()),
        // 区切りは検索索引と同じ U+0001。検索語に入り得ないので、
        // フィールド境界をまたいだ偽陽性が起きない。
        separator: super::search::SEP.to_string(),
        haystacks: rows.iter().map(|&i| folded(&snap.song_search[i as usize])).collect(),
    }
}

/// 並べ替え。**昇順と降順の両方を持つ。** 受け手が片方を反転すると、同着の並び
/// (元 SQL の 2 列目) まで裏返ってアプリと違う順になる。
///
/// 回収系 (CollectedCount / CollectedRate) は個人データが要るので web には出さない。
fn orders(
    snap: &Snapshot,
    base: &SongListFilter,
    row_of: &HashMap<u32, u32>,
    row_count: usize,
) -> Vec<SongListOrder> {
    [
        (SongListSort::TitleKana, "kana", "五十音順"),
        (SongListSort::ReleaseDate, "release", "リリース日順"),
        (SongListSort::PerformanceCount, "performance", "披露回数順"),
    ]
    .into_iter()
    .map(|(sort, key, label)| {
        let run = |asc: bool| -> Vec<u32> {
            let indexes = song_list_indexes(snap, base, sort, Some(asc), &[], &[]);
            let mapped: Vec<u32> = indexes.iter().filter_map(|i| row_of.get(i).copied()).collect();
            debug_assert_eq!(mapped.len(), row_count, "並べ替えが行を落とした: {key}");
            mapped
        };
        SongListOrder {
            key: key.to_string(),
            label: label.to_string(),
            default_ascending: sort.default_ascending(),
            ascending: run(true),
            descending: run(false),
        }
    })
    .collect()
}

/// 1 条件だけ足したときに残る行を、core のフィルタに計算させる。
fn rows_matching(
    snap: &Snapshot,
    base: &SongListFilter,
    row_of: &HashMap<u32, u32>,
    tweak: impl FnOnce(&mut SongListFilter),
) -> Vec<u32> {
    let mut filter = base.clone();
    tweak(&mut filter);
    let mut rows: Vec<u32> = song_list_indexes(snap, &filter, SongListSort::TitleKana, None, &[], &[])
        .iter()
        .filter_map(|i| row_of.get(i).copied())
        .collect();
    rows.sort_unstable();
    rows
}

/// 値ごとの行集合から軸を組む。1 件も無い値と、全行に当たる値は落とす
/// (どちらも絞り込みの役に立たない)。
fn build_facet(
    key: &str,
    label: &str,
    multi: bool,
    row_count: usize,
    entries: Vec<(String, String, Vec<u32>)>,
) -> Option<SongFacet> {
    let kept: Vec<(String, String, Vec<u32>)> = entries
        .into_iter()
        .filter(|(_, _, rows)| !rows.is_empty() && rows.len() < row_count)
        .collect();
    if kept.len() < 2 {
        return None;
    }
    let values = kept
        .iter()
        .map(|(value, label, rows)| SongFacetValue {
            value: value.clone(),
            label: label.clone(),
            count: rows.len() as u32,
        })
        .collect();
    // 行 → 値添字。受け手は行ごとの列だけ見れば済む。
    let mut row_values: Vec<Vec<u32>> = vec![Vec::new(); row_count];
    for (vi, (_, _, rows)) in kept.iter().enumerate() {
        for &r in rows {
            row_values[r as usize].push(vi as u32);
        }
    }
    Some(SongFacet {
        key: key.to_string(),
        label: label.to_string(),
        multi,
        values,
        row_values,
    })
}

fn brand_facet(
    snap: &Snapshot,
    path: &str,
    base: &SongListFilter,
    row_of: &HashMap<u32, u32>,
) -> Option<SongFacet> {
    // ブランド別ページは既に 1 ブランドに絞れているので、この軸は出さない。
    if path.contains("/brand/") {
        return None;
    }
    let entries = snap
        .brands
        .iter()
        .map(|brand| {
            let rows = rows_matching(snap, base, row_of, |f| {
                f.brand_ids = vec![brand.id.clone()];
            });
            (brand.id.clone(), brand.name.clone(), rows)
        })
        .collect();
    build_facet("brand", "ブランド", true, row_of.len(), entries)
}

fn song_type_facet(
    snap: &Snapshot,
    base: &SongListFilter,
    row_of: &HashMap<u32, u32>,
) -> Option<SongFacet> {
    let entries = [("all", "全体曲"), ("unit", "ユニット曲"), ("solo", "ソロ曲")]
        .into_iter()
        .map(|(value, label)| {
            let rows = rows_matching(snap, base, row_of, |f| {
                f.song_type = Some(value.to_string());
            });
            (value.to_string(), label.to_string(), rows)
        })
        .collect();
    build_facet("songType", "曲種別", false, row_of.len(), entries)
}

fn artist_facet(
    snap: &Snapshot,
    base: &SongListFilter,
    row_of: &HashMap<u32, u32>,
) -> Option<SongFacet> {
    let entries = snap
        .idols
        .iter()
        .map(|idol| {
            let rows = rows_matching(snap, base, row_of, |f| {
                f.idol_ids = vec![idol.id.clone()];
            });
            (idol.id.clone(), idol.name.clone(), rows)
        })
        .collect();
    build_facet("artist", "原唱者", true, row_of.len(), entries)
}

fn cd_series_facet(
    snap: &Snapshot,
    base: &SongListFilter,
    row_of: &HashMap<u32, u32>,
) -> Option<SongFacet> {
    let entries = distinct(snap, row_of, |s| s.cd_series.as_deref())
        .into_iter()
        .map(|name| {
            let rows = rows_matching(snap, base, row_of, |f| f.cd_series = Some(name.clone()));
            (name.clone(), name, rows)
        })
        .collect();
    build_facet("cdSeries", "CD シリーズ", false, row_of.len(), entries)
}

fn series_group_facet(
    snap: &Snapshot,
    base: &SongListFilter,
    row_of: &HashMap<u32, u32>,
) -> Option<SongFacet> {
    let entries = distinct(snap, row_of, |s| s.series_group.as_deref())
        .into_iter()
        .map(|name| {
            let rows = rows_matching(snap, base, row_of, |f| f.series_group = Some(name.clone()));
            (name.clone(), name, rows)
        })
        .collect();
    build_facet("seriesGroup", "シリーズ", false, row_of.len(), entries)
}

/// その一覧に並んでいる行から、指定列の相異なる値を集める (出現順ではなく辞書順)。
fn distinct(
    snap: &Snapshot,
    row_of: &HashMap<u32, u32>,
    pick: impl Fn(&crate::domain::snapshot::Song) -> Option<&str>,
) -> Vec<String> {
    let mut set: BTreeMap<String, ()> = BTreeMap::new();
    for &song_index in row_of.keys() {
        if let Some(v) = pick(&snap.songs[song_index as usize]) {
            if !v.is_empty() {
                set.insert(v.to_string(), ());
            }
        }
    }
    set.into_keys().collect()
}

/// 索引の畳み済みフィールドを 1 本に連ねる (`emit::search::folded` と同じ)。
fn folded(index: &TextSearchIndex) -> String {
    index.folded_str_fields().join(super::search::SEP)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::outbound::sqlite_loader::load_snapshot;
    use std::sync::OnceLock;

    fn snap() -> &'static Snapshot {
        static SNAP: OnceLock<Snapshot> = OnceLock::new();
        SNAP.get_or_init(|| {
            let path = format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"));
            load_snapshot(&path).expect("bundle DB はロードできる")
        })
    }

    fn base() -> SongListFilter {
        SongListFilter {
            include_remixes: false,
            include_other_brand: false,
            exclude_live_only: true,
            ..SongListFilter::default()
        }
    }

    fn rows() -> Vec<u32> {
        song_list_indexes(snap(), &base(), SongListSort::TitleKana, None, &[], &[])
    }

    /// **この出面の絞り込みが成り立つ根拠。**
    ///
    /// ブラウザは軸ごとの行集合の積を取るだけで、条件を組み直さない。それが
    /// 「条件を全部入れて core のフィルタを 1 回走らせた結果」と一致することを固定する。
    /// 一致しなくなったら (= `SongListFilter` に述語間の相互作用が入ったら)、
    /// 積で代用する前提が崩れるのでここで落とす。
    #[test]
    fn 軸ごとの積は条件をまとめて掛けた結果と一致する() {
        let rows = rows();
        let row_of: std::collections::HashMap<u32, u32> =
            rows.iter().enumerate().map(|(i, &s)| (s, i as u32)).collect();

        let brand = "ml";
        let song_type = "solo";
        let idol = snap()
            .idols
            .iter()
            .find(|i| i.brand_id.as_deref() == Some(brand))
            .expect("ミリオンのアイドルが居る");

        let a = rows_matching(snap(), &base(), &row_of, |f| f.brand_ids = vec![brand.to_string()]);
        let b = rows_matching(snap(), &base(), &row_of, |f| f.song_type = Some(song_type.to_string()));
        let c = rows_matching(snap(), &base(), &row_of, |f| f.idol_ids = vec![idol.id.clone()]);

        let intersected: Vec<u32> = {
            let sa: std::collections::HashSet<u32> = a.iter().copied().collect();
            let sb: std::collections::HashSet<u32> = b.iter().copied().collect();
            let mut v: Vec<u32> = c
                .iter()
                .copied()
                .filter(|r| sa.contains(r) && sb.contains(r))
                .collect();
            v.sort_unstable();
            v
        };

        let combined = rows_matching(snap(), &base(), &row_of, |f| {
            f.brand_ids = vec![brand.to_string()];
            f.song_type = Some(song_type.to_string());
            f.idol_ids = vec![idol.id.clone()];
        });

        assert_eq!(intersected, combined, "軸ごとの積 != まとめて掛けた結果");
        assert!(!combined.is_empty(), "検体が空では等価性を確かめたことにならない");
    }

    /// 並べ替えは行を落とさない・重複させない (受け手はこの順列をそのまま当てる)。
    #[test]
    fn 並び順は行の順列になっている() {
        let rows = rows();
        let data = song_filter_data(snap(), "/songs/", &base(), &rows);
        assert!(!data.orders.is_empty());
        for order in &data.orders {
            for (dir, seq) in [("昇順", &order.ascending), ("降順", &order.descending)] {
                let mut sorted = seq.clone();
                sorted.sort_unstable();
                sorted.dedup();
                assert_eq!(
                    sorted.len(),
                    data.row_count as usize,
                    "{} の {dir} が行の順列になっていない",
                    order.key
                );
            }
        }
    }

    /// 照合対象は検索索引の写しで、区切りは検索語に入り得ない文字であること。
    #[test]
    fn 照合対象は行数ぶんあり区切りは制御文字() {
        let rows = rows();
        let data = song_filter_data(snap(), "/songs/", &base(), &rows);
        assert_eq!(data.haystacks.len(), data.row_count as usize);
        assert_eq!(data.separator, "\u{0001}");
        // 軸は「1 件も無い値」「全行に当たる値」を落としたうえで 2 値以上が残るものだけ。
        for facet in &data.facets {
            assert!(facet.values.len() >= 2, "{} の値が少なすぎる", facet.key);
            assert_eq!(facet.row_values.len(), data.row_count as usize, "{}", facet.key);
        }
    }
}
