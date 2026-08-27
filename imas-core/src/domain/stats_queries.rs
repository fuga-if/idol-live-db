//! 統計 (ランキング/集計) のクエリ群 (SQL 時代の Stats 系を Snapshot 上の純粋関数へ移送)。
//!
//! SQL 時代の対応 (iOS `AppDatabase+StatsQueries` / Android StatsDao 相当):
//! - `fetchBrandSongCountsQuery` — ブランド別楽曲数 (brands LEFT JOIN songs)
//! - `fetchSongPlayCountRankingQuery` — ライブ披露回数ランキング (songs JOIN setlist_items)
//! - `fetchCastShowCountRankingQuery` — アイドル別出演公演数ランキング (idols JOIN show_cast)
//! - `fetchYearlyShowCountsQuery` — 年別ライブ開催数推移 (strftime('%Y') GROUP BY)
//! - `fetchBrandedSongIdsQuery` — 回収率集計の母集合 (brand_id IS NOT NULL)
//! - `fetchCdSeriesListQuery` — CD シリーズ名の一覧 (曲フィルタのピッカー)
//!
//! ポート対応: `StatsReading` 全メソッド + `SongReading.brandedSongIds` +
//! `SongReading.cdSeriesList`。
//! `DiagnosticsReading.metaValue` は `Snapshot::meta_value` を inbound がそのまま公開する
//! (ロジックが無いのでこのファイルに関数は置かない)。同ポートの `databaseStats` /
//! `syncDiagnostics` は意図的に移送しない: どちらも「永続 DB そのものの状態」を観測する
//! 診断であり、派生キャッシュ (スナップショット) 越しに読むと診断対象がすり替わる
//! (例: FK 孤児はスナップショットに載らないので、まさに診断したい異常が見えなくなる)。
//!
//! SQL の暗黙挙動をコードで明示して固定する:
//! - ランキングの `ORDER BY count DESC` の同数タイは SQL では未規定 → 添字
//!   (= rowid 読み込み順) を最終キーにして決定的にする (共有コアの決定性規約)。
//! - `COUNT(DISTINCT sc.show_id)` — show_cast に同一 (show, idol) が複数行あっても
//!   1 公演と数える (ミニ DB 照合テストで固定。Bundle DB に重複行は無い)。
//! - `strftime('%Y', date)` — ゼロ埋め 'YYYY-MM-DD' で月 01-12・日 01-31 のときだけ
//!   年を返す (SQLite 実測: 2 月 31 日は通り、月 13・日 00/32・ゼロ埋めなしは NULL)。
//! - FK 孤児 (存在しない show/idol を指すリンク行) はスナップショットに載らない世界で
//!   数える (performance_counts と同じ規約。Bundle DB はリリース規約で孤児ゼロ)。
//!
//! **user_marks はスナップショットに無い**。回収率はプラットフォーム側が回収済み id 集合を
//! 解決し、`branded_song_ids` (母集合) と突き合わせる (iOS StatsView / CollectionShareCard)。

use crate::domain::snapshot::Snapshot;
use std::cmp::Reverse;
use std::collections::{BTreeMap, HashSet};

// =============================================================================
// FFI 射影 Record (uniffi は型 derive のみ / ロジックはこのファイルの関数側)
// =============================================================================

/// ブランド別楽曲数 1 行 (iOS `BrandSongCount`)。名前に Record を付けるのは生成
/// バインディングが既存 Swift struct と衝突しないため (SongListFilter と同じ判断)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, Hash)]
pub struct BrandSongCountRecord {
    pub id: String,
    pub short_name: String,
    pub color: Option<String>,
    /// LEFT JOIN の COUNT(s.id): 楽曲ゼロのブランドも 0 で載る。
    pub song_count: u32,
}

/// 披露回数ランキング 1 行 (iOS `SongPlayCount`)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, Hash)]
pub struct SongPlayCountRecord {
    pub id: String,
    pub title: String,
    pub play_count: u32,
    pub brand_id: Option<String>,
}

/// 出演公演数ランキング 1 行 (iOS `CastShowCount`)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, Hash)]
pub struct CastShowCountRecord {
    pub id: String,
    pub name: String,
    pub show_count: u32,
}

/// 年別公演数 1 行 (iOS `YearlyShowCount`)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, Hash)]
pub struct YearlyShowCountRecord {
    /// 'YYYY' (strftime('%Y') の出力)。
    pub year: String,
    pub show_count: u32,
}

// =============================================================================
// クエリ関数 (Snapshot を引数に取る純粋関数)
// =============================================================================

