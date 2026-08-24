//! master.sqlite → Snapshot の一括ローダ。
//!
//! READ_ONLY で開く: 書き込み権を持たないので、GRDB (iOS) / Room (Android) の writer と
//! 排他競合しない。journal_mode=DELETE 運用 (iOS の既存規律) にも影響を与えない。
//! ロードは起動時 + CloudKit sync 完了後のみ。失敗時は呼び出し側が旧スナップショット
//! (または SQL 経路) を維持する。
//!
//! カラムは Bundle スキーマ基準で明示列挙する (SELECT * を使わない)。アプリ側
//! マイグレーションが Documents DB にだけ足す列 (has_streaming 等) はここでは
//! 読まないので、Bundle DB と移行済み Documents DB のどちらを渡されても同じ SQL が通る。
//!
//! FK 孤児 (参照整合が壊れた行) は黙って捨てて継続する。起動を壊すより読み飛ばす方が
//! 被害が小さい (過去に FK 孤児で起動クラッシュ→審査 reject の事故があった系譜のデータ)。

use crate::domain::snapshot::{
    Event, Idol, IdolSongLink, SetlistItem, Show, ShowCastLink, Snapshot, Song, SongArtistLink,
    Unit,
};
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
    let events = load_events(&conn)?;
    let units = load_units(&conn)?;

    let song_index_by_id: HashMap<String, u32> =
        songs.iter().enumerate().map(|(i, s)| (s.id.clone(), i as u32)).collect();
    let idol_index_by_id: HashMap<String, u32> =
        idols.iter().enumerate().map(|(i, s)| (s.id.clone(), i as u32)).collect();
    let event_index_by_id: HashMap<String, u32> =
        events.iter().enumerate().map(|(i, e)| (e.id.clone(), i as u32)).collect();
    let unit_index_by_id: HashMap<String, u32> =
        units.iter().enumerate().map(|(i, u)| (u.id.clone(), i as u32)).collect();

    // shows は event 添字リンクを張るため events の索引を先に作ってからロードする。
    let shows = load_shows(&conn, &event_index_by_id)?;
    let show_index_by_id: HashMap<String, u32> =
        shows.iter().enumerate().map(|(i, s)| (s.id.clone(), i as u32)).collect();

    // setlist_items は show / song 両方の添字リンクを張る。
    let setlist_items = load_setlist_items(&conn, &show_index_by_id, &song_index_by_id)?;

    // 以降は逆引き索引の構築。並び順の規約 (どの SQL の ORDER BY を前計算したものか) は
    // domain/snapshot.rs の各フィールド doc が正。ここでは同じ順序でソートを払う。

    // song_artists → 双方向リンク。
    let mut artists_by_song: Vec<Vec<SongArtistLink>> = vec![Vec::new(); songs.len()];
    let mut songs_by_idol: Vec<Vec<IdolSongLink>> = vec![Vec::new(); idols.len()];
    {
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
            let (Some(&si), Some(&ii)) =
                (song_index_by_id.get(&song_id), idol_index_by_id.get(&idol_id))
            else {
                continue;
            };
            let role = role.unwrap_or_default();
            artists_by_song[si as usize].push(SongArtistLink { idol: ii, role: role.clone() });
            songs_by_idol[ii as usize].push(IdolSongLink { song: si, role });
        }
    }
    for links in &mut artists_by_song {
        links.sort_by_key(|l| idol_sort_key(&idols, l.idol));
    }
    for links in &mut songs_by_idol {
        // release_date DESC (NULL 末尾)。同日は song 添字で決定的に。
        links.sort_by_key(|l| (release_desc_key(&songs, l.song), l.song));
    }

    // shows_by_event: (date ASC, sort_order ASC)。
    let mut shows_by_event: Vec<Vec<u32>> = vec![Vec::new(); events.len()];
    for (i, show) in shows.iter().enumerate() {
        shows_by_event[show.event as usize].push(i as u32);
    }
    for list in &mut shows_by_event {
        list.sort_by(|&a, &b| {
            let (sa, sb) = (&shows[a as usize], &shows[b as usize]);
            (&sa.date, sa.sort_order, a).cmp(&(&sb.date, sb.sort_order, b))
        });
    }

    // setlist_items_by_show: position ASC / setlist_items_by_song: show.date DESC。
    let mut setlist_items_by_show: Vec<Vec<u32>> = vec![Vec::new(); shows.len()];
    let mut setlist_items_by_song: Vec<Vec<u32>> = vec![Vec::new(); songs.len()];
    for (i, item) in setlist_items.iter().enumerate() {
        setlist_items_by_show[item.show as usize].push(i as u32);
        setlist_items_by_song[item.song as usize].push(i as u32);
    }
    for list in &mut setlist_items_by_show {
        list.sort_by_key(|&i| (setlist_items[i as usize].position, i));
    }
    let history_key = |i: u32| {
        // 披露履歴の表示順: 日付 DESC → 同日は sort_order ASC → position ASC → 添字。
        let item = &setlist_items[i as usize];
        let show = &shows[item.show as usize];
        (std::cmp::Reverse(show.date.clone()), show.sort_order, item.position, i)
    };
    for list in &mut setlist_items_by_song {
        list.sort_by_key(|&i| history_key(i));
    }

    // 披露回数 = setlist_items_by_song の各長さ。SQL の COUNT(*) GROUP BY song_id と
    // 一致する (孤児行を読み飛ばした後の世界で数える。履歴に出せない行は数えない)。
    let performance_counts: Vec<u32> =
        setlist_items_by_song.iter().map(|v| v.len() as u32).collect();

    // setlist_performers → 双方向リンク。
    let mut performers_by_item: Vec<Vec<u32>> = vec![Vec::new(); setlist_items.len()];
    let mut performed_items_by_idol: Vec<Vec<u32>> = vec![Vec::new(); idols.len()];
    {
        // setlist_item の String id → 添字 (この関数内でしか要らない一時索引)。
        let item_index_by_id: HashMap<&str, u32> = setlist_items
            .iter()
            .enumerate()
            .map(|(i, it)| (it.id.as_str(), i as u32))
            .collect();
        let mut stmt = conn
            .prepare("SELECT setlist_item_id, idol_id FROM setlist_performers")
            .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
            .map_err(|e| e.to_string())?;
        for row in rows {
            let (item_id, idol_id) = row.map_err(|e| e.to_string())?;
            let (Some(&ti), Some(&ii)) =
                (item_index_by_id.get(item_id.as_str()), idol_index_by_id.get(&idol_id))
            else {
                continue;
            };
            performers_by_item[ti as usize].push(ii);
            performed_items_by_idol[ii as usize].push(ti);
        }
    }
    for list in &mut performers_by_item {
        list.sort_by_key(|&i| idol_sort_key(&idols, i));
    }
    for list in &mut performed_items_by_idol {
        list.sort_by_key(|&i| history_key(i));
    }

    // show_cast → 双方向リンク。
    let mut cast_by_show: Vec<Vec<ShowCastLink>> = vec![Vec::new(); shows.len()];
    let mut cast_shows_by_idol: Vec<Vec<u32>> = vec![Vec::new(); idols.len()];
    {
        let mut stmt = conn
            .prepare("SELECT show_id, idol_id, cast_role FROM show_cast")
            .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([], |r| {
                Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, Option<String>>(2)?))
            })
            .map_err(|e| e.to_string())?;
        for row in rows {
            let (show_id, idol_id, cast_role) = row.map_err(|e| e.to_string())?;
            let (Some(&si), Some(&ii)) =
                (show_index_by_id.get(&show_id), idol_index_by_id.get(&idol_id))
            else {
                continue;
            };
            cast_by_show[si as usize].push(ShowCastLink {
                idol: ii,
                // スキーマ既定 'member' を NULL にも適用 (NOT NULL DEFAULT 'member' の再現)。
                cast_role: cast_role.unwrap_or_else(|| "member".to_string()),
            });
            cast_shows_by_idol[ii as usize].push(si);
        }
    }
    for list in &mut cast_by_show {
        list.sort_by_key(|l| idol_sort_key(&idols, l.idol));
    }
    for list in &mut cast_shows_by_idol {
        list.sort_by_key(|&i| {
            let show = &shows[i as usize];
            (std::cmp::Reverse(show.date.clone()), show.sort_order, i)
        });
    }

    // unit_members → 双方向リンク。
    let mut members_by_unit: Vec<Vec<u32>> = vec![Vec::new(); units.len()];
    let mut units_by_idol: Vec<Vec<u32>> = vec![Vec::new(); idols.len()];
    {
        let mut stmt = conn
            .prepare("SELECT unit_id, idol_id FROM unit_members")
            .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
            .map_err(|e| e.to_string())?;
        for row in rows {
            let (unit_id, idol_id) = row.map_err(|e| e.to_string())?;
            let (Some(&ui), Some(&ii)) =
                (unit_index_by_id.get(&unit_id), idol_index_by_id.get(&idol_id))
            else {
                continue;
            };
            members_by_unit[ui as usize].push(ii);
            units_by_idol[ii as usize].push(ui);
        }
    }
    for list in &mut members_by_unit {
        list.sort_by_key(|&i| idol_sort_key(&idols, i));
    }
    for list in &mut units_by_idol {
        // unit.name 昇順 (バイト列比較 = SQLite BINARY 照合と同じ)。
        list.sort_by(|&a, &b| {
            (&units[a as usize].name, a).cmp(&(&units[b as usize].name, b))
        });
    }

    // songs.unit_id → ユニット持ち曲 (release_date ASC, NULL 先頭 = SQLite ASC)。
    let mut songs_by_unit: Vec<Vec<u32>> = vec![Vec::new(); units.len()];
    for (i, song) in songs.iter().enumerate() {
        if let Some(ui) = song.unit_id.as_ref().and_then(|id| unit_index_by_id.get(id)) {
            songs_by_unit[*ui as usize].push(i as u32);
        }
    }
    for list in &mut songs_by_unit {
        list.sort_by(|&a, &b| {
            (&songs[a as usize].release_date, a).cmp(&(&songs[b as usize].release_date, b))
        });
    }

    // parent_song_id → 派生曲一族 (子は title_kana → title 昇順、NULL 先頭 = SQLite ASC)。
    let mut variants_by_song: Vec<Vec<u32>> = vec![Vec::new(); songs.len()];
    for (i, song) in songs.iter().enumerate() {
        if let Some(pi) = song.parent_song_id.as_ref().and_then(|id| song_index_by_id.get(id)) {
            variants_by_song[*pi as usize].push(i as u32);
        }
    }
    for list in &mut variants_by_song {
        list.sort_by(|&a, &b| {
            let (sa, sb) = (&songs[a as usize], &songs[b as usize]);
            (&sa.title_kana, &sa.title, a).cmp(&(&sb.title_kana, &sb.title, b))
        });
    }

    Ok(Snapshot {
        songs,
        idols,
        events,
        shows,
        setlist_items,
        units,
        artists_by_song,
        songs_by_idol,
        performance_counts,
        shows_by_event,
        setlist_items_by_show,
        setlist_items_by_song,
        performers_by_item,
        performed_items_by_idol,
        cast_by_show,
        cast_shows_by_idol,
        members_by_unit,
        units_by_idol,
        songs_by_unit,
        variants_by_song,
        song_index_by_id,
        idol_index_by_id,
        event_index_by_id,
        show_index_by_id,
        unit_index_by_id,
    })
}

