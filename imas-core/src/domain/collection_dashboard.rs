//! 統計タブの「回収ダッシュボード」: 回収率 (全体・ブランド別・担当のオリ曲)、未回収曲の一覧、
//! 「この公演で未回収が聴けるかも」。
//!
//! 両 OS に写経されていた (iOS `StatsView.loadDashboard` + `AppDatabase+UserMarks` の
//! `fetchBrandCollectionProgress` / `fetchLifetimePlayCounts` / `fetchUncollectedSongs` /
//! `fetchUpcomingCatchChances`、Android `StatsRepository.fetchCollectionDashboard`)。
//! Android は同点の並びが iOS と逆 (曲名かなの降順・公演日の降順) になっていた。
//!
//! 回収済みの曲 (参加したリアルライブのセトリの曲) は OS が持っている集合をそのまま受け取る
//! (参加マークは端末の DB にあり、一覧の回収バッジと同じ集合を使うため)。
//! 1 画面 = 1 FFI: 行の描画と遷移に要るもの (曲・公演の全列) も一緒に返す。

use std::collections::HashSet;

use crate::domain::collection_gap::is_real_live;
use crate::domain::event_detail_queries::{show_record_at, ShowRecord};
use crate::domain::event_grouping::is_upcoming_on;
use crate::domain::event_naming::event_short_name;
use crate::domain::idol_song_queries::song_ids_with_any_artist;
use crate::domain::snapshot::Snapshot;
use crate::domain::song_detail_queries::SongDetailRecord;

/// 「聴けるかも」の公演を何件まで出すか (両 OS の今の値)。
pub const DEFAULT_CATCH_CHANCE_LIMIT: u32 = 8;

/// リアルライブでの披露の多さ。未回収曲の札の文言と色の根拠。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum PlayFrequency {
    /// 10 回以上。
    Staple,
    /// 3 回以上。
    Sometimes,
    /// 1 回以上。
    Rare,
    /// まだ披露されていない。
    Never,
}

impl PlayFrequency {
    pub fn of(play_count: u32) -> Self {
        match play_count {
            10.. => Self::Staple,
            3.. => Self::Sometimes,
            1.. => Self::Rare,
            0 => Self::Never,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Staple => "定番",
            Self::Sometimes => "ときどき",
            Self::Rare => "レア",
            Self::Never => "未披露",
        }
    }
}

/// ブランド 1 つの回収率。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BrandCollectionProgressRecord {
    pub brand_id: String,
    pub short_name: String,
    pub color: Option<String>,
    /// 回収済みの曲のうち、`songs.brand_id` がこのブランドのもの。
    pub collected: u32,
    /// `songs.brand_id` がこのブランドの曲の数 (合同曲は主ブランドだけで数える)。
    pub total: u32,
}

/// 未回収の曲 1 つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct UncollectedSongRecord {
    pub song: SongDetailRecord,
    /// リアルライブ (`live` / `festival`) のセトリに載った回数 (同じ公演の再披露も数える)。
    pub play_count: u32,
    pub frequency: PlayFrequency,
    /// `定番` / `ときどき` / `レア` / `未披露`。
    pub frequency_label: String,
}

/// 今日以降のリアルライブの公演 1 つと、そこで聴けるかもしれない未回収曲の数。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CatchChanceRecord {
    pub show: ShowRecord,
    pub event_name: String,
    /// 作品名を落としたイベント名 (設定で省略するときに出す。[`event_short_name`])。
    pub event_short_name: String,
    /// 親イベントの `brand_id` (主ブランド)。
    pub brand_id: Option<String>,
    pub brand_color: Option<String>,
    /// 親イベントと同じ主ブランドのリアルライブで披露されたことのある未回収曲の異なり数 (1 以上)。
    pub likely_count: u32,
}

