//! みんなの集計 (お気に入り・再生回数) から曲の順位を出す規則。
//!
//! サーバ (`GET /community/song-stats`) は全曲の数を素のまま返すだけで、並べ方・ブランドの
//! 絞り込みはここで決める (曲のブランドの正は端末のマスタ。D1 に曲のミラーを持たせない)。
//!
//! 順位の種類 ([`CommunityRankingKind`]):
//! - 人気: お気に入り × [`POPULAR_FAVORITE_WEIGHT`] + フル再生 × [`FULL_PLAY_WEIGHT`] + 試聴。
//!   お気に入りは付けるのに意思が要るので重く見る。
//! - 急上昇: 今週 (JST の月曜始まり) の 1 日あたりの再生が、先週の 1 日あたりより
//!   どれだけ増えたか。再生はフル再生 × [`FULL_PLAY_WEIGHT`] + 試聴で数える。
//!   今週の再生が [`TRENDING_MIN_WEEK_PLAYS`] に満たない曲と、増えていない曲は出さない。
//! - お気に入り / 試聴 / フル再生: それぞれの数の多い順。0 は出さない。
//!
//! 同点は今週の再生の多い順 → 曲 id の順。

use crate::domain::jst_day::{jst, jst_midnight_epoch_seconds};
use chrono::{DateTime, Datelike, Duration, NaiveDate};
use serde_json::Value;

/// 人気の点でお気に入り 1 つが何回の試聴に当たるか。
pub const POPULAR_FAVORITE_WEIGHT: u64 = 10;
/// フル再生 1 回が何回の試聴に当たるか (人気・急上昇とも)。
pub const FULL_PLAY_WEIGHT: u64 = 2;
/// 急上昇に出すのに要る今週の再生 (重み付き)。
pub const TRENDING_MIN_WEEK_PLAYS: u64 = 3;

/// 順位の種類。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum CommunityRankingKind {
    Popular,
    Trending,
    Favorites,
    Preview,
    Full,
}

/// 1 曲の集計 (今週・先週はサーバの返した週を今の週に読み替え済み)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SongCommunityStat {
    pub song_id: String,
    pub favorites: u64,
    pub preview: u64,
    pub full: u64,
    pub week_preview: u64,
    pub week_full: u64,
    pub prev_week_preview: u64,
    pub prev_week_full: u64,
}

/// サーバの集計 1 回ぶん。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CommunityStats {
    /// 再生回数を数え始めた日 (`yyyy-MM-dd`。画面の「○月○日から集計」)。
    pub plays_since: String,
    /// 今週の月曜 (`yyyy-MM-dd`、JST)。
    pub current_week: String,
    /// 今週の何日目か (月曜 = 1 … 日曜 = 7)。
    pub days_into_week: u32,
    pub songs: Vec<SongCommunityStat>,
}

/// 順位表の 1 行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct RankedSong {
    pub rank: u32,
    pub song_id: String,
    /// その順位表で見せる数 (人気は点、急上昇は今週の再生回数 (試聴+フル)、ほかはその数)。
    pub value: u64,
    pub favorites: u64,
    pub preview: u64,
    pub full: u64,
}

/// `epoch` (秒) の JST の週の月曜。
pub fn week_of(epoch_seconds: i64) -> String {
    let day = DateTime::from_timestamp(epoch_seconds, 0)
        .unwrap_or(DateTime::UNIX_EPOCH)
        .with_timezone(&jst())
        .date_naive();
    let monday = day - Duration::days(day.weekday().num_days_from_monday() as i64);
    monday.format("%Y-%m-%d").to_string()
}

fn prev_week(week: &str) -> Option<String> {
    let d = NaiveDate::parse_from_str(week, "%Y-%m-%d").ok()?;
    Some((d - Duration::days(7)).format("%Y-%m-%d").to_string())
}

/// `GET /community/song-stats` の応答を読む。形が違えば `None`。
///
/// 応答の各曲は「最後に数えた週 (`week`)」とその週・前の週の数を持つ。その週が
/// 今週なら今週・先週として、先週なら先週として読み、もっと前なら 0 とする
/// (サーバは再生が来たときにしか週を送らないので、しばらく聴かれていない曲は古い週のまま)。
pub fn parse_stats(json: &str) -> Option<CommunityStats> {
    let obj = serde_json::from_str::<Value>(json).ok()?;
    let generated_at = obj.get("generated_at")?.as_i64()?;
    let current_week = week_of(generated_at);
    let last_week = prev_week(&current_week)?;
    let monday = jst_midnight_epoch_seconds(&current_week)?;
    let days_into_week = (((generated_at - monday) / 86_400) + 1).clamp(1, 7) as u32;
    let plays_since = obj.get("plays_since").and_then(Value::as_str).unwrap_or_default().to_string();
    let n = |v: &Value, k: &str| v.get(k).and_then(Value::as_u64).unwrap_or(0);
    let songs = obj
        .get("songs")?
        .as_array()?
        .iter()
        .filter_map(|s| {
            let song_id = s.get("song_id")?.as_str().filter(|id| !id.is_empty())?.to_string();
            let week = s.get("week").and_then(Value::as_str).unwrap_or_default();
            let (wp, wf, pp, pf) = (
                n(s, "week_preview"),
                n(s, "week_full"),
                n(s, "prev_week_preview"),
                n(s, "prev_week_full"),
            );
            let (week_preview, week_full, prev_week_preview, prev_week_full) = if week == current_week {
                (wp, wf, pp, pf)
            } else if week == last_week {
                (0, 0, wp, wf)
            } else {
                (0, 0, 0, 0)
            };
            Some(SongCommunityStat {
                song_id,
                favorites: n(s, "favorites"),
                preview: n(s, "preview"),
                full: n(s, "full"),
                week_preview,
                week_full,
                prev_week_preview,
                prev_week_full,
            })
        })
        .collect();
    Some(CommunityStats { plays_since, current_week, days_into_week, songs })
}

