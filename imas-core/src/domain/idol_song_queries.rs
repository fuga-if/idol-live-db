//! アイドル→曲の逆引きクエリ (Phase 2 曲スライス)。
//!
//! SQL 時代の対応: AppDatabase+IdolQueries.swift の曲関連クエリ
//! (fetchIdolSongs / fetchIdolPerformedSongs / fetchIdolSongHistory /
//! fetchUnitIdsWithSongs) と、ユニット経由の関与曲 (unit_members × songs.unit_id)。
//! アイドル詳細画面の「楽曲 (原曲)」「ライブ歌唱曲」タブと、曲あり/曲なしユニット分割が顧客。
//!
//! ここは Snapshot を引数に取る純粋関数のみ。SQL の暗黙挙動は次の方針で明示化してある:
//! - ORDER BY の NULL 位置: SQLite は ASC で NULL 先頭 / DESC で NULL 末尾。
//!   Rust の `Option` は `None < Some` なのでそのまま (DESC は `Reverse`) で一致する。
//! - 文字列比較: スキーマは COLLATE 指定なし = BINARY (バイト列比較)。Rust の `str` の
//!   `Ord` もバイト列比較なので一致する。
//! - SQL で未規定だった同順位の並びは、スナップショットの添字 (= 決定的) で固定する
//!   (プラットフォーム間で同一結果を返すのが共有コアの目的なので、非決定性は残さない)。
//! - user_marks (担当/お気に入り/回収) はスナップショットに無い。回収バッジ等は
//!   プラットフォーム側が song_id で引く (この層は関与しない)。

use crate::domain::snapshot::Snapshot;
use std::cmp::Reverse;
use std::collections::HashMap;

/// アイドルの持ち歌 1 行ぶんの射影 (fetchIdolSongs 相当の行)。
///
/// エンティティ全体ではなく、一覧行の描画 (タイトル・ジャケ写・ユニット表記) と
/// 詳細画面への遷移 (song_id) に要る列だけを FFI 境界に載せる。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct IdolSongRecord {
    pub song_id: String,
    pub title: String,
    pub title_kana: Option<String>,
    /// 恒常ユニットの名義表記 (一覧行のサブラベル)。
    pub unit_name: Option<String>,
    pub artwork_url: Option<String>,
    pub preview_url: Option<String>,
    pub release_date: Option<String>,
    /// song_artists.role ('original' / 'performer')。role 未指定で引いたとき
    /// 同じ曲が role 違いで複数行返るのは SQL (JOIN) と同じ挙動。
    pub role: String,
}

/// ライブ歌唱曲 1 行ぶんの射影 (fetchIdolPerformedSongs 相当の行)。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct IdolPerformedSongRecord {
    pub song_id: String,
    pub title: String,
    pub title_kana: Option<String>,
    pub unit_name: Option<String>,
    pub artwork_url: Option<String>,
    pub preview_url: Option<String>,
    /// このアイドルが歌唱者として立った披露 (setlist_items) の数。
    /// 曲全体の披露回数 (Snapshot::performance_counts) とは別物。
    pub perform_count: u32,
}

/// アイドル×曲の披露公演履歴 1 行ぶんの射影 (fetchIdolSongHistory の CastShowRow 相当)。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct IdolSongShowRecord {
    pub show_id: String,
    pub event_id: String,
    pub event_name: String,
    pub show_name: String,
    /// YYYY-MM-DD。
    pub date: String,
    pub venue: Option<String>,
    /// show_cast 上の役割。行が無い (セトリのみの出演) 場合は SQL の
    /// `COALESCE(..., 'member')` と同じく 'member' に落とす。
    pub cast_role: String,
}