/// 回収ダッシュボード 1 画面分。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CollectionDashboardRecord {
    /// 回収済みのうち `brand_id` を持つ曲の数。
    pub overall_collected: u32,
    /// `brand_id` を持つ曲の数。
    pub overall_total: u32,
    /// ブランドの表示順 (`sort_order`)。曲の無いブランドも 0 / 0 で載る。
    pub brand_progress: Vec<BrandCollectionProgressRecord>,
    pub my_pick_collected: u32,
    /// 担当アイドルのいずれかが原唱者 (`role = original`) の曲の数。
    pub my_pick_total: u32,
    /// 担当のオリ曲のうち未回収のもの。披露回数の多い順 → 曲名かなの昇順 → 曲 id 順。
    pub pick_uncollected: Vec<UncollectedSongRecord>,
    /// `brand_id` を持つ曲のうち未回収のもの。並びは `pick_uncollected` と同じ。
    pub all_uncollected: Vec<UncollectedSongRecord>,
    /// 聴けるかもしれない数の多い順 → 公演日の昇順 → 公演の `sort_order` 順 → 公演 id 順。
    pub catch_chances: Vec<CatchChanceRecord>,
}

/// 回収ダッシュボードを組む。
///
/// - `collected_song_ids`: 回収済みの曲 (参加したリアルライブのセトリの曲)。未知の id は無視する。
/// - `pick_idol_ids`: 担当アイドル。
/// - `today`: JST の今日 (`YYYY-MM-DD`)。「今日以降」は [`is_upcoming_on`] で決める
///   (年・月だけの日付の公演も今年・今月なら入る)。
/// - `chance_limit`: 「聴けるかも」を何件まで返すか (今の画面は [`DEFAULT_CATCH_CHANCE_LIMIT`])。
pub fn collection_dashboard(
    snap: &Snapshot,
    collected_song_ids: &[String],
    pick_idol_ids: &[String],
    today: &str,
    chance_limit: u32,
) -> CollectionDashboardRecord {
    let mut collected = vec![false; snap.songs.len()];
    for id in collected_song_ids {
        if let Some(&song) = snap.song_index_by_id.get(id) {
            collected[song as usize] = true;
        }
    }

    let branded: Vec<u32> = (0..snap.songs.len() as u32)
        .filter(|&song| snap.songs[song as usize].brand_id.is_some())
        .collect();
    let pick: Vec<u32> = song_ids_with_any_artist(snap, pick_idol_ids)
        .iter()
        .filter_map(|id| snap.song_index_by_id.get(id).copied())
        .collect();
    let count_collected = |songs: &[u32]| songs.iter().filter(|&&song| collected[song as usize]).count() as u32;

    let play_counts = real_live_play_counts(snap);
    let uncollected_of = |songs: &[u32]| -> Vec<u32> {
        let mut rest: Vec<u32> = songs.iter().copied().filter(|&song| !collected[song as usize]).collect();
        rest.sort_by(|&a, &b| {
            let (sa, sb) = (&snap.songs[a as usize], &snap.songs[b as usize]);
            play_counts[b as usize]
                .cmp(&play_counts[a as usize])
                .then_with(|| sa.title_kana.as_deref().unwrap_or("").cmp(sb.title_kana.as_deref().unwrap_or("")))
                .then_with(|| sa.id.cmp(&sb.id))
        });
        rest
    };
    let all_uncollected = uncollected_of(&branded);
    let pick_uncollected = uncollected_of(&pick);
    let catch_chances = catch_chances(snap, &all_uncollected, today, chance_limit);
    let rows = |songs: &[u32]| -> Vec<UncollectedSongRecord> {
        songs
            .iter()
            .map(|&song| {
                let play_count = play_counts[song as usize];
                let frequency = PlayFrequency::of(play_count);
                UncollectedSongRecord {
                    song: SongDetailRecord::from(&snap.songs[song as usize]),
                    play_count,
                    frequency,
                    frequency_label: frequency.label().to_string(),
                }
            })
            .collect()
    };

    CollectionDashboardRecord {
        overall_collected: count_collected(&branded),
        overall_total: branded.len() as u32,
        brand_progress: brand_progress(snap, &collected),
        my_pick_collected: count_collected(&pick),
        my_pick_total: pick.len() as u32,
        pick_uncollected: rows(&pick_uncollected),
        all_uncollected: rows(&all_uncollected),
        catch_chances,
    }
}