fn weighted(preview: u64, full: u64) -> u64 {
    preview.saturating_add(full.saturating_mul(FULL_PLAY_WEIGHT))
}

/// 人気の点。
pub fn popular_score(s: &SongCommunityStat) -> u64 {
    s.favorites.saturating_mul(POPULAR_FAVORITE_WEIGHT).saturating_add(weighted(s.preview, s.full))
}

/// 急上昇の伸び (1 日あたりの重み付き再生の、先週からの増分)。出さない曲は `None`。
fn trending_growth(s: &SongCommunityStat, days_into_week: u32) -> Option<f64> {
    let week = weighted(s.week_preview, s.week_full);
    if week < TRENDING_MIN_WEEK_PLAYS {
        return None;
    }
    let growth = week as f64 / days_into_week.max(1) as f64
        - weighted(s.prev_week_preview, s.prev_week_full) as f64 / 7.0;
    (growth > 0.0).then_some(growth)
}

/// 順位表を作る。`in_scope` はマスタにある曲で、選んだブランドに入るか
/// (端末のマスタで決める。マスタに無い曲は出さない)。`limit` までで切る。
pub fn rank(
    stats: &CommunityStats,
    kind: CommunityRankingKind,
    in_scope: impl Fn(&str) -> bool,
    limit: usize,
) -> Vec<RankedSong> {
    // (並べる鍵, 見せる数, 曲)
    let mut rows: Vec<(f64, u64, &SongCommunityStat)> = stats
        .songs
        .iter()
        .filter(|s| in_scope(&s.song_id))
        .filter_map(|s| {
            let week_plays = s.week_preview.saturating_add(s.week_full);
            let (key, value) = match kind {
                CommunityRankingKind::Popular => {
                    let p = popular_score(s);
                    (p as f64, p)
                }
                CommunityRankingKind::Trending => (trending_growth(s, stats.days_into_week)?, week_plays),
                CommunityRankingKind::Favorites => (s.favorites as f64, s.favorites),
                CommunityRankingKind::Preview => (s.preview as f64, s.preview),
                CommunityRankingKind::Full => (s.full as f64, s.full),
            };
            (key > 0.0).then_some((key, value, s))
        })
        .collect();
    rows.sort_by(|a, b| {
        b.0.total_cmp(&a.0)
            .then_with(|| weighted(b.2.week_preview, b.2.week_full).cmp(&weighted(a.2.week_preview, a.2.week_full)))
            .then_with(|| a.2.song_id.cmp(&b.2.song_id))
    });
    rows.into_iter()
        .take(limit)
        .enumerate()
        .map(|(i, (_, value, s))| RankedSong {
            rank: i as u32 + 1,
            song_id: s.song_id.clone(),
            value,
            favorites: s.favorites,
            preview: s.preview,
            full: s.full,
        })
        .collect()
}