/// アイドルの持ち歌一覧 (song_artists 経由)。fetchIdolSongs 相当。
///
/// 元 SQL:
/// ```sql
/// SELECT s.* FROM songs s JOIN song_artists sa ON s.id = sa.song_id
/// WHERE sa.idol_id = ? [AND sa.role = ?] ORDER BY s.release_date DESC
/// ```
/// 並びは release_date DESC (NULL 末尾)・同日はスナップショット構築時に添字で固定済み。
/// 未知の idol_id は空 (SQL の 0 行と同じ)。
pub fn idol_songs(snap: &Snapshot, idol_id: &str, role: Option<&str>) -> Vec<IdolSongRecord> {
    let Some(&ii) = snap.idol_index_by_id.get(idol_id) else { return vec![] };
    snap.songs_by_idol[ii as usize]
        .iter()
        // role の比較は SQL の `sa.role = ?` と同じ完全一致 (BINARY)。
        // スキーマ上 role は NOT NULL なので NULL 対 '' の曖昧さは生じない。
        .filter(|l| role.is_none_or(|r| l.role == r))
        .map(|l| {
            let s = &snap.songs[l.song as usize];
            IdolSongRecord {
                song_id: s.id.clone(),
                title: s.title.clone(),
                title_kana: s.title_kana.clone(),
                unit_name: s.unit_name.clone(),
                artwork_url: s.artwork_url.clone(),
                preview_url: s.preview_url.clone(),
                release_date: s.release_date.clone(),
                role: l.role.clone(),
            }
        })
        .collect()
}

/// アイドルがライブで披露した曲一覧 (披露回数つき)。fetchIdolPerformedSongs 相当。
///
/// 元 SQL:
/// ```sql
/// SELECT s.*, COUNT(DISTINCT si.id) AS perform_count
/// FROM songs s
/// JOIN setlist_items si ON s.id = si.song_id
/// JOIN setlist_performers sp ON si.id = sp.setlist_item_id
/// WHERE sp.idol_id = ?
/// GROUP BY s.id
/// ORDER BY perform_count DESC, s.title_kana
/// ```
/// COUNT(DISTINCT si.id) は setlist_performers の PK (item, idol) により
/// 「このアイドルが立った披露の件数」と同値なので、逆引き索引の件数をそのまま数える。
/// 並びは (回数 DESC, title_kana ASC・NULL 先頭)・同順位は添字で固定。
pub fn idol_performed_songs(snap: &Snapshot, idol_id: &str) -> Vec<IdolPerformedSongRecord> {
    let Some(&ii) = snap.idol_index_by_id.get(idol_id) else { return vec![] };
    let mut count_by_song: HashMap<u32, u32> = HashMap::new();
    for &item in &snap.performed_items_by_idol[ii as usize] {
        *count_by_song.entry(snap.setlist_items[item as usize].song).or_insert(0) += 1;
    }
    let mut entries: Vec<(u32, u32)> = count_by_song.into_iter().collect();
    entries.sort_by(|&(sa, ca), &(sb, cb)| {
        let ka = (Reverse(ca), &snap.songs[sa as usize].title_kana, sa);
        let kb = (Reverse(cb), &snap.songs[sb as usize].title_kana, sb);
        ka.cmp(&kb)
    });
    entries
        .into_iter()
        .map(|(si, count)| {
            let s = &snap.songs[si as usize];
            IdolPerformedSongRecord {
                song_id: s.id.clone(),
                title: s.title.clone(),
                title_kana: s.title_kana.clone(),
                unit_name: s.unit_name.clone(),
                artwork_url: s.artwork_url.clone(),
                preview_url: s.preview_url.clone(),
                perform_count: count,
            }
        })
        .collect()
}

/// アイドルが特定の曲を披露した公演履歴 (最新順)。fetchIdolSongHistory 相当。
///
/// 元 SQL:
/// ```sql
/// SELECT DISTINCT sh.id, e.id, e.name, sh.name, sh.date, sh.venue,
///        COALESCE((SELECT cast_role FROM show_cast
///                   WHERE show_id = sh.id AND idol_id = :idol), 'member') AS cast_role
/// FROM setlist_items si
/// JOIN shows sh ON si.show_id = sh.id
/// JOIN events e ON sh.event_id = e.id
/// JOIN setlist_performers sp ON si.id = sp.setlist_item_id
/// WHERE si.song_id = :song AND sp.idol_id = :idol
/// ORDER BY sh.date DESC
/// ```
/// DISTINCT は選択列に show_id を含むため実質「公演単位の重複排除」
/// (同一公演でアンコール等 2 回歌っても 1 行)。ここでは show 添字で明示的に排除する。
/// 並びは date DESC・同日は (show.sort_order, position) で固定
/// (performed_items_by_idol の前計算順をそのまま使う)。
pub fn idol_song_history(snap: &Snapshot, idol_id: &str, song_id: &str) -> Vec<IdolSongShowRecord> {
    let (Some(&ii), Some(&si)) =
        (snap.idol_index_by_id.get(idol_id), snap.song_index_by_id.get(song_id))
    else {
        return vec![];
    };
    let mut seen_shows: Vec<u32> = Vec::new();
    let mut rows: Vec<IdolSongShowRecord> = Vec::new();
    for &item in &snap.performed_items_by_idol[ii as usize] {
        let it = &snap.setlist_items[item as usize];
        if it.song != si || seen_shows.contains(&it.show) {
            continue;
        }
        seen_shows.push(it.show);
        let show = &snap.shows[it.show as usize];
        let event = &snap.events[show.event as usize];
        rows.push(IdolSongShowRecord {
            show_id: show.id.clone(),
            event_id: event.id.clone(),
            event_name: event.name.clone(),
            show_name: show.name.clone(),
            date: show.date.clone(),
            venue: show.venue.clone(),
            // show_cast に行が無い = セトリだけの出演。SQL の COALESCE と同じ既定。
            cast_role: snap.show_cast_role(it.show, ii).unwrap_or("member").to_string(),
        });
    }
    rows
}

