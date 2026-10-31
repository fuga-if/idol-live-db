//! 歌詞の投稿状況: 歌詞が公開された曲が、投稿を受け付けている曲のうち何曲あるか (全体とブランド別)。
//!
//! 投稿を呼びかける画面 (iOS「歌詞の投稿状況」) が使う。どの曲に歌詞があるかは端末のマスタに無いので、
//! サーバの公開曲 id (`GET /lyrics/published`) を受け取ってスナップショットと突き合わせる。
//!
//! - 母数は「歌詞を投稿できる曲」([`submission_allowed`]) のうち、曲一覧に出る曲 (派生曲を除く。
//!   [`crate::domain::song_detail_queries::listable_song_records_by_ids`] と同じ線)。
//!   ブランドの無い曲は行を立てられないので数えない。
//! - 公開数は母数に入る曲だけ数える (割合が 100% を超えないように)。
//! - ブランドは表示順 (`sort_order`)。投稿できる曲が 0 のブランド (その他) は載せない。
//! - [`lyric_song_ids`] は数えた「歌詞のある曲」そのものの一覧 (画面の数と一覧の行数を一致させる)。

use std::collections::HashSet;

use crate::domain::lyric_submission::submission_allowed;
use crate::domain::snapshot::Snapshot;

/// ブランド 1 つの歌詞の投稿状況。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct BrandLyricCoverageRecord {
    pub brand_id: String,
    pub short_name: String,
    pub color: Option<String>,
    /// 歌詞が公開されている曲の数。
    pub published: u32,
    /// 歌詞を投稿できる曲の数。
    pub eligible: u32,
    /// `published / eligible` (0.0〜1.0)。`eligible` が 0 なら 0。
    pub coverage: f64,
    /// 公開されている曲全体のうち、このブランドの曲が占める割合 (0.0〜1.0)。全体が 0 なら 0。
    pub share: f64,
}

/// 歌詞の投稿状況 1 画面分。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct LyricCoverageRecord {
    pub published: u32,
    pub eligible: u32,
    /// `published / eligible` (0.0〜1.0)。
    pub coverage: f64,
    pub brands: Vec<BrandLyricCoverageRecord>,
}

fn ratio(n: u32, d: u32) -> f64 {
    if d == 0 {
        0.0
    } else {
        n as f64 / d as f64
    }
}

/// 母数に入る曲か (派生曲・ブランド無し・投稿を受け付けない曲を除く)。数えるのも一覧もこれ 1 本。
fn counted_brand(snap: &Snapshot, s: &crate::domain::snapshot::Song) -> Option<u32> {
    if s.parent_song_id.is_some() {
        return None;
    }
    let brand_id = s.brand_id.as_deref()?;
    let &brand = snap.brand_index_by_id.get(brand_id)?;
    submission_allowed(brand_id, s.song_type.as_deref(), s.singer_label.as_deref()).then_some(brand)
}

/// 歌詞が公開されている曲の id 一覧 (「歌詞の投稿状況」の数と同じ母集合)。
///
/// `brand_id` を渡すとそのブランドだけ。並びはブランドの表示順 → 50 音 (title_kana、無ければ title)。
pub fn lyric_song_ids(snap: &Snapshot, published_song_ids: &[String], brand_id: Option<&str>) -> Vec<String> {
    let published_ids: HashSet<&str> = published_song_ids.iter().map(String::as_str).collect();
    let mut brand_rank = vec![u32::MAX; snap.brands.len()];
    for (rank, &b) in snap.brand_order.iter().enumerate() {
        brand_rank[b as usize] = rank as u32;
    }
    let mut hits: Vec<(u32, &str, &str)> = snap
        .songs
        .iter()
        .filter(|s| published_ids.contains(s.id.as_str()))
        .filter(|s| brand_id.is_none_or(|b| s.brand_id.as_deref() == Some(b)))
        .filter_map(|s| {
            let brand = counted_brand(snap, s)?;
            let key = s.title_kana.as_deref().unwrap_or(&s.title);
            Some((brand_rank[brand as usize], key, s.id.as_str()))
        })
        .collect();
    hits.sort();
    hits.into_iter().map(|(_, _, id)| id.to_string()).collect()
}

