//! アイドル詳細の「次の出演」と「タグが似ているアイドル」の決め方。
//!
//! 両 OS に写経されていた (iOS `IdolDetailView.nextShow` / `loadSimilarIdols`、
//! Android `IdolDetailUiState.nextShow` / `IdolDetailViewModel.loadSimilarIdols`)。

use crate::domain::event_grouping::is_upcoming_on;
use crate::domain::snapshot::Snapshot;

/// 出演公演の日付 (`YYYY-MM-DD`) から「次の出演」を選ぶ: 今日 (JST) 以降でいちばん早いもの。
/// 同じ日が並べば先に来た方。無ければ `None`。「今日以降か」の判断は
/// [`is_upcoming_on`] (日付の精度をそろえて比べる) に任せる。
pub fn next_show_index(dates: &[String], today_key: &str) -> Option<u32> {
    dates
        .iter()
        .enumerate()
        .filter(|(_, date)| is_upcoming_on(date, today_key))
        .min_by(|(ia, a), (ib, b)| a.cmp(b).then(ia.cmp(ib)))
        .map(|(i, _)| i as u32)
}

/// サーバに頼む「タグが似ているアイドル」の件数。外部ゲストを端末で除くと減るので、
/// 出す件数より多めに頼む (サーバの D1 には idols が無く、is_external で絞れない)。
pub const SIMILAR_IDOLS_FETCH_LIMIT: u32 = 25;

/// 画面に出す「タグが似ているアイドル」の件数。
pub const SIMILAR_IDOLS_DISPLAY_LIMIT: usize = 10;

/// サーバが返した 1 件 (共有タグ数の多い順に並んでいる)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SimilarIdolCandidate {
    pub idol_id: String,
    pub shared_tags: u32,
}

/// サーバが返した候補から、画面に出すものを選ぶ: 手元に無い id と外部ゲストを除き、
/// サーバの並び (共有タグ数の多い順) のまま先頭から 10 件。同じ id は最初の 1 件だけ。
pub fn pick_similar_idols(snap: &Snapshot, candidates: &[SimilarIdolCandidate]) -> Vec<SimilarIdolCandidate> {
    let mut seen = std::collections::HashSet::new();
    candidates
        .iter()
        .filter(|c| {
            snap.idol_index_by_id
                .get(&c.idol_id)
                .is_some_and(|&i| !snap.idols[i as usize].is_external)
        })
        .filter(|c| seen.insert(c.idol_id.as_str()))
        .take(SIMILAR_IDOLS_DISPLAY_LIMIT)
        .cloned()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    fn dates(values: &[&str]) -> Vec<String> {
        values.iter().map(|v| v.to_string()).collect()
    }

    #[test]
    fn next_show_is_the_earliest_on_or_after_today() {
        let d = dates(&["2026-09-30", "2026-09-20", "2026-09-23", "2026-10-05"]);
        assert_eq!(next_show_index(&d, "2026-09-23"), Some(2), "今日の公演は次の出演");
        assert_eq!(next_show_index(&d, "2026-09-24"), Some(0));
        assert_eq!(next_show_index(&d, "2026-11-01"), None);
        assert_eq!(next_show_index(&[], "2026-09-23"), None);
    }

    #[test]
    fn similar_idols_drop_unknown_and_external_and_keep_server_order() {
        let snap = bundle_snapshot();
        let external = snap.idols.iter().find(|i| i.is_external).expect("外部ゲストがいる");
        let members: Vec<&str> = snap
            .idols
            .iter()
            .filter(|i| !i.is_external)
            .take(12)
            .map(|i| i.id.as_str())
            .collect();
        let mut candidates = vec![
            SimilarIdolCandidate { idol_id: external.id.clone(), shared_tags: 9 },
            SimilarIdolCandidate { idol_id: "存在しない".into(), shared_tags: 8 },
        ];
        candidates.extend(members.iter().enumerate().map(|(n, id)| SimilarIdolCandidate {
            idol_id: id.to_string(),
            shared_tags: 7 - (n as u32).min(7),
        }));
        candidates.push(SimilarIdolCandidate { idol_id: members[0].to_string(), shared_tags: 1 });
        let picked = pick_similar_idols(snap, &candidates);
        assert_eq!(picked.len(), SIMILAR_IDOLS_DISPLAY_LIMIT);
        let ids: Vec<&str> = picked.iter().map(|c| c.idol_id.as_str()).collect();
        assert_eq!(ids, members[..SIMILAR_IDOLS_DISPLAY_LIMIT].to_vec(), "サーバの並びのまま");
        assert_eq!(picked[0].shared_tags, 7, "最初の 1 件の共有タグ数");
    }
}