/// 指定ユニット ID のうち楽曲を 1 曲以上持つもの。fetchUnitIdsWithSongs 相当。
///
/// 元 SQL: `SELECT DISTINCT unit_id FROM songs WHERE unit_id IN (...)`
///
/// SQL の出力順は未規定だった (呼び出し側も Set として使う) ので、ここでは
/// 「入力順を保った重複なし列」に固定する。
/// 意図的な差分: songs.unit_id が units に実在しない FK 孤児 (Bundle DB に少数ある) は
/// 返さない。呼び出し側 (アイドル詳細の曲あり/曲なし分割) は units 由来の実在 ID しか
/// 渡さないので観測不能な差であり、ローダの「FK 孤児は読み飛ばす」規約とも揃う。
pub fn unit_ids_with_songs(snap: &Snapshot, unit_ids: &[String]) -> Vec<String> {
    let mut seen: Vec<&str> = Vec::new();
    let mut out: Vec<String> = Vec::new();
    for id in unit_ids {
        if seen.contains(&id.as_str()) {
            continue;
        }
        seen.push(id);
        if let Some(&ui) = snap.unit_index_by_id.get(id) {
            if !snap.songs_by_unit[ui as usize].is_empty() {
                out.push(id.clone());
            }
        }
    }
    out
}