/// 曲ごとの、リアルライブのセトリに載った回数 (songs と同じ添字)。
fn real_live_play_counts(snap: &Snapshot) -> Vec<u32> {
    snap.setlist_items_by_song
        .iter()
        .map(|items| {
            items
                .iter()
                .filter(|&&item| is_real_live(snap, snap.setlist_items[item as usize].show))
                .count() as u32
        })
        .collect()
}

/// ブランドごとの回収率 (ブランドの表示順)。数えるのは `songs.brand_id` (主ブランド) だけ。
fn brand_progress(snap: &Snapshot, collected: &[bool]) -> Vec<BrandCollectionProgressRecord> {
    let mut total = vec![0u32; snap.brands.len()];
    let mut got = vec![0u32; snap.brands.len()];
    for (song, s) in snap.songs.iter().enumerate() {
        let Some(&brand) = s.brand_id.as_deref().and_then(|id| snap.brand_index_by_id.get(id)) else {
            continue;
        };
        total[brand as usize] += 1;
        if collected[song] {
            got[brand as usize] += 1;
        }
    }
    snap.brand_order
        .iter()
        .map(|&brand| {
            let b = &snap.brands[brand as usize];
            BrandCollectionProgressRecord {
                brand_id: b.id.clone(),
                short_name: b.short_name.clone(),
                color: b.color.clone(),
                collected: got[brand as usize],
                total: total[brand as usize],
            }
        })
        .collect()
}