/// sort_order NULL は末尾 (SQL の ORDER BY と同じ NULLS LAST 相当)。同値は添字で決定的に。
fn idol_sort_key(idols: &[Idol], idol: u32) -> (i64, u32) {
    (idols[idol as usize].sort_order.unwrap_or(i64::MAX), idol)
}

/// release_date DESC のキー。NULL は末尾 (SQLite の DESC は NULL を最後に置く)。
fn release_desc_key(songs: &[Song], song: u32) -> std::cmp::Reverse<Option<String>> {
    // Option の Ord は None < Some なので、Reverse すると None (=NULL) が末尾に落ちる。
    std::cmp::Reverse(songs[song as usize].release_date.clone())
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

fn load_events(conn: &Connection) -> Result<Vec<Event>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, brand_id, name, event_type, is_streaming, is_solo, kind,
                    ticket_open_date, ticket_deadline, ticket_lottery_date, ticket_url,
                    joint_brand_ids
             FROM events",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok(Event {
                id: r.get(0)?,
                brand_id: r.get(1)?,
                name: r.get(2)?,
                event_type: r.get(3)?,
                is_streaming: r.get::<_, Option<i64>>(4)?.unwrap_or(0) != 0,
                is_solo: r.get::<_, Option<i64>>(5)?.unwrap_or(1) != 0,
                // NOT NULL DEFAULT 'live' の既定を NULL にも適用 (防御)。
                kind: r.get::<_, Option<String>>(6)?.unwrap_or_else(|| "live".to_string()),
                ticket_open_date: r.get(7)?,
                ticket_deadline: r.get(8)?,
                ticket_lottery_date: r.get(9)?,
                ticket_url: r.get(10)?,
                joint_brand_ids: r.get(11)?,
            })
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<_, _>>().map_err(|e| e.to_string())
}