/// ユニット経由の関与曲: アイドルが所属するユニットの持ち曲 (songs.unit_id 由来) の
/// song_id 列。SQL で書くなら:
/// ```sql
/// SELECT s.id FROM songs s
/// JOIN units u ON u.id = s.unit_id
/// JOIN unit_members um ON um.unit_id = u.id
/// WHERE um.idol_id = ? ORDER BY u.name, s.release_date
/// ```
/// 並びは所属ユニットの name 昇順 → ユニット内は release_date 昇順 (NULL 先頭)
/// (units_by_idol / songs_by_unit の前計算順をそのまま連結)。
/// songs.unit_id は単一列なので 1 曲が複数ユニットから重複して出ることはない。
pub fn idol_unit_song_ids(snap: &Snapshot, idol_id: &str) -> Vec<String> {
    let Some(&ii) = snap.idol_index_by_id.get(idol_id) else { return vec![] };
    snap.units_by_idol[ii as usize]
        .iter()
        .flat_map(|&ui| snap.songs_by_unit[ui as usize].iter())
        .map(|&si| snap.songs[si as usize].id.clone())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    fn db_path() -> String {
        format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"))
    }

    fn load() -> (Snapshot, Connection) {
        let path = db_path();
        let snap = crate::outbound::sqlite_loader::load_snapshot(&path).expect("bundle DB はロードできる");
        let conn = Connection::open_with_flags(
            &path,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .expect("bundle DB を開ける");
        (snap, conn)
    }

    /// 照合 1: idol_songs (role なし / original) が元 SQL と全アイドルで一致する。
    ///
    /// SQL の ORDER BY release_date DESC は同日内が未規定なので、
    /// (a) 並びのキーである release_date の列が完全一致すること
    /// (b) (song_id, role, release_date) の多重集合が完全一致すること
    /// の 2 点で等価性を固定する ((a)+(b) で「SQL が返しうる並びの1つ」であることが言える)。
    #[test]
    fn idol_songs_matches_sql_for_all_idols() {
        let (snap, conn) = load();
        let mut stmt_all = conn
            .prepare(
                "SELECT s.id, sa.role, s.release_date FROM songs s
                 JOIN song_artists sa ON s.id = sa.song_id
                 WHERE sa.idol_id = ?1 ORDER BY s.release_date DESC",
            )
            .unwrap();
        let mut stmt_role = conn
            .prepare(
                "SELECT s.id, sa.role, s.release_date FROM songs s
                 JOIN song_artists sa ON s.id = sa.song_id
                 WHERE sa.idol_id = ?1 AND sa.role = ?2 ORDER BY s.release_date DESC",
            )
            .unwrap();
        let mut nonempty = 0usize;
        for idol in &snap.idols {
            for role in [None, Some("original")] {
                let sql_rows: Vec<(String, String, Option<String>)> = match role {
                    None => stmt_all
                        .query_map([&idol.id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
                        .unwrap()
                        .map(Result::unwrap)
                        .collect(),
                    Some(ro) => stmt_role
                        .query_map([idol.id.as_str(), ro], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
                        .unwrap()
                        .map(Result::unwrap)
                        .collect(),
                };
                let got = idol_songs(&snap, &idol.id, role);
                // (a) release_date の並び (DESC・NULL 末尾) が SQL と同一
                let sql_dates: Vec<&Option<String>> = sql_rows.iter().map(|r| &r.2).collect();
                let got_dates: Vec<&Option<String>> = got.iter().map(|r| &r.release_date).collect();
                assert_eq!(sql_dates, got_dates, "idol={} role={:?}", idol.id, role);
                // (b) 内容の多重集合が同一 (role 違いの重複行も含めて)
                let mut sql_set: Vec<(String, String)> =
                    sql_rows.into_iter().map(|r| (r.0, r.1)).collect();
                let mut got_set: Vec<(String, String)> =
                    got.iter().map(|r| (r.song_id.clone(), r.role.clone())).collect();
                sql_set.sort();
                got_set.sort();
                assert_eq!(sql_set, got_set, "idol={} role={:?}", idol.id, role);
                if !got.is_empty() {
                    nonempty += 1;
                }
            }
        }
        assert!(nonempty > 300, "持ち歌のあるアイドル×role 組が少なすぎる: {nonempty}");
    }

    /// 照合 2: idol_performed_songs が元 SQL と全アイドルで一致する。
    /// 並びキー (perform_count DESC, title_kana) の列一致 + (song_id, count) の集合一致で固定。
    #[test]
    fn idol_performed_songs_matches_sql_for_all_idols() {
        let (snap, conn) = load();
        let mut stmt = conn
            .prepare(
                "SELECT s.id, COUNT(DISTINCT si.id) AS perform_count, s.title_kana
                 FROM songs s
                 JOIN setlist_items si ON s.id = si.song_id
                 JOIN setlist_performers sp ON si.id = sp.setlist_item_id
                 WHERE sp.idol_id = ?1
                 GROUP BY s.id
                 ORDER BY perform_count DESC, s.title_kana",
            )
            .unwrap();
        let mut checked = 0usize;
        for idol in &snap.idols {
            let sql_rows: Vec<(String, u32, Option<String>)> = stmt
                .query_map([&idol.id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
                .unwrap()
                .map(Result::unwrap)
                .collect();
            let got = idol_performed_songs(&snap, &idol.id);
            let sql_keys: Vec<(u32, &Option<String>)> =
                sql_rows.iter().map(|r| (r.1, &r.2)).collect();
            let got_keys: Vec<(u32, &Option<String>)> =
                got.iter().map(|r| (r.perform_count, &r.title_kana)).collect();
            assert_eq!(sql_keys, got_keys, "idol={} の並びキー列", idol.id);
            let mut sql_set: Vec<(String, u32)> = sql_rows.into_iter().map(|r| (r.0, r.1)).collect();
            let mut got_set: Vec<(String, u32)> =
                got.iter().map(|r| (r.song_id.clone(), r.perform_count)).collect();
            sql_set.sort();
            got_set.sort();
            assert_eq!(sql_set, got_set, "idol={} の内容", idol.id);
            if !got_set.is_empty() {
                checked += 1;
            }
        }
        assert!(checked > 100, "歌唱記録のあるアイドルが少なすぎる: {checked}");
    }

    /// 照合 3: idol_song_history が元 SQL とサンプル (アイドル×曲) 全組で一致する。
    /// date DESC の並びキー列一致 + 全射影列の集合一致 (cast_role の COALESCE 含む) で固定。
    #[test]
    fn idol_song_history_matches_sql_for_sampled_pairs() {
        let (snap, conn) = load();
        let mut stmt = conn
            .prepare(
                "SELECT DISTINCT sh.id, e.id, e.name, sh.name, sh.date, sh.venue,
                        COALESCE((SELECT cast_role FROM show_cast
                                   WHERE show_id = sh.id AND idol_id = ?1), 'member')
                 FROM setlist_items si
                 JOIN shows sh ON si.show_id = sh.id
                 JOIN events e ON sh.event_id = e.id
                 JOIN setlist_performers sp ON si.id = sp.setlist_item_id
                 WHERE si.song_id = ?2 AND sp.idol_id = ?1
                 ORDER BY sh.date DESC",
            )
            .unwrap();
        type Row = (String, String, String, String, String, Option<String>, String);
        let mut pairs = 0usize;
        for (ii, idol) in snap.idols.iter().enumerate() {
            // 各アイドル先頭 3 曲 (披露履歴の新しい順に現れた曲) をサンプルに使う。
            let mut sampled: Vec<u32> = Vec::new();
            for &item in &snap.performed_items_by_idol[ii] {
                let song = snap.setlist_items[item as usize].song;
                if !sampled.contains(&song) {
                    sampled.push(song);
                    if sampled.len() >= 3 {
                        break;
                    }
                }
            }
            for &song_idx in &sampled {
                let song_id = &snap.songs[song_idx as usize].id;
                let sql_rows: Vec<Row> = stmt
                    .query_map([idol.id.as_str(), song_id.as_str()], |r| {
                        Ok((
                            r.get(0)?,
                            r.get(1)?,
                            r.get(2)?,
                            r.get(3)?,
                            r.get(4)?,
                            r.get(5)?,
                            r.get(6)?,
                        ))
                    })
                    .unwrap()
                    .map(Result::unwrap)
                    .collect();
                let got = idol_song_history(&snap, &idol.id, song_id);
                assert!(!got.is_empty(), "サンプルは披露実績から取ったので空にならない");
                let sql_dates: Vec<&String> = sql_rows.iter().map(|r| &r.4).collect();
                let got_dates: Vec<&String> = got.iter().map(|r| &r.date).collect();
                assert_eq!(sql_dates, got_dates, "idol={} song={} の date 列", idol.id, song_id);
                let mut sql_set: Vec<Row> = sql_rows;
                let mut got_set: Vec<Row> = got
                    .iter()
                    .map(|r| {
                        (
                            r.show_id.clone(),
                            r.event_id.clone(),
                            r.event_name.clone(),
                            r.show_name.clone(),
                            r.date.clone(),
                            r.venue.clone(),
                            r.cast_role.clone(),
                        )
                    })
                    .collect();
                sql_set.sort();
                got_set.sort();
                assert_eq!(sql_set, got_set, "idol={} song={} の内容", idol.id, song_id);
                pairs += 1;
            }
        }
        assert!(pairs > 300, "照合した (アイドル×曲) 組が少なすぎる: {pairs}");
    }

    /// 照合 4: unit_ids_with_songs が元 SQL と一致する (実在ユニット全 ID を入力)。
    /// 実運用の入力は units 由来の実在 ID のみなので、その全域で集合一致を確認する。
    #[test]
    fn unit_ids_with_songs_matches_sql_for_all_units() {
        let (snap, conn) = load();
        let all_ids: Vec<String> = snap.units.iter().map(|u| u.id.clone()).collect();
        let placeholders = vec!["?"; all_ids.len()].join(",");
        let mut stmt = conn
            .prepare(&format!(
                "SELECT DISTINCT unit_id FROM songs WHERE unit_id IN ({placeholders})"
            ))
            .unwrap();
        let mut sql_ids: Vec<String> = stmt
            .query_map(rusqlite::params_from_iter(all_ids.iter()), |r| r.get(0))
            .unwrap()
            .map(Result::unwrap)
            .collect();
        let mut got = unit_ids_with_songs(&snap, &all_ids);
        assert!(!got.is_empty());
        // 入力順保持の確認: 出力は入力 (units の並び) の部分列になっている。
        let mut cursor = all_ids.iter();
        for id in &got {
            assert!(cursor.any(|x| x == id), "入力順が保たれていない: {id}");
        }
        sql_ids.sort();
        got.sort();
        assert_eq!(sql_ids, got);
    }

    /// unit_ids_with_songs の意図的な差分の固定: songs.unit_id にしかない FK 孤児 ID は
    /// 返さない (SQL は返すが、ローダの「FK 孤児は読み飛ばす」規約に合わせて除外する)。
    /// 重複入力が 1 回に畳まれること (SQL の DISTINCT 相当) もここで見る。
    #[test]
    fn unit_ids_with_songs_drops_orphans_and_duplicates() {
        let (snap, conn) = load();
        let orphan_ids: Vec<String> = conn
            .prepare("SELECT DISTINCT unit_id FROM songs WHERE unit_id NOT IN (SELECT id FROM units)")
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .map(Result::unwrap)
            .collect();
        // Bundle DB には孤児が実在する前提のテスト。消えたらこの分岐自体が不要になる。
        assert!(!orphan_ids.is_empty(), "孤児が解消されたらこのテストを整理して良い");
        assert_eq!(unit_ids_with_songs(&snap, &orphan_ids), Vec::<String>::new());

        let with_songs = snap
            .units
            .iter()
            .enumerate()
            .find(|(i, _)| !snap.songs_by_unit[*i].is_empty())
            .map(|(_, u)| u.id.clone())
            .expect("曲持ちユニットは存在する");
        let doubled = vec![with_songs.clone(), with_songs.clone(), "存在しないid".into()];
        assert_eq!(unit_ids_with_songs(&snap, &doubled), vec![with_songs]);
    }

    /// 照合 5: idol_unit_song_ids が対応 SQL と全アイドルで一致する。
    /// 並びキー (unit.name, release_date) の列一致 + song_id 集合一致で固定。
    #[test]
    fn idol_unit_song_ids_matches_sql_for_all_idols() {
        let (snap, conn) = load();
        let mut stmt = conn
            .prepare(
                "SELECT s.id, u.name, s.release_date FROM songs s
                 JOIN units u ON u.id = s.unit_id
                 JOIN unit_members um ON um.unit_id = u.id
                 WHERE um.idol_id = ?1
                 ORDER BY u.name, s.release_date",
            )
            .unwrap();
        let mut nonempty = 0usize;
        for (ii, idol) in snap.idols.iter().enumerate() {
            let sql_rows: Vec<(String, String, Option<String>)> = stmt
                .query_map([&idol.id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
                .unwrap()
                .map(Result::unwrap)
                .collect();
            let got = idol_unit_song_ids(&snap, &idol.id);
            // 並びキー列: got 側のキーはスナップショットから引き直す。
            let mut got_keys: Vec<(&String, &Option<String>)> = Vec::new();
            for &ui in &snap.units_by_idol[ii] {
                let name = &snap.units[ui as usize].name;
                for &si in &snap.songs_by_unit[ui as usize] {
                    got_keys.push((name, &snap.songs[si as usize].release_date));
                }
            }
            let sql_keys: Vec<(&String, &Option<String>)> =
                sql_rows.iter().map(|r| (&r.1, &r.2)).collect();
            assert_eq!(sql_keys, got_keys, "idol={} の並びキー列", idol.id);
            let mut sql_ids: Vec<&String> = sql_rows.iter().map(|r| &r.0).collect();
            let mut got_ids: Vec<&String> = got.iter().collect();
            sql_ids.sort();
            got_ids.sort();
            assert_eq!(sql_ids, got_ids, "idol={} の内容", idol.id);
            if !got.is_empty() {
                nonempty += 1;
            }
        }
        assert!(nonempty > 100, "ユニット曲持ちアイドルが少なすぎる: {nonempty}");
    }

    /// 未知 ID は SQL の 0 行と同じく空を返す (panic しない)。
    #[test]
    fn unknown_ids_yield_empty_results() {
        let (snap, _conn) = load();
        assert!(idol_songs(&snap, "居ないアイドル", None).is_empty());
        assert!(idol_songs(&snap, "居ないアイドル", Some("original")).is_empty());
        assert!(idol_performed_songs(&snap, "居ないアイドル").is_empty());
        assert!(idol_song_history(&snap, "居ないアイドル", "居ない曲").is_empty());
        let real_idol = &snap.idols[0].id;
        assert!(idol_song_history(&snap, real_idol, "居ない曲").is_empty());
        assert!(idol_unit_song_ids(&snap, "居ないアイドル").is_empty());
        assert!(unit_ids_with_songs(&snap, &[]).is_empty());
    }
}