/// 「この公演で未回収が聴けるかも」: 今日以降のリアルライブの公演ごとに、親イベントと同じ
/// 主ブランドのリアルライブで披露されたことのある未回収曲の異なり数を数え、多い順に返す。
/// 0 曲の公演は出さない。
fn catch_chances(snap: &Snapshot, uncollected: &[u32], today: &str, limit: u32) -> Vec<CatchChanceRecord> {
    let mut hits: HashSet<(&str, u32)> = HashSet::new();
    for &song in uncollected {
        for &item in &snap.setlist_items_by_song[song as usize] {
            let show = snap.setlist_items[item as usize].show;
            if !is_real_live(snap, show) {
                continue;
            }
            let event = &snap.events[snap.shows[show as usize].event as usize];
            if let Some(brand) = event.brand_id.as_deref() {
                hits.insert((brand, song));
            }
        }
    }
    let mut likely_by_brand: std::collections::HashMap<&str, u32> = std::collections::HashMap::new();
    for (brand, _) in hits {
        *likely_by_brand.entry(brand).or_default() += 1;
    }

    let mut chances: Vec<(u32, u32)> = snap
        .shows_in_date_order
        .iter()
        .filter(|&&show| is_real_live(snap, show) && is_upcoming_on(&snap.shows[show as usize].date, today))
        .filter_map(|&show| {
            let event = &snap.events[snap.shows[show as usize].event as usize];
            let likely = *likely_by_brand.get(event.brand_id.as_deref()?)?;
            (likely > 0).then_some((show, likely))
        })
        .collect();
    // 同じ数・同じ日・同じ sort_order の公演は公演 id 順 (端末の DB の行の順に左右されない)。
    chances.sort_by(|&(a, likely_a), &(b, likely_b)| {
        let (sa, sb) = (&snap.shows[a as usize], &snap.shows[b as usize]);
        likely_b
            .cmp(&likely_a)
            .then_with(|| sa.date.cmp(&sb.date))
            .then_with(|| sa.sort_order.cmp(&sb.sort_order))
            .then_with(|| sa.id.cmp(&sb.id))
    });
    chances.truncate(limit as usize);

    chances
        .into_iter()
        .map(|(show, likely_count)| {
            let event = &snap.events[snap.shows[show as usize].event as usize];
            let brand = event.brand_id.as_deref().and_then(|id| snap.brand_index_by_id.get(id));
            CatchChanceRecord {
                show: show_record_at(snap, show),
                event_name: event.name.clone(),
                event_short_name: event_short_name(&event.name).to_string(),
                brand_id: event.brand_id.clone(),
                brand_color: brand.and_then(|&b| snap.brands[b as usize].color.clone()),
                likely_count,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{bundle_conn, bundle_snapshot};
    use std::collections::HashMap;

    /// 参加したことにする公演: リアルライブの公演を日付順に 1 つおきに 60 公演。
    fn attended_songs(snap: &Snapshot) -> Vec<String> {
        let shows: HashSet<u32> = snap
            .shows_in_date_order
            .iter()
            .copied()
            .filter(|&show| is_real_live(snap, show))
            .step_by(2)
            .take(60)
            .collect();
        let mut ids: Vec<String> = snap
            .setlist_items
            .iter()
            .filter(|item| shows.contains(&item.show))
            .map(|item| snap.songs[item.song as usize].id.clone())
            .collect();
        ids.sort();
        ids.dedup();
        ids
    }

    /// 担当: 原唱曲の多いアイドルを 2 人。
    fn pick_idols(snap: &Snapshot) -> Vec<String> {
        let mut idols: Vec<(usize, &str)> = snap
            .idols
            .iter()
            .enumerate()
            .map(|(i, idol)| (snap.songs_by_idol[i].iter().filter(|l| l.role == "original").count(), idol.id.as_str()))
            .collect();
        idols.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(b.1)));
        idols.iter().take(2).map(|(_, id)| id.to_string()).collect()
    }

    #[test]
    fn frequency_thresholds_and_labels() {
        let cases = [(0, PlayFrequency::Never, "未披露"), (1, PlayFrequency::Rare, "レア"), (2, PlayFrequency::Rare, "レア")];
        let more = [(3, PlayFrequency::Sometimes, "ときどき"), (9, PlayFrequency::Sometimes, "ときどき"), (10, PlayFrequency::Staple, "定番")];
        for (count, frequency, label) in cases.into_iter().chain(more) {
            assert_eq!(PlayFrequency::of(count), frequency, "{count} 回");
            assert_eq!(frequency.label(), label);
        }
    }

    #[test]
    fn totals_and_brand_progress_match_the_ios_sql() {
        let snap = bundle_snapshot();
        let conn = bundle_conn();
        let collected = attended_songs(snap);
        assert!(collected.len() > 100, "参加したことにした公演の曲が十分ある: {}", collected.len());
        let d = collection_dashboard(snap, &collected, &[], "2026-01-01", DEFAULT_CATCH_CHANCE_LIMIT);

        let branded: u32 = conn
            .query_row("SELECT COUNT(*) FROM songs WHERE brand_id IS NOT NULL", [], |r| r.get(0))
            .unwrap();
        assert_eq!(d.overall_total, branded);
        let collected_set: HashSet<&str> = collected.iter().map(String::as_str).collect();
        let mut stmt = conn.prepare("SELECT id FROM songs WHERE brand_id IS NOT NULL").unwrap();
        let branded_collected = stmt
            .query_map([], |r| r.get::<_, String>(0))
            .unwrap()
            .filter(|id| collected_set.contains(id.as_ref().unwrap().as_str()))
            .count() as u32;
        assert_eq!(d.overall_collected, branded_collected);
        assert!(d.overall_collected > 0 && d.overall_collected < d.overall_total);

        // fetchBrandCollectionProgress の SQL と、回収済みのブランド別の数え方。
        let mut stmt = conn
            .prepare(
                "SELECT b.id, b.short_name, b.color, COUNT(s.id) FROM brands b
                 LEFT JOIN songs s ON b.id = s.brand_id GROUP BY b.id ORDER BY b.sort_order",
            )
            .unwrap();
        let expected: Vec<(String, String, Option<String>, u32)> = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
            .unwrap()
            .map(Result::unwrap)
            .collect();
        let mut by_brand: HashMap<String, u32> = HashMap::new();
        for id in &collected {
            let brand: Option<String> =
                conn.query_row("SELECT brand_id FROM songs WHERE id = ?", [id], |r| r.get(0)).unwrap();
            if let Some(brand) = brand {
                *by_brand.entry(brand).or_default() += 1;
            }
        }
        let got: Vec<(String, String, Option<String>, u32)> = d
            .brand_progress
            .iter()
            .map(|b| (b.brand_id.clone(), b.short_name.clone(), b.color.clone(), b.total))
            .collect();
        assert_eq!(got, expected);
        for b in &d.brand_progress {
            assert_eq!(b.collected, by_brand.get(&b.brand_id).copied().unwrap_or(0), "{}", b.brand_id);
        }
    }

    #[test]
    fn uncollected_songs_are_ordered_by_play_count_then_kana_then_id() {
        let snap = bundle_snapshot();
        let conn = bundle_conn();
        let collected = attended_songs(snap);
        let picks = pick_idols(snap);
        let d = collection_dashboard(snap, &collected, &picks, "2026-01-01", DEFAULT_CATCH_CHANCE_LIMIT);

        // 披露回数は fetchLifetimePlayCounts の SQL (リアルライブのセトリの行数)。
        let mut stmt = conn
            .prepare(
                "SELECT si.song_id, COUNT(*) FROM setlist_items si
                 JOIN shows sh ON sh.id = si.show_id JOIN events e ON e.id = sh.event_id
                 WHERE e.kind IN ('live','festival') AND COALESCE(sh.performer_type, '') <> 'screening' GROUP BY si.song_id",
            )
            .unwrap();
        let counts: HashMap<String, u32> = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
            .unwrap()
            .map(Result::unwrap)
            .collect();
        let collected_set: HashSet<&str> = collected.iter().map(String::as_str).collect();
        for list in [&d.all_uncollected, &d.pick_uncollected] {
            for row in list.iter() {
                assert!(!collected_set.contains(row.song.id.as_str()), "回収済みは載らない");
                assert_eq!(row.play_count, counts.get(&row.song.id).copied().unwrap_or(0), "{}", row.song.id);
                assert_eq!(row.frequency, PlayFrequency::of(row.play_count));
                assert_eq!(row.frequency_label, row.frequency.label());
            }
            for pair in list.windows(2) {
                let key = |r: &UncollectedSongRecord| {
                    (std::cmp::Reverse(r.play_count), r.song.title_kana.clone().unwrap_or_default(), r.song.id.clone())
                };
                assert!(key(&pair[0]) < key(&pair[1]), "{} → {}", pair[0].song.id, pair[1].song.id);
            }
        }
        assert_eq!(d.all_uncollected.len() as u32, d.overall_total - d.overall_collected);
        assert!(d.all_uncollected.iter().any(|r| r.frequency == PlayFrequency::Never));
        assert!(d.all_uncollected.iter().any(|r| r.frequency == PlayFrequency::Staple));

        // 担当のオリ曲 (song_artists の原唱者) の回収率と未回収。
        let pick_ids = song_ids_with_any_artist(snap, &picks);
        assert!(!pick_ids.is_empty());
        assert_eq!(d.my_pick_total, pick_ids.len() as u32);
        let pick_collected = pick_ids.iter().filter(|id| collected_set.contains(id.as_str())).count() as u32;
        assert_eq!(d.my_pick_collected, pick_collected);
        let mut pick_rest: Vec<&str> = pick_ids.iter().map(String::as_str).filter(|id| !collected_set.contains(id)).collect();
        let mut listed: Vec<&str> = d.pick_uncollected.iter().map(|r| r.song.id.as_str()).collect();
        pick_rest.sort();
        listed.sort();
        assert_eq!(listed, pick_rest);
    }

    #[test]
    fn catch_chances_match_the_ios_sql_and_are_ordered_deterministically() {
        let snap = bundle_snapshot();
        let collected = attended_songs(snap);
        check_catch_chances_against_ios_sql(&collected, "2025-06-01");
        let d = collection_dashboard(snap, &collected, &[], "2025-06-01", 1000);
        let limited = collection_dashboard(snap, &collected, &[], "2025-06-01", 3);
        assert_eq!(limited.catch_chances, d.catch_chances[..3].to_vec(), "先頭から chance_limit 件");
    }

    /// iOS `fetchUpcomingCatchChances` の SQL (削除前の b6ea16f8^) と、今日以降の全公演で突き合わせる。
    fn check_catch_chances_against_ios_sql(collected: &[String], today: &str) {
        let snap = bundle_snapshot();
        let conn = bundle_conn();
        let d = collection_dashboard(snap, collected, &[], today, 1000);
        let uncollected: HashSet<&str> = d.all_uncollected.iter().map(|r| r.song.id.as_str()).collect();

        // fetchUpcomingCatchChances の 2 つの SQL。
        let mut stmt = conn
            .prepare(
                "SELECT DISTINCT e.brand_id, si.song_id FROM setlist_items si
                 JOIN shows sh ON sh.id = si.show_id JOIN events e ON e.id = sh.event_id
                 WHERE e.kind IN ('live','festival') AND e.brand_id IS NOT NULL
                   AND COALESCE(sh.performer_type, '') <> 'screening'",
            )
            .unwrap();
        let mut likely_by_brand: HashMap<String, u32> = HashMap::new();
        for row in stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))).unwrap() {
            let (brand, song) = row.unwrap();
            if uncollected.contains(song.as_str()) {
                *likely_by_brand.entry(brand).or_default() += 1;
            }
        }
        let mut stmt = conn
            .prepare(
                "SELECT s.id, e.brand_id, s.date FROM shows s JOIN events e ON s.event_id = e.id
                 WHERE s.date >= ? AND e.kind IN ('live','festival')
                   AND COALESCE(s.performer_type, '') <> 'screening' ORDER BY s.date, s.sort_order, s.id",
            )
            .unwrap();
        let mut expected: Vec<(String, u32, String)> = stmt
            .query_map([today], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?)))
            .unwrap()
            .map(Result::unwrap)
            .filter_map(|(show, brand, date)| likely_by_brand.get(&brand).map(|&n| (show, n, date)))
            .collect();
        expected.sort_by_key(|e| std::cmp::Reverse(e.1));
        assert!(expected.len() > 5, "今日以降の公演が十分ある: {}", expected.len());

        let got: Vec<(String, u32, String)> = d
            .catch_chances
            .iter()
            .map(|c| (c.show.id.clone(), c.likely_count, c.show.date.clone()))
            .collect();
        let ids = |v: &[(String, u32, String)]| v.iter().map(|(id, n, _)| (id.clone(), *n)).collect::<Vec<_>>();
        assert_eq!(ids(&got), ids(&expected));
        for pair in got.windows(2) {
            assert!(pair[0].1 > pair[1].1 || (pair[0].1 == pair[1].1 && pair[0].2 <= pair[1].2), "多い順 → 日付の昇順");
        }
        for c in &d.catch_chances {
            assert!(c.likely_count > 0);
            assert_eq!(c.event_short_name, event_short_name(&c.event_name));
            let brand = c.brand_id.as_deref().expect("主ブランドのある公演だけ");
            let color: Option<String> =
                conn.query_row("SELECT color FROM brands WHERE id = ?", [brand], |r| r.get(0)).unwrap();
            assert_eq!(c.brand_color, color);
        }

    }

    #[test]
    fn unknown_and_duplicate_ids_do_not_count_and_nothing_collected_leaves_everything_open() {
        let snap = bundle_snapshot();
        let d = collection_dashboard(snap, &[], &[], "2026-01-01", DEFAULT_CATCH_CHANCE_LIMIT);
        assert_eq!(d.overall_collected, 0);
        assert_eq!(d.all_uncollected.len() as u32, d.overall_total);
        assert!(d.pick_uncollected.is_empty() && d.my_pick_total == 0 && d.my_pick_collected == 0);
        assert!(d.brand_progress.iter().all(|b| b.collected == 0));

        let song = d.all_uncollected[0].song.id.clone();
        let with_noise = [song.clone(), song.clone(), "存在しない曲".to_string()];
        let once = collection_dashboard(snap, &with_noise, &[], "2026-01-01", DEFAULT_CATCH_CHANCE_LIMIT);
        assert_eq!(once.overall_collected, 1, "重複と未知の id は数えない");
        assert!(once.all_uncollected.iter().all(|r| r.song.id != song));
    }

    #[test]
    fn no_chances_after_the_last_show() {
        let snap = bundle_snapshot();
        let d = collection_dashboard(snap, &[], &[], "9999-12-31", DEFAULT_CATCH_CHANCE_LIMIT);
        assert!(d.catch_chances.is_empty());
    }
}