/// shows をロードする。親 event が存在しない FK 孤児は読み飛ばす
/// (孤児 show を残すと添字リンクが張れず、履歴系クエリすべてが Option を舐める羽目になる)。
fn load_shows(
    conn: &Connection,
    event_index_by_id: &HashMap<String, u32>,
) -> Result<Vec<Show>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, event_id, name, date, venue, venue_city, start_time, sort_order,
                    performer_type, venue_id, hall, stream_platform
             FROM shows",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, Option<String>>(4)?,
                r.get::<_, Option<String>>(5)?,
                r.get::<_, Option<String>>(6)?,
                r.get::<_, Option<i64>>(7)?,
                r.get::<_, Option<String>>(8)?,
                r.get::<_, Option<String>>(9)?,
                r.get::<_, Option<String>>(10)?,
                r.get::<_, Option<String>>(11)?,
            ))
        })
        .map_err(|e| e.to_string())?;
    let mut shows = Vec::new();
    for row in rows {
        let (id, event_id, name, date, venue, venue_city, start_time, sort_order, performer_type, venue_id, hall, stream_platform) =
            row.map_err(|e| e.to_string())?;
        let Some(&event) = event_index_by_id.get(&event_id) else { continue };
        shows.push(Show {
            id,
            event,
            name,
            date,
            venue,
            venue_city,
            start_time,
            sort_order: sort_order.unwrap_or(0),
            performer_type,
            venue_id,
            hall,
            stream_platform,
        });
    }
    Ok(shows)
}