/// 歌詞の投稿状況を数える。`published_song_ids` はサーバが公開している曲の id (未知の id は無視する)。
pub fn lyric_coverage(snap: &Snapshot, published_song_ids: &[String]) -> LyricCoverageRecord {
    let published_ids: HashSet<&str> = published_song_ids.iter().map(String::as_str).collect();
    let mut eligible = vec![0u32; snap.brands.len()];
    let mut published = vec![0u32; snap.brands.len()];
    for s in &snap.songs {
        let Some(brand) = counted_brand(snap, s) else {
            continue;
        };
        eligible[brand as usize] += 1;
        if published_ids.contains(s.id.as_str()) {
            published[brand as usize] += 1;
        }
    }
    let total_published: u32 = published.iter().sum();
    let total_eligible: u32 = eligible.iter().sum();
    let brands = snap
        .brand_order
        .iter()
        .filter(|&&brand| eligible[brand as usize] > 0)
        .map(|&brand| {
            let b = &snap.brands[brand as usize];
            let (p, e) = (published[brand as usize], eligible[brand as usize]);
            BrandLyricCoverageRecord {
                brand_id: b.id.clone(),
                short_name: b.short_name.clone(),
                color: b.color.clone(),
                published: p,
                eligible: e,
                coverage: ratio(p, e),
                share: ratio(p, total_published),
            }
        })
        .collect();
    LyricCoverageRecord {
        published: total_published,
        eligible: total_eligible,
        coverage: ratio(total_published, total_eligible),
        brands,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    fn id_where(snap: &Snapshot, f: impl Fn(&crate::domain::snapshot::Song) -> bool) -> String {
        snap.songs
            .iter()
            .find(|s| f(s))
            .expect("条件に合う曲がある")
            .id
            .clone()
    }

    #[test]
    fn counts_only_listable_submittable_songs() {
        let snap = bundle_snapshot();
        let original = id_where(snap, |s| {
            s.parent_song_id.is_none()
                && s.brand_id.as_deref() == Some("sidem")
                && submission_allowed("sidem", s.song_type.as_deref(), s.singer_label.as_deref())
        });
        let cover = id_where(snap, |s| {
            s.parent_song_id.is_none() && s.song_type.as_deref() == Some("cover")
        });
        let derived = id_where(snap, |s| s.parent_song_id.is_some());
        let other = id_where(snap, |s| s.brand_id.as_deref() == Some("other"));
        let ids = vec![
            original.clone(),
            original,
            cover,
            derived,
            other,
            "no_such_song".into(),
        ];

        let r = lyric_coverage(snap, &ids);
        assert_eq!(
            r.published, 1,
            "カバー・派生曲・その他・未知の id は数えない"
        );
        let sidem = r.brands.iter().find(|b| b.brand_id == "sidem").unwrap();
        assert_eq!(sidem.published, 1);
        assert_eq!(sidem.share, 1.0);
        assert!((sidem.coverage - 1.0 / sidem.eligible as f64).abs() < 1e-12);
        assert_eq!(r.eligible, r.brands.iter().map(|b| b.eligible).sum::<u32>());
        assert!(r
            .brands
            .iter()
            .all(|b| b.brand_id != "other" && b.eligible > 0));
    }

    #[test]
    fn song_ids_match_counts_and_order() {
        let snap = bundle_snapshot();
        // 公開扱いにする曲: 各ブランドの数曲 + 数えない曲 (派生曲・その他・未知の id)。
        let mut ids: Vec<String> = snap.songs.iter().step_by(7).map(|s| s.id.clone()).collect();
        ids.push(id_where(snap, |s| s.parent_song_id.is_some()));
        ids.push("no_such_song".into());

        let r = lyric_coverage(snap, &ids);
        let all = lyric_song_ids(snap, &ids, None);
        assert_eq!(all.len() as u32, r.published, "一覧の行数は「歌詞あり」の数と一致する");
        for b in &r.brands {
            let one = lyric_song_ids(snap, &ids, Some(&b.brand_id));
            assert_eq!(one.len() as u32, b.published, "{} の行数", b.brand_id);
            assert!(one.iter().all(|id| snap.song(id).unwrap().brand_id.as_deref() == Some(b.brand_id.as_str())));
        }
        // ブランドの表示順に並ぶ (同じブランドが飛び飛びにならない)。
        let brands: Vec<&str> = all.iter().map(|id| snap.song(id).unwrap().brand_id.as_deref().unwrap()).collect();
        let mut seen: Vec<&str> = vec![];
        for b in brands {
            if seen.last() != Some(&b) {
                assert!(!seen.contains(&b), "{b} が飛び飛び");
                seen.push(b);
            }
        }
        let want: Vec<&str> = r.brands.iter().filter(|b| b.published > 0).map(|b| b.brand_id.as_str()).collect();
        assert_eq!(seen, want);
        assert!(lyric_song_ids(snap, &[], None).is_empty());
    }

    #[test]
    fn brands_follow_display_order_and_empty_is_zero() {
        let snap = bundle_snapshot();
        let r = lyric_coverage(snap, &[]);
        assert_eq!((r.published, r.coverage), (0, 0.0));
        assert!(r.eligible > 0);
        let order: Vec<&str> = snap
            .brand_order
            .iter()
            .map(|&b| snap.brands[b as usize].id.as_str())
            .filter(|id| r.brands.iter().any(|b| b.brand_id == *id))
            .collect();
        let got: Vec<&str> = r.brands.iter().map(|b| b.brand_id.as_str()).collect();
        assert_eq!(got, order);
        assert!(r.brands.iter().all(|b| b.share == 0.0 && b.coverage == 0.0));
    }
}