/// ブランド別楽曲数。iOS `fetchBrandSongCountsQuery` 相当:
///
/// ```sql
/// SELECT b.id, b.short_name, b.color, COUNT(s.id) AS song_count
/// FROM brands b LEFT JOIN songs s ON b.id = s.brand_id
/// GROUP BY b.id ORDER BY b.sort_order
/// ```
///
/// LEFT JOIN + GROUP BY を「songs 1 回走査で加算」に置き換える。brand_id が NULL、
/// または brands に無い id を指す曲はどのブランドにも数えない (JOIN 不成立と同じ)。
pub fn brand_song_counts(snap: &Snapshot) -> Vec<BrandSongCountRecord> {
    let mut counts = vec![0u32; snap.brands.len()];
    for song in &snap.songs {
        if let Some(&bi) = song.brand_id.as_deref().and_then(|id| snap.brand_index_by_id.get(id)) {
            counts[bi as usize] += 1;
        }
    }
    // ORDER BY b.sort_order は brand_order (sort_order ASC, 添字) が前計算済み。
    snap.brand_order
        .iter()
        .map(|&bi| {
            let b = &snap.brands[bi as usize];
            BrandSongCountRecord {
                id: b.id.clone(),
                short_name: b.short_name.clone(),
                color: b.color.clone(),
                song_count: counts[bi as usize],
            }
        })
        .collect()
}

/// ライブ披露回数ランキング。iOS `fetchSongPlayCountRankingQuery` 相当:
///
/// ```sql
/// SELECT s.id, s.title, COUNT(si.id) AS play_count, s.brand_id
/// FROM songs s JOIN setlist_items si ON s.id = si.song_id
/// GROUP BY s.id ORDER BY play_count DESC LIMIT ?
/// ```
///
/// INNER JOIN なので披露 0 回の曲は行が生まれない。回数は performance_counts
/// (= setlist_items_by_song の各長さ) を再集計せず使う (二重集計防止の既存規約)。
pub fn song_play_count_ranking(snap: &Snapshot, limit: u32) -> Vec<SongPlayCountRecord> {
    let mut ranked: Vec<u32> = (0..snap.songs.len() as u32)
        .filter(|&i| snap.performance_counts[i as usize] > 0)
        .collect();
    // DESC の同数タイは SQL 未規定 → 添字を最終キーに固定。
    ranked.sort_by_key(|&i| (Reverse(snap.performance_counts[i as usize]), i));
    ranked.truncate(limit as usize);
    ranked
        .into_iter()
        .map(|i| {
            let s = &snap.songs[i as usize];
            SongPlayCountRecord {
                id: s.id.clone(),
                title: s.title.clone(),
                play_count: snap.performance_counts[i as usize],
                brand_id: s.brand_id.clone(),
            }
        })
        .collect()
}

/// アイドル別出演公演数ランキング。iOS `fetchCastShowCountRankingQuery` 相当:
///
/// ```sql
/// SELECT i.id, i.name, COUNT(DISTINCT sc.show_id) AS show_count
/// FROM idols i JOIN show_cast sc ON i.id = sc.idol_id
/// GROUP BY i.id ORDER BY show_count DESC LIMIT ?
/// ```
///
/// INNER JOIN なので出演記録の無いアイドルは行が生まれない。COUNT(DISTINCT) の
/// とおり、同一公演に複数行 (role 違い等) あっても 1 公演と数える。
pub fn cast_show_count_ranking(snap: &Snapshot, limit: u32) -> Vec<CastShowCountRecord> {
    let mut ranked: Vec<(u32, u32)> = snap
        .cast_shows_by_idol
        .iter()
        .enumerate()
        .filter(|(_, shows)| !shows.is_empty())
        .map(|(ii, shows)| {
            let distinct = shows.iter().collect::<HashSet<_>>().len() as u32;
            (ii as u32, distinct)
        })
        .collect();
    // DESC の同数タイは SQL 未規定 → 添字を最終キーに固定。
    ranked.sort_by_key(|&(ii, count)| (Reverse(count), ii));
    ranked.truncate(limit as usize);
    ranked
        .into_iter()
        .map(|(ii, count)| {
            let idol = &snap.idols[ii as usize];
            CastShowCountRecord { id: idol.id.clone(), name: idol.name.clone(), show_count: count }
        })
        .collect()
}

/// 年別ライブ開催数推移。iOS `fetchYearlyShowCountsQuery` 相当:
///
/// ```sql
/// SELECT strftime('%Y', date) AS year, COUNT(*) FROM shows GROUP BY year ORDER BY year
/// ```
///
/// BTreeMap が GROUP BY + ORDER BY year (BINARY 照合 = バイト列昇順) を担う。
/// strftime が NULL になる規約外の date は行ごと落とす: SQL では NULL 年グループが
/// 先頭にできるが、その行は GRDB の `YearlyShowCount.year: String` デコードで
/// エラーになっていた = 保存すべき既存挙動が無いため、落とす側に明示的に倒す。
pub fn yearly_show_counts(snap: &Snapshot) -> Vec<YearlyShowCountRecord> {
    let mut by_year: BTreeMap<&str, u32> = BTreeMap::new();
    for show in &snap.shows {
        if let Some(year) = strftime_year(&show.date) {
            *by_year.entry(year).or_insert(0) += 1;
        }
    }
    by_year
        .into_iter()
        .map(|(year, show_count)| YearlyShowCountRecord { year: year.to_string(), show_count })
        .collect()
}