/// setlist_items をロードする。show / song どちらかが FK 孤児の行は読み飛ばす。
fn load_setlist_items(
    conn: &Connection,
    show_index_by_id: &HashMap<String, u32>,
    song_index_by_id: &HashMap<String, u32>,
) -> Result<Vec<SetlistItem>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, show_id, song_id, position, section, notes, unit_name
             FROM setlist_items",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, Option<i64>>(3)?,
                r.get::<_, Option<String>>(4)?,
                r.get::<_, Option<String>>(5)?,
                r.get::<_, Option<String>>(6)?,
            ))
        })
        .map_err(|e| e.to_string())?;
    let mut items = Vec::new();
    for row in rows {
        let (id, show_id, song_id, position, section, notes, unit_name) =
            row.map_err(|e| e.to_string())?;
        let (Some(&show), Some(&song)) =
            (show_index_by_id.get(&show_id), song_index_by_id.get(&song_id))
        else {
            continue;
        };
        items.push(SetlistItem {
            id,
            show,
            song,
            position: position.unwrap_or(0),
            section,
            notes,
            unit_name,
        });
    }
    Ok(items)
}

fn load_units(conn: &Connection) -> Result<Vec<Unit>, String> {
    let mut stmt = conn
        .prepare("SELECT id, brand_id, name, is_permanent, name_alt FROM units")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok(Unit {
                id: r.get(0)?,
                brand_id: r.get(1)?,
                name: r.get(2)?,
                is_permanent: r.get::<_, Option<i64>>(3)?.unwrap_or(1) != 0,
                name_alt: r.get(4)?,
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

    fn snapshot() -> Snapshot {
        load_snapshot(&bundle_db()).expect("bundle DB はロードできる")
    }

    fn conn() -> Connection {
        Connection::open_with_flags(
            bundle_db(),
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .unwrap()
    }

    #[test]
    fn loads_bundle_db_with_consistent_indexes() {
        let s = snapshot();
        assert!(s.songs.len() >= 3000, "songs={}", s.songs.len());
        assert!(s.idols.len() >= 300, "idols={}", s.idols.len());
        assert!(s.events.len() >= 500, "events={}", s.events.len());
        assert!(s.shows.len() >= 1000, "shows={}", s.shows.len());
        assert!(s.setlist_items.len() >= 10000, "items={}", s.setlist_items.len());
        assert!(s.units.len() >= 1000, "units={}", s.units.len());
        // 「◯◯_by_△△」は△△側と同じ長さ (添字リンクの前提)。
        assert_eq!(s.songs.len(), s.artists_by_song.len());
        assert_eq!(s.songs.len(), s.performance_counts.len());
        assert_eq!(s.songs.len(), s.setlist_items_by_song.len());
        assert_eq!(s.songs.len(), s.variants_by_song.len());
        assert_eq!(s.idols.len(), s.songs_by_idol.len());
        assert_eq!(s.idols.len(), s.performed_items_by_idol.len());
        assert_eq!(s.idols.len(), s.cast_shows_by_idol.len());
        assert_eq!(s.idols.len(), s.units_by_idol.len());
        assert_eq!(s.events.len(), s.shows_by_event.len());
        assert_eq!(s.shows.len(), s.setlist_items_by_show.len());
        assert_eq!(s.shows.len(), s.cast_by_show.len());
        assert_eq!(s.setlist_items.len(), s.performers_by_item.len());
        assert_eq!(s.units.len(), s.members_by_unit.len());
        assert_eq!(s.units.len(), s.songs_by_unit.len());
        // 索引の往復整合
        for (i, song) in s.songs.iter().enumerate().step_by(97) {
            assert_eq!(s.song_index_by_id[&song.id] as usize, i);
        }
        for (i, show) in s.shows.iter().enumerate().step_by(53) {
            assert_eq!(s.show_index_by_id[&show.id] as usize, i);
        }
        for (i, ev) in s.events.iter().enumerate().step_by(31) {
            assert_eq!(s.event_index_by_id[&ev.id] as usize, i);
        }
        for (i, unit) in s.units.iter().enumerate().step_by(41) {
            assert_eq!(s.unit_index_by_id[&unit.id] as usize, i);
        }
    }

    #[test]
    fn row_counts_match_sql_after_orphan_policy() {
        // Bundle DB は FK 整合済みのはずなので、孤児読み飛ばし後も SQL の COUNT と一致する。
        // ずれたら「Bundle に孤児が混入した」ことを意味する (審査 reject 事故の再来を検知)。
        let s = snapshot();
        let c = conn();
        let count = |sql: &str| -> usize {
            c.query_row(sql, [], |r| r.get::<_, i64>(0)).unwrap() as usize
        };
        assert_eq!(s.events.len(), count("SELECT COUNT(*) FROM events"));
        assert_eq!(s.shows.len(), count("SELECT COUNT(*) FROM shows"));
        assert_eq!(s.setlist_items.len(), count("SELECT COUNT(*) FROM setlist_items"));
        assert_eq!(s.units.len(), count("SELECT COUNT(*) FROM units"));
        let performer_links: usize = s.performers_by_item.iter().map(Vec::len).sum();
        assert_eq!(performer_links, count("SELECT COUNT(*) FROM setlist_performers"));
        let cast_links: usize = s.cast_by_show.iter().map(Vec::len).sum();
        assert_eq!(cast_links, count("SELECT COUNT(*) FROM show_cast"));
        let member_links: usize = s.members_by_unit.iter().map(Vec::len).sum();
        assert_eq!(member_links, count("SELECT COUNT(*) FROM unit_members"));
    }

    #[test]
    fn artists_are_sorted_by_sort_order() {
        let s = snapshot();
        for links in s.artists_by_song.iter().step_by(53) {
            let orders: Vec<i64> =
                links.iter().map(|l| s.idols[l.idol as usize].sort_order.unwrap_or(i64::MAX)).collect();
            assert!(orders.windows(2).all(|w| w[0] <= w[1]));
        }
    }

    #[test]
    fn performance_counts_match_sql_group_by() {
        // 披露回数は SQL 時代 (COUNT(*) GROUP BY song_id) と同じ値になること。
        let s = snapshot();
        let c = conn();
        let mut stmt =
            c.prepare("SELECT song_id, COUNT(*) FROM setlist_items GROUP BY song_id").unwrap();
        let rows: Vec<(String, i64)> = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        assert!(!rows.is_empty());
        for (song_id, cnt) in rows {
            let si = s.song_index_by_id[&song_id] as usize;
            assert_eq!(s.performance_counts[si] as i64, cnt, "song={song_id}");
            assert_eq!(s.setlist_items_by_song[si].len() as i64, cnt);
        }
    }

    #[test]
    fn shows_by_event_are_sorted_by_date_then_sort_order() {
        let s = snapshot();
        for list in &s.shows_by_event {
            let keys: Vec<(&String, i64)> = list
                .iter()
                .map(|&i| (&s.shows[i as usize].date, s.shows[i as usize].sort_order))
                .collect();
            assert!(keys.windows(2).all(|w| w[0] <= w[1]));
            // event 添字リンクが自分に戻ること
            if let Some(&first) = list.first() {
                let ev = s.shows[first as usize].event as usize;
                assert!(s.shows_by_event[ev].contains(&first));
            }
        }
    }

    #[test]
    fn setlist_items_by_show_are_sorted_by_position() {
        let s = snapshot();
        for list in s.setlist_items_by_show.iter().step_by(7) {
            let positions: Vec<i64> =
                list.iter().map(|&i| s.setlist_items[i as usize].position).collect();
            assert!(positions.windows(2).all(|w| w[0] <= w[1]));
        }
    }

    #[test]
    fn performance_history_matches_sql_order_and_fields() {
        // 披露履歴 (fetchSongPerformanceHistory 相当) を最多披露曲で SQL と突き合わせる。
        // SQL は date DESC のみで同日内が未規定なので、集合一致 + 日付の降順単調性で見る。
        let s = snapshot();
        let (top_song, _) = s
            .performance_counts
            .iter()
            .enumerate()
            .max_by_key(|(_, &c)| c)
            .unwrap();
        let items = &s.setlist_items_by_song[top_song];
        assert!(items.len() >= 10, "最多披露曲の披露数={}", items.len());

        let dates: Vec<&String> =
            items.iter().map(|&i| &s.shows[s.setlist_items[i as usize].show as usize].date).collect();
        assert!(dates.windows(2).all(|w| w[0] >= w[1]), "date DESC が崩れている");

        let c = conn();
        let mut stmt = c
            .prepare(
                "SELECT si.id FROM setlist_items si
                 JOIN shows sh ON si.show_id = sh.id
                 JOIN events e ON sh.event_id = e.id
                 WHERE si.song_id = ?
                 ORDER BY sh.date DESC",
            )
            .unwrap();
        let sql_ids: Vec<String> = stmt
            .query_map([&s.songs[top_song].id], |r| r.get(0))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        let snap_ids: std::collections::HashSet<&str> =
            items.iter().map(|&i| s.setlist_items[i as usize].id.as_str()).collect();
        assert_eq!(sql_ids.len(), snap_ids.len());
        assert!(sql_ids.iter().all(|id| snap_ids.contains(id.as_str())));
    }

    #[test]
    fn performers_resolve_singers_like_sql() {
        // setlist_performers の歌い手解決を、適当な披露 1 件で SQL と突き合わせる。
        let s = snapshot();
        let ti = s
            .performers_by_item
            .iter()
            .position(|l| l.len() >= 2)
            .expect("複数人歌唱の披露がある");
        let item = &s.setlist_items[ti];
        let c = conn();
        let mut stmt = c
            .prepare(
                "SELECT sp.idol_id FROM setlist_performers sp
                 WHERE sp.setlist_item_id = ?",
            )
            .unwrap();
        let sql_ids: std::collections::HashSet<String> = stmt
            .query_map([&item.id], |r| r.get(0))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        let snap_ids: std::collections::HashSet<String> = s.performers_by_item[ti]
            .iter()
            .map(|&i| s.idols[i as usize].id.clone())
            .collect();
        assert_eq!(sql_ids, snap_ids);
        // 並びは sort_order 昇順
        let orders: Vec<i64> = s.performers_by_item[ti]
            .iter()
            .map(|&i| s.idols[i as usize].sort_order.unwrap_or(i64::MAX))
            .collect();
        assert!(orders.windows(2).all(|w| w[0] <= w[1]));
    }

    #[test]
    fn songs_by_idol_are_release_date_desc_with_roles() {
        let s = snapshot();
        let total_links: usize = s.songs_by_idol.iter().map(Vec::len).sum();
        let sql_links: usize = conn()
            .query_row("SELECT COUNT(*) FROM song_artists", [], |r| r.get::<_, i64>(0))
            .unwrap() as usize;
        assert_eq!(total_links, sql_links);
        for links in s.songs_by_idol.iter().step_by(11) {
            // release_date DESC (NULL 末尾)。Option<&String> の逆順比較で検証。
            let dates: Vec<Option<&String>> =
                links.iter().map(|l| s.songs[l.song as usize].release_date.as_ref()).collect();
            assert!(dates.windows(2).all(|w| match (w[0], w[1]) {
                (Some(a), Some(b)) => a >= b,
                (Some(_), None) => true,  // 値あり → NULL の順
                (None, Some(_)) => false, // NULL の後に値が来たら並び崩れ
                (None, None) => true,
            }));
        }
    }

    #[test]
    fn variants_form_families_with_sorted_children() {
        let s = snapshot();
        let parent = s
            .variants_by_song
            .iter()
            .position(|v| v.len() >= 2)
            .expect("派生曲を複数持つ親がいる (Crossing! のソロ群等)");
        for &child in &s.variants_by_song[parent] {
            assert_eq!(
                s.songs[child as usize].parent_song_id.as_deref(),
                Some(s.songs[parent].id.as_str())
            );
            // 子から根に戻れる (fetchVariantSongs の root 解決)
            assert_eq!(s.variant_root(child) as usize, parent);
        }
        // 子は (title_kana, title) 昇順
        let keys: Vec<(Option<&String>, &String)> = s.variants_by_song[parent]
            .iter()
            .map(|&i| (s.songs[i as usize].title_kana.as_ref(), &s.songs[i as usize].title))
            .collect();
        assert!(keys.windows(2).all(|w| w[0] <= w[1]));
    }

    #[test]
    fn unit_links_resolve_members_and_songs() {
        let s = snapshot();
        // メンバーのいるユニットと曲のあるユニットがそれぞれ十分いる
        let with_members = s.members_by_unit.iter().filter(|m| !m.is_empty()).count();
        assert!(with_members > 500, "メンバー付きユニット={with_members}");
        // songs.unit_id → songs_by_unit の往復
        for (i, song) in s.songs.iter().enumerate() {
            if let Some(ui) = song.unit_id.as_ref().and_then(|id| s.unit_index_by_id.get(id)) {
                assert!(s.songs_by_unit[*ui as usize].contains(&(i as u32)));
            }
        }
        // units_by_idol は unit.name 昇順
        for list in s.units_by_idol.iter().step_by(13) {
            let names: Vec<&String> = list.iter().map(|&i| &s.units[i as usize].name).collect();
            assert!(names.windows(2).all(|w| w[0] <= w[1]));
        }
    }

    #[test]
    fn show_cast_roles_are_loaded() {
        let s = snapshot();
        let cast_links: usize = s.cast_by_show.iter().map(Vec::len).sum();
        assert!(cast_links > 5000, "show_cast リンク={cast_links}");
        // cast_role は常に非空 (NULL は 'member' に既定化)
        assert!(s
            .cast_by_show
            .iter()
            .flatten()
            .all(|l| !l.cast_role.is_empty()));
        // show_cast_role の往復: 適当な行で引けること
        let si = s.cast_by_show.iter().position(|c| !c.is_empty()).unwrap();
        let link = &s.cast_by_show[si][0];
        assert_eq!(s.show_cast_role(si as u32, link.idol), Some(link.cast_role.as_str()));
    }

    #[test]
    fn collected_counts_can_be_derived_from_indexes() {
        // 回収回数 (fetchSongCollectedCounts 相当) が索引だけで再現できることの確認。
        // user_marks は載せない規約なので、参加 show 集合を「全 show」と仮置きして
        // SQL の同等式 (kind IN ('live','festival') の distinct show 数) と突き合わせる。
        let s = snapshot();
        let c = conn();
        let mut stmt = c
            .prepare(
                "SELECT si.song_id, COUNT(DISTINCT si.show_id)
                 FROM setlist_items si
                 JOIN shows sh ON sh.id = si.show_id
                 JOIN events e ON e.id = sh.event_id
                 WHERE e.kind IN ('live','festival')
                 GROUP BY si.song_id",
            )
            .unwrap();
        let sql_counts: HashMap<String, i64> = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        for (si, items) in s.setlist_items_by_song.iter().enumerate().step_by(17) {
            let mut show_set = std::collections::HashSet::new();
            for &ti in items {
                let show = s.setlist_items[ti as usize].show;
                let kind = &s.events[s.shows[show as usize].event as usize].kind;
                if kind == "live" || kind == "festival" {
                    show_set.insert(show);
                }
            }
            let expected = sql_counts.get(&s.songs[si].id).copied().unwrap_or(0);
            assert_eq!(show_set.len() as i64, expected, "song={}", s.songs[si].id);
        }
    }

    #[test]
    fn missing_file_is_an_error_not_a_panic() {
        assert!(load_snapshot("/nonexistent/never.sqlite").is_err());
    }
}