/// 1 曲の集計 (曲詳細用)。載っていなければ全部 0。
pub fn stat_for(stats: &CommunityStats, song_id: &str) -> SongCommunityStat {
    stats.songs.iter().find(|s| s.song_id == song_id).cloned().unwrap_or(SongCommunityStat {
        song_id: song_id.to_string(),
        favorites: 0,
        preview: 0,
        full: 0,
        week_preview: 0,
        week_full: 0,
        prev_week_preview: 0,
        prev_week_full: 0,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 2026-10-21 (水) 12:00 JST。今週の月曜は 10-19、先週は 10-12。
    const WED_NOON: i64 = 1_792_551_600;

    fn stat(id: &str, fav: u64, preview: u64, full: u64, week: (u64, u64), prev: (u64, u64)) -> SongCommunityStat {
        SongCommunityStat {
            song_id: id.into(),
            favorites: fav,
            preview,
            full,
            week_preview: week.0,
            week_full: week.1,
            prev_week_preview: prev.0,
            prev_week_full: prev.1,
        }
    }

    fn stats(songs: Vec<SongCommunityStat>, days: u32) -> CommunityStats {
        CommunityStats { plays_since: "2026-10-20".into(), current_week: "2026-10-19".into(), days_into_week: days, songs }
    }

    fn ids(rows: &[RankedSong]) -> Vec<&str> {
        rows.iter().map(|r| r.song_id.as_str()).collect()
    }

    #[test]
    fn 週はjstの月曜始まり() {
        assert_eq!(week_of(WED_NOON), "2026-10-19");
        // 2026-10-19 00:00 JST ちょうどは今週、その 1 秒前は先週
        let monday = jst_midnight_epoch_seconds("2026-10-19").unwrap();
        assert_eq!(week_of(monday), "2026-10-19");
        assert_eq!(week_of(monday - 1), "2026-10-12");
    }

    #[test]
    fn 応答の週を今週と先週に読み替える() {
        let json = format!(
            r#"{{"generated_at":{WED_NOON},"plays_since":"2026-10-20","songs":[
              {{"song_id":"now","favorites":2,"preview":10,"full":5,"week":"2026-10-19","week_preview":3,"week_full":1,"prev_week_preview":4,"prev_week_full":2}},
              {{"song_id":"last","preview":1,"week":"2026-10-12","week_preview":7,"week_full":8,"prev_week_preview":9,"prev_week_full":9}},
              {{"song_id":"old","week":"2026-09-01","week_preview":7}},
              {{"song_id":"fav_only","favorites":4}},
              {{"song_id":""}}
            ]}}"#
        );
        let s = parse_stats(&json).unwrap();
        assert_eq!(s.current_week, "2026-10-19");
        assert_eq!(s.days_into_week, 3);
        assert_eq!(s.plays_since, "2026-10-20");
        assert_eq!(
            s.songs,
            vec![
                stat("now", 2, 10, 5, (3, 1), (4, 2)),
                stat("last", 0, 1, 0, (0, 0), (7, 8)),
                stat("old", 0, 0, 0, (0, 0), (0, 0)),
                stat("fav_only", 4, 0, 0, (0, 0), (0, 0)),
            ]
        );
        assert_eq!(parse_stats("{}"), None);
        assert_eq!(parse_stats("x"), None);
    }

    #[test]
    fn 人気はお気に入りを重く見る() {
        let s = stats(vec![stat("fav", 1, 0, 0, (0, 0), (0, 0)), stat("play", 0, 5, 2, (0, 0), (0, 0))], 1);
        let r = rank(&s, CommunityRankingKind::Popular, |_| true, 10);
        assert_eq!(ids(&r), vec!["fav", "play"]);
        assert_eq!(r[0].value, 10);
        assert_eq!(r[1].value, 9);
        assert_eq!(r[1].rank, 2);
    }

    #[test]
    fn 急上昇は1日あたりの伸びで_少ない曲と減った曲は出さない() {
        let s = stats(
            vec![
                // 水曜 (3 日目) までに 6 → 1 日 2、先週は 1 日 1 → +1
                stat("up", 0, 0, 0, (6, 0), (7, 0)),
                // 今週 1 日 4、先週 0 → +4
                stat("new", 0, 0, 0, (0, 6), (0, 0)),
                // 少なすぎる
                stat("few", 0, 0, 0, (2, 0), (0, 0)),
                // 減った
                stat("down", 0, 0, 0, (6, 0), (70, 0)),
            ],
            3,
        );
        let r = rank(&s, CommunityRankingKind::Trending, |_| true, 10);
        assert_eq!(ids(&r), vec!["new", "up"]);
        // 見せる数は今週の再生回数 (重みなし)
        assert_eq!(r[0].value, 6);
    }

    #[test]
    fn 数の順位は0を出さず_同点は今週の再生と曲idで決める() {
        let s = stats(
            vec![
                stat("b", 0, 3, 0, (0, 0), (0, 0)),
                stat("a", 0, 3, 0, (0, 0), (0, 0)),
                stat("hot", 0, 3, 0, (1, 0), (0, 0)),
                stat("zero", 5, 0, 1, (0, 0), (0, 0)),
            ],
            1,
        );
        assert_eq!(ids(&rank(&s, CommunityRankingKind::Preview, |_| true, 10)), vec!["hot", "a", "b"]);
        assert_eq!(ids(&rank(&s, CommunityRankingKind::Full, |_| true, 10)), vec!["zero"]);
        assert_eq!(ids(&rank(&s, CommunityRankingKind::Favorites, |_| true, 10)), vec!["zero"]);
    }

    #[test]
    fn 範囲外の曲を除き上限で切る() {
        let s = stats(
            vec![stat("a", 3, 0, 0, (0, 0), (0, 0)), stat("b", 2, 0, 0, (0, 0), (0, 0)), stat("c", 1, 0, 0, (0, 0), (0, 0))],
            1,
        );
        let r = rank(&s, CommunityRankingKind::Favorites, |id| id != "a", 1);
        assert_eq!(ids(&r), vec!["b"]);
        assert_eq!(r[0].rank, 1);
    }

    #[test]
    fn 載っていない曲の集計は0() {
        let s = stats(vec![stat("a", 3, 1, 2, (0, 0), (0, 0))], 1);
        assert_eq!(stat_for(&s, "a").full, 2);
        assert_eq!(stat_for(&s, "x"), stat("x", 0, 0, 0, (0, 0), (0, 0)));
    }
}