/// brand_id が設定されている曲 id (回収率集計の母集合)。iOS `fetchBrandedSongIdsQuery` 相当:
///
/// ```sql
/// SELECT id FROM songs WHERE brand_id IS NOT NULL
/// ```
///
/// IS NOT NULL なので空文字 '' や brands に無い id でも「設定あり」として含む。
/// iOS 側は Set にしていた (= 順序不問) が、FFI 面は songs Vec 順 (= rowid 読み込み順)
/// で決定的に返し、集合化はプラットフォーム側に任せる。
pub fn branded_song_ids(snap: &Snapshot) -> Vec<String> {
    snap.songs.iter().filter(|s| s.brand_id.is_some()).map(|s| s.id.clone()).collect()
}

/// CD シリーズ名の一覧 (曲フィルタのピッカー用)。iOS `fetchCdSeriesListQuery` 相当:
///
/// ```sql
/// SELECT DISTINCT cd_series FROM songs
///  WHERE cd_series IS NOT NULL AND cd_series != ''
///  ORDER BY cd_series
/// ```
///
/// `!= ''` があるので空文字は NULL と同じく「未設定」として落とす
/// (落とさないとピッカーに名前の無い行が 1 つ出る)。
///
/// 並びは列に COLLATE 指定が無い = BINARY 昇順で、Rust の `str` の `Ord`
/// (バイト列比較) と一致する。かな/漢字が五十音順に並ばないのは SQL 時代からの
/// 挙動なので、ここで「読み順に直す」ことはしない (直すとピッカーの並びが黙って変わる)。
pub fn cd_series_list(snap: &Snapshot) -> Vec<String> {
    let mut out: Vec<&str> = snap
        .songs
        .iter()
        .filter_map(|s| s.cd_series.as_deref())
        .filter(|v| !v.is_empty())
        .collect();
    // sort + dedup で SQL の DISTINCT + ORDER BY と同じ (隣接重複のみ消えれば十分)。
    out.sort_unstable();
    out.dedup();
    out.into_iter().map(str::to_string).collect()
}

