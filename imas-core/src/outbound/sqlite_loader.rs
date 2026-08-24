//! master.sqlite → Snapshot の一括ローダ。
//!
//! READ_ONLY で開く: 書き込み権を持たないので、GRDB (iOS) / Room (Android) の writer と
//! 排他競合しない。journal_mode=DELETE 運用 (iOS の既存規律) にも影響を与えない。
//! ロードは起動時 + CloudKit sync 完了後のみ。失敗時は呼び出し側が旧スナップショット
//! (または SQL 経路) を維持する。

use crate::domain::snapshot::{Idol, Snapshot, Song, SongArtistLink};
use rusqlite::{Connection, OpenFlags};
use std::collections::HashMap;

pub fn load_snapshot(db_path: &str) -> Result<Snapshot, String> {
    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
    .map_err(|e| format!("open失敗 {db_path}: {e}"))?;

    let songs = load_songs(&conn)?;
    let idols = load_idols(&conn)?;

    let song_index_by_id: HashMap<String, u32> =
        songs.iter().enumerate().map(|(i, s)| (s.id.clone(), i as u32)).collect();
    let idol_index_by_id: HashMap<String, u32> =
        idols.iter().enumerate().map(|(i, s)| (s.id.clone(), i as u32)).collect();

    // song_artists → 双方向リンク。sort_order 順は構築時に一度だけ払う。
    let mut artists_by_song: Vec<Vec<SongArtistLink>> = vec![Vec::new(); songs.len()];
    let mut songs_by_idol: Vec<Vec<u32>> = vec![Vec::new(); idols.len()];
    let mut stmt = conn
        .prepare("SELECT song_id, idol_id, role FROM song_artists")
        .map_err(|e| e.to_string())?;
    let links = stmt
        .query_map([], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, Option<String>>(2)?))
        })
        .map_err(|e| e.to_string())?;
    for link in links {
        let (song_id, idol_id, role) = link.map_err(|e| e.to_string())?;
        // 参照整合が壊れた行 (FK 孤児) は黙って捨てず起動を壊すより、読み飛ばして継続する。
        // (過去に FK 孤児で起動クラッシュ→審査 reject の事故があった系譜のデータ)
        let (Some(&si), Some(&ii)) = (song_index_by_id.get(&song_id), idol_index_by_id.get(&idol_id))
        else { continue };
        artists_by_song[si as usize].push(SongArtistLink { idol: ii, role: role.unwrap_or_default() });
        songs_by_idol[ii as usize].push(si);
    }
    for links in &mut artists_by_song {
        links.sort_by_key(|l| self_sort_key(&idols[l.idol as usize]));
    }

    // 披露回数 (setlist_items の song_id 集計)。
    let mut performance_counts = vec![0u32; songs.len()];
    let mut stmt = conn
        .prepare("SELECT song_id, COUNT(*) FROM setlist_items GROUP BY song_id")
        .map_err(|e| e.to_string())?;
    let counts = stmt
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))
        .map_err(|e| e.to_string())?;
    for c in counts {
        let (song_id, n) = c.map_err(|e| e.to_string())?;
        if let Some(&si) = song_index_by_id.get(&song_id) {
            performance_counts[si as usize] = n.max(0) as u32;
        }
    }

    Ok(Snapshot {
        songs,
        idols,
        artists_by_song,
        songs_by_idol,
        performance_counts,
        song_index_by_id,
        idol_index_by_id,
    })
}

fn self_sort_key(idol: &Idol) -> i64 {
    // sort_order NULL は末尾 (SQL の ORDER BY と同じ NULLS LAST 相当)。
    idol.sort_order.unwrap_or(i64::MAX)
}

fn load_songs(conn: &Connection) -> Result<Vec<Song>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, title, title_kana, brand_id, song_type, release_date, duration_sec,
                    composer, lyricist, arranger, cd_series, cd_title, artwork_url, preview_url,
                    apple_music_id, apple_music_album_id, isrc, lyrics_url, parent_song_id,
                    singer_label, unit_name, unit_id, series_group, jasrac_code
             FROM songs",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok(Song {
                id: r.get(0)?,
                title: r.get(1)?,
                title_kana: r.get(2)?,
                brand_id: r.get(3)?,
                song_type: r.get(4)?,
                release_date: r.get(5)?,
                duration_sec: r.get(6)?,
                composer: r.get(7)?,
                lyricist: r.get(8)?,
                arranger: r.get(9)?,
                cd_series: r.get(10)?,
                cd_title: r.get(11)?,
                artwork_url: r.get(12)?,
                preview_url: r.get(13)?,
                apple_music_id: r.get(14)?,
                apple_music_album_id: r.get(15)?,
                isrc: r.get(16)?,
                lyrics_url: r.get(17)?,
                parent_song_id: r.get(18)?,
                singer_label: r.get(19)?,
                unit_name: r.get(20)?,
                unit_id: r.get(21)?,
                series_group: r.get(22)?,
                jasrac_code: r.get(23)?,
            })
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<_, _>>().map_err(|e| e.to_string())
}

fn load_idols(conn: &Connection) -> Result<Vec<Idol>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, brand_id, name, name_kana, color, sort_order, nickname, aliases,
                    attribute, is_external, birthday, debut_date
             FROM idols",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok(Idol {
                id: r.get(0)?,
                brand_id: r.get(1)?,
                name: r.get(2)?,
                name_kana: r.get(3)?,
                color: r.get(4)?,
                sort_order: r.get(5)?,
                nickname: r.get(6)?,
                aliases: r.get(7)?,
                attribute: r.get(8)?,
                is_external: r.get::<_, Option<i64>>(9)?.unwrap_or(0) != 0,
                birthday: r.get(10)?,
                debut_date: r.get(11)?,
            })
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<_, _>>().map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bundle_db() -> String {
        format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"))
    }

    #[test]
    fn loads_bundle_db_with_consistent_indexes() {
        let s = load_snapshot(&bundle_db()).expect("bundle DB はロードできる");
        assert!(s.songs.len() >= 3000, "songs={}", s.songs.len());
        assert!(s.idols.len() >= 300, "idols={}", s.idols.len());
        assert_eq!(s.songs.len(), s.artists_by_song.len());
        assert_eq!(s.songs.len(), s.performance_counts.len());
        assert_eq!(s.idols.len(), s.songs_by_idol.len());
        // 索引の往復整合
        for (i, song) in s.songs.iter().enumerate().step_by(97) {
            assert_eq!(s.song_index_by_id[&song.id] as usize, i);
        }
    }

    #[test]
    fn artists_are_sorted_by_sort_order() {
        let s = load_snapshot(&bundle_db()).unwrap();
        for links in s.artists_by_song.iter().step_by(53) {
            let orders: Vec<i64> =
                links.iter().map(|l| s.idols[l.idol as usize].sort_order.unwrap_or(i64::MAX)).collect();
            assert!(orders.windows(2).all(|w| w[0] <= w[1]));
        }
    }

    #[test]
    fn missing_file_is_an_error_not_a_panic() {
        assert!(load_snapshot("/nonexistent/never.sqlite").is_err());
    }
}