/// SQLite `strftime('%Y', date)` の、当アプリの date 契約域での等価実装。
///
/// SQLite の受理域は実測でテストに固定してある (`strftime_year_matches_sqlite`):
/// - ゼロ埋め 'YYYY-MM-DD' で月 01-12・日 01-31 → 先頭 4 桁 (2 月 31 日のような
///   月ごとの日数超過も SQLite は受理して年を返す)
/// - 月 13 以降・月/日 00・日 32 以降・ゼロ埋めなし・空文字 → NULL
///
/// 'YYYY-MM-DD HH:MM' のような時刻つきも SQLite は受理するが、shows.date は
/// スナップショット規約で 10 文字の 'YYYY-MM-DD' (snapshot::Show::date) なので
/// 契約外として None に倒す (この分岐差もテストで明示している)。
fn strftime_year(date: &str) -> Option<&str> {
    let b = date.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return None;
    }
    if !b.iter().enumerate().all(|(i, c)| matches!(i, 4 | 7) || c.is_ascii_digit()) {
        return None;
    }
    let two = |hi: u8, lo: u8| u32::from(hi - b'0') * 10 + u32::from(lo - b'0');
    let (month, day) = (two(b[5], b[6]), two(b[8], b[9]));
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    Some(&date[..4])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::outbound::sqlite_loader::load_snapshot;
    use rusqlite::{Connection, OpenFlags};
    use std::collections::HashMap;
    use std::sync::OnceLock;

    fn db_path() -> String {
        format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"))
    }

    /// スナップショットは全テストで共有 (不変なので安全・ロードを 1 回にする)。
    fn snap() -> &'static Snapshot {
        static SNAP: OnceLock<Snapshot> = OnceLock::new();
        SNAP.get_or_init(|| load_snapshot(&db_path()).expect("bundle DB はロードできる"))
    }

    fn conn() -> Connection {
        Connection::open_with_flags(
            db_path(),
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .expect("bundle DB を開ける")
    }

    // ---- 元 SQL の写経 (これが等価性の基準) ----

    fn sql_brand_song_counts(db: &Connection) -> Vec<BrandSongCountRecord> {
        db.prepare(
            "SELECT b.id, b.short_name, b.color, COUNT(s.id) AS song_count
             FROM brands b LEFT JOIN songs s ON b.id = s.brand_id
             GROUP BY b.id ORDER BY b.sort_order",
        )
        .unwrap()
        .query_map([], |r| {
            Ok(BrandSongCountRecord {
                id: r.get(0)?,
                short_name: r.get(1)?,
                color: r.get(2)?,
                song_count: r.get::<_, i64>(3)? as u32,
            })
        })
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap()
    }

    /// LIMIT -1 = 無制限 (SQLite の負値 LIMIT)。タイ込みの全順序を得るのに使う。
    fn sql_play_count_ranking(db: &Connection, limit: i64) -> Vec<SongPlayCountRecord> {
        db.prepare(
            "SELECT s.id, s.title, COUNT(si.id) AS play_count, s.brand_id
             FROM songs s JOIN setlist_items si ON s.id = si.song_id
             GROUP BY s.id ORDER BY play_count DESC LIMIT ?",
        )
        .unwrap()
        .query_map([limit], |r| {
            Ok(SongPlayCountRecord {
                id: r.get(0)?,
                title: r.get(1)?,
                play_count: r.get::<_, i64>(2)? as u32,
                brand_id: r.get(3)?,
            })
        })
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap()
    }

    fn sql_cast_show_count_ranking(db: &Connection, limit: i64) -> Vec<CastShowCountRecord> {
        db.prepare(
            "SELECT i.id, i.name, COUNT(DISTINCT sc.show_id) AS show_count
             FROM idols i JOIN show_cast sc ON i.id = sc.idol_id
             GROUP BY i.id ORDER BY show_count DESC LIMIT ?",
        )
        .unwrap()
        .query_map([limit], |r| {
            Ok(CastShowCountRecord {
                id: r.get(0)?,
                name: r.get(1)?,
                show_count: r.get::<_, i64>(2)? as u32,
            })
        })
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap()
    }

    fn sql_yearly_show_counts(db: &Connection) -> Vec<YearlyShowCountRecord> {
        db.prepare(
            "SELECT strftime('%Y', date) AS year, COUNT(*) AS show_count
             FROM shows GROUP BY year ORDER BY year",
        )
        .unwrap()
        .query_map([], |r| {
            Ok(YearlyShowCountRecord {
                year: r.get(0)?,
                show_count: r.get::<_, i64>(1)? as u32,
            })
        })
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap()
    }

    /// ランキングの照合。`ORDER BY count DESC` の同数タイは SQLite では実行計画依存で
    /// 未規定なので「counts 列が一致し、同数グループの構成員が一致」を等価とみなす。
    /// LIMIT がグループの途中で切れる場合、SQL 側もどの構成員が残るか未規定なので、
    /// 境界グループだけは「LIMIT なし全結果の同グループへの包含」まで弱める。
    fn assert_ranking_matches<T: std::hash::Hash + Eq + std::fmt::Debug>(
        label: &str,
        actual: &[T],
        full: &[T],
        limit: usize,
        count_of: impl Fn(&T) -> u32,
    ) {
        assert_eq!(actual.len(), full.len().min(limit), "{label}: 件数");
        for (i, (a, e)) in actual.iter().zip(full.iter()).enumerate() {
            assert_eq!(count_of(a), count_of(e), "{label}: counts 列 {i} 行目");
        }
        fn group<'a, T: std::hash::Hash + Eq>(
            source: &'a [T],
            count_of: &impl Fn(&T) -> u32,
        ) -> HashMap<u32, HashSet<&'a T>> {
            let mut m: HashMap<u32, HashSet<&'a T>> = HashMap::new();
            for r in source {
                m.entry(count_of(r)).or_default().insert(r);
            }
            m
        }
        let full_groups = group(full, &count_of);
        let actual_groups = group(actual, &count_of);
        let boundary = actual.last().map(&count_of);
        for (count, members) in &actual_groups {
            let expected = full_groups.get(count).unwrap_or_else(|| {
                panic!("{label}: count={count} が SQL 全結果に無い")
            });
            if Some(*count) == boundary {
                assert!(
                    members.is_subset(expected),
                    "{label}: 境界グループ count={count} が SQL 全結果の部分集合でない"
                );
            } else {
                assert_eq!(members, expected, "{label}: count={count} の同数グループ");
            }
        }
    }

    // ---- brand_song_counts (照合 3 本) ----

    #[test]
    fn brand_song_counts_matches_sql_verbatim() {
        // Bundle の brands は sort_order がユニークなのでタイが無く、逐語一致を要求できる。
        let db = conn();
        let unique: i64 = db
            .query_row("SELECT COUNT(DISTINCT sort_order) - COUNT(*) FROM brands", [], |r| r.get(0))
            .unwrap();
        assert_eq!(unique, 0, "前提: brands.sort_order はユニーク");
        let expected = sql_brand_song_counts(&db);
        assert!(!expected.is_empty());
        assert_eq!(brand_song_counts(snap()), expected);
    }

    #[test]
    fn brand_song_counts_includes_zero_song_brands() {
        // LEFT JOIN: 楽曲ゼロのブランドも 0 件で載る = 行数は常に brands 全件。
        let db = conn();
        let brands: i64 = db.query_row("SELECT COUNT(*) FROM brands", [], |r| r.get(0)).unwrap();
        assert_eq!(brand_song_counts(snap()).len() as i64, brands);
    }

    #[test]
    fn brand_song_counts_total_matches_joined_songs() {
        // 合計 = brands に JOIN できる曲の数 (NULL・未知 brand_id はどこにも数えない)。
        let db = conn();
        let joined: i64 = db
            .query_row(
                "SELECT COUNT(*) FROM songs s JOIN brands b ON s.brand_id = b.id",
                [],
                |r| r.get(0),
            )
            .unwrap();
        let total: u32 = brand_song_counts(snap()).iter().map(|r| r.song_count).sum();
        assert_eq!(i64::from(total), joined);
    }

    // ---- song_play_count_ranking (照合 3 本) ----

    #[test]
    fn play_count_ranking_full_matches_sql() {
        let full = sql_play_count_ranking(&conn(), -1);
        assert!(full.len() > 100);
        let actual = song_play_count_ranking(snap(), u32::MAX);
        assert_ranking_matches("play_count 全件", &actual, &full, usize::MAX, |r| r.play_count);
        // INNER JOIN: 披露 0 回の曲は載らない。
        assert!(actual.iter().all(|r| r.play_count >= 1));
    }

    #[test]
    fn play_count_ranking_default_limit_matches_sql() {
        // iOS 既定の limit=20。境界タイは全結果への包含で判定する。
        let full = sql_play_count_ranking(&conn(), -1);
        let actual = song_play_count_ranking(snap(), 20);
        assert_ranking_matches("play_count limit=20", &actual, &full, 20, |r| r.play_count);
    }

    #[test]
    fn play_count_ranking_limit_cutting_inside_tie_group() {
        // 同数グループの途中で LIMIT が切れるケースを実データから作る:
        // 2 曲以上が並ぶ回数を探し、そのグループの 1 曲目までで切る。
        let full = sql_play_count_ranking(&conn(), -1);
        let mut cut = None;
        for i in 1..full.len() {
            if full[i].play_count == full[i - 1].play_count {
                cut = Some(i); // グループ 2 曲目の手前 = グループ途中
                break;
            }
        }
        let cut = cut.expect("bundle DB には同数タイがあるはず");
        let actual = song_play_count_ranking(snap(), cut as u32);
        assert_ranking_matches("play_count タイ途中", &actual, &full, cut, |r| r.play_count);
    }

    // ---- cast_show_count_ranking (照合 3 本) ----

    #[test]
    fn cast_ranking_full_matches_sql() {
        let full = sql_cast_show_count_ranking(&conn(), -1);
        assert!(full.len() > 50);
        let actual = cast_show_count_ranking(snap(), u32::MAX);
        assert_ranking_matches("cast 全件", &actual, &full, usize::MAX, |r| r.show_count);
        assert!(actual.iter().all(|r| r.show_count >= 1));
    }

    #[test]
    fn cast_ranking_default_limit_matches_sql() {
        let full = sql_cast_show_count_ranking(&conn(), -1);
        let actual = cast_show_count_ranking(snap(), 20);
        assert_ranking_matches("cast limit=20", &actual, &full, 20, |r| r.show_count);
    }

    #[test]
    fn cast_ranking_limit_cutting_inside_tie_group() {
        let full = sql_cast_show_count_ranking(&conn(), -1);
        let mut cut = None;
        for i in 1..full.len() {
            if full[i].show_count == full[i - 1].show_count {
                cut = Some(i);
                break;
            }
        }
        let cut = cut.expect("bundle DB には同数タイがあるはず");
        let actual = cast_show_count_ranking(snap(), cut as u32);
        assert_ranking_matches("cast タイ途中", &actual, &full, cut, |r| r.show_count);
    }

    // ---- yearly_show_counts (照合 3 本) ----

    #[test]
    fn yearly_show_counts_matches_sql_verbatim() {
        // year は GROUP BY キーそのものなのでタイが存在せず、逐語一致を要求できる。
        let expected = sql_yearly_show_counts(&conn());
        assert!(!expected.is_empty());
        assert_eq!(yearly_show_counts(snap()), expected);
    }

    #[test]
    fn yearly_show_counts_cover_all_shows() {
        // Bundle の date は全行 'YYYY-MM-DD' (規約) なので合計 = shows 全件。
        let db = conn();
        let shows: i64 = db.query_row("SELECT COUNT(*) FROM shows", [], |r| r.get(0)).unwrap();
        let total: u32 = yearly_show_counts(snap()).iter().map(|r| r.show_count).sum();
        assert_eq!(i64::from(total), shows);
    }

    #[test]
    fn strftime_year_matches_sqlite() {
        // 実データ全 date + 境界値バッテリで SQLite の strftime('%Y') と突き合わせる。
        let db = conn();
        let mut dates: Vec<String> = db
            .prepare("SELECT DISTINCT date FROM shows")
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        dates.extend(
            [
                "2015-12-31", "2015-02-31", "0500-01-01", "9999-01-01", // 受理域
                "2015-13-01", "2015-00-01", "2015-01-00", "2015-01-32", // 範囲外 → NULL
                "2015-1-01", "2015-01-1", "", "abcd-ef-gh", // 形式不正 → NULL
            ]
            .map(String::from),
        );
        for date in &dates {
            let sqlite: Option<String> = db
                .query_row("SELECT strftime('%Y', ?)", [date], |r| r.get(0))
                .unwrap();
            assert_eq!(strftime_year(date), sqlite.as_deref(), "date={date:?}");
        }
        // 契約外の時刻つきだけは意図的に分岐が異なる (モジュール doc 参照):
        // SQLite は受理するが、shows.date の契約 (10 文字) の外なので None に倒す。
        let with_time = "2015-02-10 18:00";
        let sqlite: Option<String> =
            db.query_row("SELECT strftime('%Y', ?)", [with_time], |r| r.get(0)).unwrap();
        assert_eq!(sqlite.as_deref(), Some("2015"));
        assert_eq!(strftime_year(with_time), None);
    }

    // ---- branded_song_ids (照合 2 本 + ミニ DB 1 本) ----

    #[test]
    fn branded_song_ids_matches_sql_as_set() {
        // iOS 側は Set<String> 化して使う (順序不問) ので集合として照合する。
        let db = conn();
        let expected: HashSet<String> = db
            .prepare("SELECT id FROM songs WHERE brand_id IS NOT NULL")
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        assert!(!expected.is_empty());
        let actual = branded_song_ids(snap());
        assert_eq!(actual.len(), expected.len(), "重複なし");
        assert_eq!(actual.into_iter().collect::<HashSet<_>>(), expected);
    }

    #[test]
    fn branded_song_ids_order_is_deterministic_songs_order() {
        // FFI 面の並びは songs Vec 順 (= rowid 読み込み順) で固定 (関数 doc の宣言どおり)。
        let s = snap();
        let expected: Vec<String> = s
            .songs
            .iter()
            .filter(|song| song.brand_id.is_some())
            .map(|song| song.id.clone())
            .collect();
        assert_eq!(branded_song_ids(s), expected);
    }

    /// 元 SQL の写経 (DISTINCT + NULL/空文字の除外 + BINARY 昇順)。
    fn sql_cd_series_list(db: &Connection) -> Vec<String> {
        db.prepare(
            "SELECT DISTINCT cd_series FROM songs
              WHERE cd_series IS NOT NULL AND cd_series != ''
              ORDER BY cd_series",
        )
        .unwrap()
        .query_map([], |r| r.get::<_, String>(0))
        .unwrap()
        .map(Result::unwrap)
        .collect()
    }

    #[test]
    fn cd_series_list_matches_sql_verbatim() {
        let db = conn();
        let sql = sql_cd_series_list(&db);
        // ORDER BY + DISTINCT で並びまで一意に決まるので逐語一致を要求できる。
        assert_eq!(cd_series_list(snap()), sql);
        assert!(sql.len() > 10, "Bundle DB の CD シリーズ数={}", sql.len());
    }

    #[test]
    fn cd_series_list_is_sorted_and_deduped() {
        let got = cd_series_list(snap());
        assert!(got.windows(2).all(|w| w[0] < w[1]), "厳密昇順 (= 重複なし・BINARY 順)");
        assert!(got.iter().all(|v| !v.is_empty()), "空文字は落ちている");
    }

    // ---- ミニ DB 照合 (Bundle には無いエッジデータで暗黙挙動を固定) ----

    /// Bundle DB では観測できない境界データを持つミニ DB を作り、全クエリを元 SQL と
    /// 逐語照合する。固定する挙動:
    /// - show_cast の同一 (show, idol) 重複 → COUNT(DISTINCT) で 1 公演
    /// - brand_id = '' / 未知 id → branded には含む・brand 集計には数えない
    /// - 楽曲ゼロのブランド → LEFT JOIN で 0 件行が残る
    /// - 披露 0 回の曲・出演 0 回のアイドル → INNER JOIN で行なし
    /// - cd_series の NULL / '' / 重複・非整列 → DISTINCT + != '' + ORDER BY で畳む
    #[test]
    fn mini_db_edge_semantics_match_sql() {
        let path = std::env::temp_dir().join(format!(
            "imas_core_stats_edge_{}.sqlite",
            std::process::id()
        ));
        let path_str = path.to_str().unwrap().to_string();
        let _ = std::fs::remove_file(&path);
        {
            let c = Connection::open(&path).unwrap();
            // スキーマは outbound::sqlite_loader のミニ DB テストと同じ Bundle 相当
            // (ローダが読む全テーブルが必要)。あちらは Documents 専用要素の検証、
            // こちらは統計クエリの境界検証と目的が違うので独立に持つ。
            c.execute_batch(
                "CREATE TABLE songs (id TEXT PRIMARY KEY, title TEXT NOT NULL, title_kana TEXT,
                     brand_id TEXT, song_type TEXT, release_date TEXT, duration_sec INTEGER,
                     composer TEXT, lyricist TEXT, arranger TEXT, cd_series TEXT, cd_title TEXT,
                     artwork_url TEXT, preview_url TEXT, apple_music_id TEXT,
                     apple_music_album_id TEXT, isrc TEXT, lyrics_url TEXT, parent_song_id TEXT,
                     singer_label TEXT, unit_name TEXT, unit_id TEXT, series_group TEXT,
                     jasrac_code TEXT);
                 CREATE TABLE idols (id TEXT PRIMARY KEY, brand_id TEXT, name TEXT NOT NULL,
                     name_kana TEXT, name_romaji TEXT, color TEXT, sort_order INTEGER,
                     birthday TEXT, blood_type TEXT, height REAL, weight REAL, birth_place TEXT,
                     age INTEGER, bust REAL, waist REAL, hip REAL, constellation TEXT,
                     hobbies TEXT, talents TEXT, description TEXT, gender TEXT, handedness TEXT,
                     family_name TEXT, given_name TEXT, nickname TEXT, debut_date TEXT,
                     attribute TEXT, is_external INTEGER NOT NULL DEFAULT 0, aliases TEXT);
                 CREATE TABLE events (id TEXT PRIMARY KEY, brand_id TEXT, name TEXT NOT NULL,
                     event_type TEXT NOT NULL, is_streaming INTEGER NOT NULL DEFAULT 0,
                     is_solo INTEGER NOT NULL DEFAULT 1, kind TEXT NOT NULL DEFAULT 'live',
                     ticket_deadline TEXT, ticket_lottery_date TEXT, ticket_url TEXT,
                     joint_brand_ids TEXT, ticket_open_date TEXT);
                 CREATE TABLE shows (id TEXT PRIMARY KEY, event_id TEXT NOT NULL,
                     name TEXT NOT NULL, date TEXT NOT NULL, venue TEXT, venue_city TEXT,
                     start_time TEXT, sort_order INTEGER NOT NULL DEFAULT 0, performer_type TEXT,
                     venue_id TEXT, hall TEXT, stream_platform TEXT);
                 CREATE TABLE setlist_items (id TEXT PRIMARY KEY, show_id TEXT NOT NULL,
                     song_id TEXT NOT NULL, position INTEGER, section TEXT, notes TEXT,
                     unit_name TEXT);
                 CREATE TABLE setlist_performers (setlist_item_id TEXT NOT NULL,
                     idol_id TEXT NOT NULL);
                 CREATE TABLE show_cast (show_id TEXT NOT NULL, idol_id TEXT NOT NULL,
                     cast_role TEXT NOT NULL DEFAULT 'member');
                 CREATE TABLE units (id TEXT PRIMARY KEY, brand_id TEXT NOT NULL,
                     name TEXT NOT NULL, is_permanent INTEGER NOT NULL DEFAULT 1, name_alt TEXT);
                 CREATE TABLE unit_members (unit_id TEXT NOT NULL, idol_id TEXT NOT NULL);
                 CREATE TABLE song_artists (song_id TEXT NOT NULL, idol_id TEXT NOT NULL,
                     role TEXT);
                 CREATE TABLE brands (id TEXT PRIMARY KEY, name TEXT NOT NULL,
                     short_name TEXT NOT NULL, color TEXT, sort_order INTEGER NOT NULL);
                 CREATE TABLE idol_brands (idol_id TEXT NOT NULL, brand_id TEXT NOT NULL,
                     is_primary INTEGER NOT NULL DEFAULT 0);
                 CREATE TABLE venues (id TEXT PRIMARY KEY, name TEXT NOT NULL, name_kana TEXT,
                     prefecture TEXT, city TEXT, aliases TEXT, capacity INTEGER,
                     sort_order INTEGER NOT NULL DEFAULT 0);
                 CREATE TABLE venue_names (id TEXT PRIMARY KEY, venue_id TEXT NOT NULL,
                     name TEXT NOT NULL, valid_from TEXT, valid_to TEXT);
                 CREATE TABLE venue_halls (id TEXT PRIMARY KEY, venue_id TEXT NOT NULL,
                     name TEXT NOT NULL, capacity INTEGER);
                 CREATE TABLE staff (id TEXT PRIMARY KEY, brand_id TEXT NOT NULL,
                     name TEXT NOT NULL, name_kana TEXT, name_romaji TEXT, role TEXT,
                     birthday TEXT, sort_order INTEGER NOT NULL DEFAULT 0);
                 CREATE TABLE anniversaries (id TEXT PRIMARY KEY, brand_id TEXT NOT NULL,
                     label TEXT NOT NULL, date TEXT NOT NULL, kind TEXT NOT NULL,
                     sort_order INTEGER NOT NULL DEFAULT 0);
                 CREATE TABLE idol_voice_actors (id TEXT PRIMARY KEY, idol_id TEXT NOT NULL,
                     name TEXT NOT NULL, valid_from TEXT, valid_to TEXT);
                 CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);

                 INSERT INTO brands (id, name, short_name, color, sort_order) VALUES
                     ('b_empty', '曲ゼロ', 'ZERO', NULL, 0),
                     ('b1', 'ブランド1', 'B1', '#111111', 1),
                     ('b2', 'ブランド2', 'B2', NULL, 2);
                 -- cd_series は NULL / 空文字 / 重複 / 非整列 を 1 つずつ含めて
                 -- DISTINCT・!= '' ・ORDER BY の境界を Bundle DB 非依存で押さえる。
                 INSERT INTO songs (id, title, brand_id, cd_series) VALUES
                     ('s1', '定番曲', 'b1', 'seriesB'),
                     ('s2', '空文字ブランド曲', '', ''),
                     ('s3', 'ブランドなし曲', NULL, NULL),
                     ('s4', '未知ブランド曲', 'ghost_brand', 'seriesA'),
                     ('s5', '披露ゼロ曲', 'b2', 'seriesB');
                 INSERT INTO idols (id, name, sort_order) VALUES
                     ('i1', '重複出演', 1), ('i2', '単独出演', 2), ('i3', '出演なし', 3);
                 INSERT INTO events (id, name, event_type) VALUES ('ev1', 'ミニライブ', 'live');
                 INSERT INTO shows (id, event_id, name, date) VALUES
                     ('sh1', 'ev1', 'DAY1', '2020-05-01'),
                     ('sh2', 'ev1', 'DAY2', '2021-06-02'),
                     ('sh3', 'ev1', 'DAY3', '2021-06-03');
                 -- i1 は sh1 に role 違いで 2 行 (COUNT(DISTINCT) で 1 公演になるべき)。
                 INSERT INTO show_cast (show_id, idol_id, cast_role) VALUES
                     ('sh1', 'i1', 'member'), ('sh1', 'i1', 'lead'),
                     ('sh2', 'i1', 'member'), ('sh1', 'i2', 'guest');
                 INSERT INTO setlist_items (id, show_id, song_id, position) VALUES
                     ('it1', 'sh1', 's1', 1), ('it2', 'sh2', 's1', 1), ('it3', 'sh1', 's3', 2);",
            )
            .unwrap();
        }
        let mini = load_snapshot(&path_str).expect("ミニ DB はロードできる");
        let db = Connection::open_with_flags(
            &path_str,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .unwrap();

        // counts が全部異なるデータにしてあるのでランキングも逐語一致を要求できる。
        assert_eq!(brand_song_counts(&mini), sql_brand_song_counts(&db));
        assert_eq!(brand_song_counts(&mini).iter().map(|r| r.song_count).collect::<Vec<_>>(), [0, 1, 1]);
        assert_eq!(song_play_count_ranking(&mini, 10), sql_play_count_ranking(&db, 10));
        assert_eq!(cast_show_count_ranking(&mini, 10), sql_cast_show_count_ranking(&db, 10));
        assert_eq!(
            cast_show_count_ranking(&mini, 10).iter().map(|r| r.show_count).collect::<Vec<_>>(),
            [2, 1],
            "重複 (sh1,i1) は 1 公演・i3 は行なし"
        );
        assert_eq!(yearly_show_counts(&mini), sql_yearly_show_counts(&db));
        let branded: HashSet<String> = branded_song_ids(&mini).into_iter().collect();
        let sql_branded: HashSet<String> = db
            .prepare("SELECT id FROM songs WHERE brand_id IS NOT NULL")
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        assert_eq!(branded, sql_branded);
        assert!(branded.contains("s2") && branded.contains("s4"), "'' と未知 id も IS NOT NULL");
        assert!(!branded.contains("s3"));

        assert_eq!(cd_series_list(&mini), sql_cd_series_list(&db));
        assert_eq!(
            cd_series_list(&mini),
            ["seriesA", "seriesB"],
            "NULL と '' は落ち、重複は 1 つ、挿入順でなく昇順"
        );

        drop(db);
        let _ = std::fs::remove_file(&path);
    }
}
