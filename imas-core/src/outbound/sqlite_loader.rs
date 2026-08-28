//! master.sqlite → Snapshot の一括ローダ。
//!
//! READ_ONLY で開く: 書き込み権を持たないので、GRDB (iOS) / Room (Android) の writer と
//! 排他競合しない。journal_mode=DELETE 運用 (iOS の既存規律) にも影響を与えない。
//! ロードは起動時 + CloudKit sync 完了後のみ。失敗時は呼び出し側が旧スナップショット
//! (または SQL 経路) を維持する。
//!
//! カラムは Bundle スキーマ基準で明示列挙する (SELECT * を使わない)。アプリ側
//! マイグレーションが Documents DB にだけ足す列 (events/shows の has_streaming ・
//! has_live_viewing、brands.icon_url) と表 (event_releases) は、PRAGMA table_info /
//! sqlite_master で有無を動的検出して「あれば読む・無ければ既定値 (None / 空)」にする。
//! これで Bundle DB と移行済み Documents DB のどちらを渡されても同じコードが通る。
//!
//! song_calls / song_videos は意図して読まない (理由は domain/snapshot.rs 冒頭)。
//!
//! FK 孤児 (参照整合が壊れた行) は黙って捨てて継続する。起動を壊すより読み飛ばす方が
//! 被害が小さい (過去に FK 孤児で起動クラッシュ→審査 reject の事故があった系譜のデータ)。

use crate::domain::snapshot::{
    Anniversary, Brand, BrandMemberLink, Creator, Event, EventRelease, Idol, IdolBrandLink,
    IdolSongLink,
    IdolVoiceActor, SetlistItem, Show, ShowCastLink, Snapshot, Song, SongArtistLink, Staff, Unit,
    Venue, VenueHall, VenueName,
};
use rusqlite::{Connection, OpenFlags};
use std::collections::{HashMap, HashSet};

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
    let brands = load_brands(&conn)?;
    let creators = load_creators(&conn)?;
    let venues = load_venues(&conn)?;
    let staff = load_staff(&conn)?;
    let anniversaries = load_anniversaries(&conn)?;
    let meta = load_meta(&conn)?;

    let song_index_by_id: HashMap<String, u32> =
        songs.iter().enumerate().map(|(i, s)| (s.id.clone(), i as u32)).collect();
    let idol_index_by_id: HashMap<String, u32> =
        idols.iter().enumerate().map(|(i, s)| (s.id.clone(), i as u32)).collect();
    let event_index_by_id: HashMap<String, u32> =
        events.iter().enumerate().map(|(i, e)| (e.id.clone(), i as u32)).collect();
    let unit_index_by_id: HashMap<String, u32> =
        units.iter().enumerate().map(|(i, u)| (u.id.clone(), i as u32)).collect();
    let brand_index_by_id: HashMap<String, u32> =
        brands.iter().enumerate().map(|(i, b)| (b.id.clone(), i as u32)).collect();
    let venue_index_by_id: HashMap<String, u32> =
        venues.iter().enumerate().map(|(i, v)| (v.id.clone(), i as u32)).collect();

    // shows は event 添字リンクを張るため events の索引を先に作ってからロードする。
    let shows = load_shows(&conn, &event_index_by_id)?;
    let show_index_by_id: HashMap<String, u32> =
        shows.iter().enumerate().map(|(i, s)| (s.id.clone(), i as u32)).collect();

    // setlist_items は show / song 両方の添字リンクを張る。
    let setlist_items = load_setlist_items(&conn, &show_index_by_id, &song_index_by_id)?;

    // 添字リンクつきの従属テーブル群 (親の索引ができてからロードする)。
    let venue_names = load_venue_names(&conn, &venue_index_by_id)?;
    let venue_halls = load_venue_halls(&conn, &venue_index_by_id)?;
    let idol_voice_actors = load_voice_actors(&conn, &idol_index_by_id)?;
    let event_releases = load_event_releases(&conn, &event_index_by_id, &show_index_by_id)?;

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

    // idol_brands → 双方向リンク (is_primary つき)。is_external の除外はクエリ層。
    let mut idols_by_brand: Vec<Vec<BrandMemberLink>> = vec![Vec::new(); brands.len()];
    let mut brands_by_idol: Vec<Vec<IdolBrandLink>> = vec![Vec::new(); idols.len()];
    {
        let mut stmt = conn
            .prepare("SELECT idol_id, brand_id, is_primary FROM idol_brands")
            .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([], |r| {
                Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, Option<i64>>(2)?))
            })
            .map_err(|e| e.to_string())?;
        for row in rows {
            let (idol_id, brand_id, is_primary) = row.map_err(|e| e.to_string())?;
            let (Some(&ii), Some(&bi)) =
                (idol_index_by_id.get(&idol_id), brand_index_by_id.get(&brand_id))
            else {
                continue;
            };
            let is_primary = is_primary.unwrap_or(0) != 0;
            idols_by_brand[bi as usize].push(BrandMemberLink { idol: ii, is_primary });
            brands_by_idol[ii as usize].push(IdolBrandLink { brand: bi, is_primary });
        }
    }
    for links in &mut idols_by_brand {
        links.sort_by_key(|l| idol_sort_key(&idols, l.idol));
    }
    for links in &mut brands_by_idol {
        links.sort_by_key(|l| (brands[l.brand as usize].sort_order, l.brand));
    }

    // idol_voice_actors → 履歴索引 + CV 名逆引き。
    let mut voice_actors_by_idol: Vec<Vec<u32>> = vec![Vec::new(); idols.len()];
    for (i, va) in idol_voice_actors.iter().enumerate() {
        voice_actors_by_idol[va.idol as usize].push(i as u32);
    }
    for list in &mut voice_actors_by_idol {
        // IFNULL(valid_from,'') DESC (NULL='' は DESC で末尾)。同値は添字で決定的に。
        list.sort_by_key(|&i| {
            let va = &idol_voice_actors[i as usize];
            (std::cmp::Reverse(va.valid_from.clone().unwrap_or_default()), i)
        });
    }
    let mut idols_by_voice_actor_name: HashMap<String, Vec<u32>> = HashMap::new();
    for va in &idol_voice_actors {
        idols_by_voice_actor_name.entry(va.name.clone()).or_default().push(va.idol);
    }
    for list in idols_by_voice_actor_name.values_mut() {
        // DISTINCT + ORDER BY sort_order。キーに添字が入るので同一 idol は隣接し dedup で消える。
        list.sort_by_key(|&i| idol_sort_key(&idols, i));
        list.dedup();
    }

    // venue_names / venue_halls → venue 添字で束ねる (並びはテーブル出現順のまま)。
    let mut names_by_venue: Vec<Vec<u32>> = vec![Vec::new(); venues.len()];
    for (i, vn) in venue_names.iter().enumerate() {
        names_by_venue[vn.venue as usize].push(i as u32);
    }
    let mut halls_by_venue: Vec<Vec<u32>> = vec![Vec::new(); venues.len()];
    for (i, vh) in venue_halls.iter().enumerate() {
        halls_by_venue[vh.venue as usize].push(i as u32);
    }

    // 会場 → 公演 (date DESC)。venue_id と生文字列の両方を持つのは、
    // ID 未付与の過去公演を「ID 一致 or 生文字列一致」の OR で拾う後方互換のため。
    let show_date_desc_key = |i: u32| {
        let s = &shows[i as usize];
        (std::cmp::Reverse(s.date.clone()), s.sort_order, i)
    };
    let mut shows_by_venue_id: HashMap<String, Vec<u32>> = HashMap::new();
    let mut shows_by_venue_label: HashMap<String, Vec<u32>> = HashMap::new();
    for (i, show) in shows.iter().enumerate() {
        if let Some(vid) = &show.venue_id {
            shows_by_venue_id.entry(vid.clone()).or_default().push(i as u32);
        }
        if let Some(label) = &show.venue {
            shows_by_venue_label.entry(label.clone()).or_default().push(i as u32);
        }
    }
    for list in shows_by_venue_id.values_mut() {
        list.sort_by_key(|&i| show_date_desc_key(i));
    }
    for list in shows_by_venue_label.values_mut() {
        list.sort_by_key(|&i| show_date_desc_key(i));
    }

    // event_releases → (release_date ASC NULL 先頭, sort_order ASC)。
    let mut releases_by_event: Vec<Vec<u32>> = vec![Vec::new(); events.len()];
    for (i, er) in event_releases.iter().enumerate() {
        releases_by_event[er.event as usize].push(i as u32);
    }
    for list in &mut releases_by_event {
        list.sort_by(|&a, &b| {
            let (ra, rb) = (&event_releases[a as usize], &event_releases[b as usize]);
            (&ra.release_date, ra.sort_order, a).cmp(&(&rb.release_date, rb.sort_order, b))
        });
    }

    // 全体並びの前計算 (SQL 時代に毎回払っていた ORDER BY)。
    let mut brand_order: Vec<u32> = (0..brands.len() as u32).collect();
    brand_order.sort_by_key(|&i| (brands[i as usize].sort_order, i));
    let mut idol_order: Vec<u32> = (0..idols.len() as u32).collect();
    idol_order.sort_by_key(|&i| idol_sort_key(&idols, i));
    let mut unit_order: Vec<u32> = (0..units.len() as u32).collect();
    unit_order.sort_by(|&a, &b| {
        let (ua, ub) = (&units[a as usize], &units[b as usize]);
        (&ua.brand_id, &ua.name, a).cmp(&(&ub.brand_id, &ub.name, b))
    });
    let mut venue_order: Vec<u32> = (0..venues.len() as u32).collect();
    venue_order.sort_by_key(|&i| (venues[i as usize].sort_order, i));
    let mut anniversary_order: Vec<u32> = (0..anniversaries.len() as u32).collect();
    anniversary_order.sort_by(|&a, &b| {
        (&anniversaries[a as usize].date, a).cmp(&(&anniversaries[b as usize].date, b))
    });
    let mut shows_in_date_order: Vec<u32> = (0..shows.len() as u32).collect();
    shows_in_date_order.sort_by(|&a, &b| {
        let (sa, sb) = (&shows[a as usize], &shows[b as usize]);
        (&sa.date, sa.sort_order, a).cmp(&(&sb.date, sb.sort_order, b))
    });
    let mut events_by_name_order: Vec<u32> = (0..events.len() as u32).collect();
    events_by_name_order.sort_by(|&a, &b| {
        (&events[a as usize].name, a).cmp(&(&events[b as usize].name, b))
    });

    Ok(Snapshot {
        songs,
        idols,
        events,
        shows,
        setlist_items,
        units,
        brands,
        creator_spellings: creators
            .iter()
            .map(|c| {
                // 読み・表記・別表記をまとめて 1 人ぶんの綴り列にする。
                // `aliases` は改行区切り (曲側に現れる「烏屋茶房」以外の書き方)。
                let mut v = vec![c.name.clone(), c.name_kana.clone()];
                if let Some(a) = &c.aliases {
                    v.extend(a.lines().map(str::trim).filter(|l| !l.is_empty()).map(str::to_string));
                }
                v
            })
            .collect(),
        creators,
        venues,
        venue_names,
        venue_halls,
        staff,
        anniversaries,
        idol_voice_actors,
        event_releases,
        meta,
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
        idols_by_brand,
        brands_by_idol,
        voice_actors_by_idol,
        idols_by_voice_actor_name,
        names_by_venue,
        halls_by_venue,
        shows_by_venue_id,
        shows_by_venue_label,
        releases_by_event,
        brand_order,
        idol_order,
        unit_order,
        venue_order,
        anniversary_order,
        shows_in_date_order,
        events_by_name_order,
        song_index_by_id,
        idol_index_by_id,
        event_index_by_id,
        show_index_by_id,
        unit_index_by_id,
        brand_index_by_id,
        venue_index_by_id,
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

/// PRAGMA table_info の列名集合。Documents 専用列の有無検出に使う。
fn table_columns(conn: &Connection, table: &str) -> Result<HashSet<String>, String> {
    let mut stmt = conn
        .prepare(&format!("PRAGMA table_info({table})"))
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| r.get::<_, String>(1))
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<_, _>>().map_err(|e| e.to_string())
}

/// 表の有無 (Documents 専用表の検出)。
fn table_exists(conn: &Connection, table: &str) -> Result<bool, String> {
    conn.query_row(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
        |r| r.get::<_, i64>(0),
    )
    .map(|n| n > 0)
    .map_err(|e| e.to_string())
}

/// Documents 専用列の SELECT 断片: あれば列名・無ければ `NULL AS 列名`。
/// 列が無い DB でも同じ列数・同じ添字で読めるようにするための細工。
fn optional_col(cols: &HashSet<String>, name: &str) -> String {
    if cols.contains(name) {
        name.to_string()
    } else {
        format!("NULL AS {name}")
    }
}

fn load_songs(conn: &Connection) -> Result<Vec<Song>, String> {
    // jasrac_code は iOS 側にしか無い列 (JASRAC 許諾は認可待ちで Android スキーマ未追加)。
    // 無ければ NULL を選ぶ: 列の有無でスナップショット全体を落とさないため。
    let jasrac = if table_columns(conn, "songs")?.contains("jasrac_code") {
        "jasrac_code"
    } else {
        "NULL AS jasrac_code"
    };
    let mut stmt = conn
        .prepare(
            &format!("SELECT id, title, title_kana, brand_id, song_type, release_date, duration_sec,
                    composer, lyricist, arranger, cd_series, cd_title, artwork_url, preview_url,
                    apple_music_id, apple_music_album_id, isrc, lyrics_url, parent_song_id,
                    singer_label, unit_name, unit_id, series_group, {jasrac}
             FROM songs"),
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
            "SELECT id, brand_id, name, name_kana, name_romaji, color, sort_order, birthday,
                    blood_type, height, weight, birth_place, age, bust, waist, hip,
                    constellation, hobbies, talents, description, gender, handedness,
                    family_name, given_name, nickname, debut_date, attribute, is_external,
                    aliases
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
                name_romaji: r.get(4)?,
                color: r.get(5)?,
                sort_order: r.get(6)?,
                birthday: r.get(7)?,
                blood_type: r.get(8)?,
                height: r.get(9)?,
                weight: r.get(10)?,
                birth_place: r.get(11)?,
                age: r.get(12)?,
                bust: r.get(13)?,
                waist: r.get(14)?,
                hip: r.get(15)?,
                constellation: r.get(16)?,
                hobbies: r.get(17)?,
                talents: r.get(18)?,
                description: r.get(19)?,
                gender: r.get(20)?,
                handedness: r.get(21)?,
                family_name: r.get(22)?,
                given_name: r.get(23)?,
                nickname: r.get(24)?,
                debut_date: r.get(25)?,
                attribute: r.get(26)?,
                is_external: r.get::<_, Option<i64>>(27)?.unwrap_or(0) != 0,
                aliases: r.get(28)?,
            })
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<_, _>>().map_err(|e| e.to_string())
}

fn load_events(conn: &Connection) -> Result<Vec<Event>, String> {
    let cols = table_columns(conn, "events")?;
    let sql = format!(
        "SELECT id, brand_id, name, event_type, is_streaming, is_solo, kind,
                ticket_open_date, ticket_deadline, ticket_lottery_date, ticket_url,
                joint_brand_ids, {has_streaming}, {has_live_viewing}, {name_kana}
         FROM events",
        has_streaming = optional_col(&cols, "has_streaming"),
        has_live_viewing = optional_col(&cols, "has_live_viewing"),
        // 後から足した列。移行前の DB (Android の Room 版が上がる前) には無いので守る。
        name_kana = optional_col(&cols, "name_kana"),
    );
    let mut stmt = conn.prepare(&sql).map_err(|e| e.to_string())?;
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
                // Documents 専用列。列が無い DB では NULL 定数列 → None。
                has_streaming: r.get::<_, Option<i64>>(12)?.map(|v| v != 0),
                has_live_viewing: r.get::<_, Option<i64>>(13)?.map(|v| v != 0),
                name_kana: r.get(14)?,
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
    let cols = table_columns(conn, "shows")?;
    let sql = format!(
        "SELECT id, event_id, name, date, venue, venue_city, start_time, sort_order,
                performer_type, venue_id, hall, stream_platform,
                {has_streaming}, {has_live_viewing}
         FROM shows",
        has_streaming = optional_col(&cols, "has_streaming"),
        has_live_viewing = optional_col(&cols, "has_live_viewing"),
    );
    let mut stmt = conn.prepare(&sql).map_err(|e| e.to_string())?;
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
                r.get::<_, Option<i64>>(12)?,
                r.get::<_, Option<i64>>(13)?,
            ))
        })
        .map_err(|e| e.to_string())?;
    let mut shows = Vec::new();
    for row in rows {
        let (id, event_id, name, date, venue, venue_city, start_time, sort_order, performer_type, venue_id, hall, stream_platform, has_streaming, has_live_viewing) =
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
            has_streaming: has_streaming.map(|v| v != 0),
            has_live_viewing: has_live_viewing.map(|v| v != 0),
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

fn load_brands(conn: &Connection) -> Result<Vec<Brand>, String> {
    let cols = table_columns(conn, "brands")?;
    let sql = format!(
        "SELECT id, name, short_name, color, sort_order, {icon_url} FROM brands",
        icon_url = optional_col(&cols, "icon_url"),
    );
    let mut stmt = conn.prepare(&sql).map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok(Brand {
                id: r.get(0)?,
                name: r.get(1)?,
                short_name: r.get(2)?,
                color: r.get(3)?,
                sort_order: r.get::<_, Option<i64>>(4)?.unwrap_or(0),
                icon_url: r.get(5)?,
            })
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<_, _>>().map_err(|e| e.to_string())
}

/// 作家の読み。テーブルが無い DB (旧スキーマの端末) では空で返す。
///
/// 空でも一覧やクレジット表示は動く (かなで引けなくなるだけ) ので、
/// ここで読み込みを失敗させて**スナップショット全体を落とす方が損失が大きい**。
/// Android は `idol_voice_actors` を持たない等、端末ごとに表が欠けることが実際にある。
fn load_creators(conn: &Connection) -> Result<Vec<Creator>, String> {
    let mut stmt = match conn.prepare("SELECT id, name, name_kana, aliases FROM creators") {
        Ok(s) => s,
        Err(_) => return Ok(Vec::new()),
    };
    let rows = stmt
        .query_map([], |r| {
            Ok(Creator {
                id: r.get(0)?,
                name: r.get(1)?,
                name_kana: r.get(2)?,
                aliases: r.get(3)?,
            })
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<_, _>>().map_err(|e| e.to_string())
}

fn load_venues(conn: &Connection) -> Result<Vec<Venue>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, name, name_kana, prefecture, city, aliases, capacity, sort_order
             FROM venues",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok(Venue {
                id: r.get(0)?,
                name: r.get(1)?,
                name_kana: r.get(2)?,
                prefecture: r.get(3)?,
                city: r.get(4)?,
                aliases: r.get(5)?,
                capacity: r.get(6)?,
                sort_order: r.get::<_, Option<i64>>(7)?.unwrap_or(0),
            })
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<_, _>>().map_err(|e| e.to_string())
}

/// venue_names をロードする。親 venue が存在しない FK 孤児は読み飛ばす。
fn load_venue_names(
    conn: &Connection,
    venue_index_by_id: &HashMap<String, u32>,
) -> Result<Vec<VenueName>, String> {
    let mut stmt = conn
        .prepare("SELECT id, venue_id, name, valid_from, valid_to FROM venue_names")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, Option<String>>(3)?,
                r.get::<_, Option<String>>(4)?,
            ))
        })
        .map_err(|e| e.to_string())?;
    let mut names = Vec::new();
    for row in rows {
        let (id, venue_id, name, valid_from, valid_to) = row.map_err(|e| e.to_string())?;
        let Some(&venue) = venue_index_by_id.get(&venue_id) else { continue };
        names.push(VenueName { id, venue, name, valid_from, valid_to });
    }
    Ok(names)
}

/// venue_halls をロードする。親 venue が存在しない FK 孤児は読み飛ばす。
fn load_venue_halls(
    conn: &Connection,
    venue_index_by_id: &HashMap<String, u32>,
) -> Result<Vec<VenueHall>, String> {
    let mut stmt = conn
        .prepare("SELECT id, venue_id, name, capacity FROM venue_halls")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, Option<i64>>(3)?,
            ))
        })
        .map_err(|e| e.to_string())?;
    let mut halls = Vec::new();
    for row in rows {
        let (id, venue_id, name, capacity) = row.map_err(|e| e.to_string())?;
        let Some(&venue) = venue_index_by_id.get(&venue_id) else { continue };
        halls.push(VenueHall { id, venue, name, capacity });
    }
    Ok(halls)
}

fn load_staff(conn: &Connection) -> Result<Vec<Staff>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, brand_id, name, name_kana, name_romaji, role, birthday, sort_order
             FROM staff",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok(Staff {
                id: r.get(0)?,
                brand_id: r.get(1)?,
                name: r.get(2)?,
                name_kana: r.get(3)?,
                name_romaji: r.get(4)?,
                role: r.get(5)?,
                birthday: r.get(6)?,
                sort_order: r.get::<_, Option<i64>>(7)?.unwrap_or(0),
            })
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<_, _>>().map_err(|e| e.to_string())
}

fn load_anniversaries(conn: &Connection) -> Result<Vec<Anniversary>, String> {
    let mut stmt = conn
        .prepare("SELECT id, brand_id, label, date, kind, sort_order FROM anniversaries")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok(Anniversary {
                id: r.get(0)?,
                brand_id: r.get(1)?,
                label: r.get(2)?,
                date: r.get(3)?,
                kind: r.get(4)?,
                sort_order: r.get::<_, Option<i64>>(5)?.unwrap_or(0),
            })
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<_, _>>().map_err(|e| e.to_string())
}

/// idol_voice_actors をロードする。親 idol が存在しない FK 孤児は読み飛ばす。
///
/// ⚠️ このテーブルは iOS (GRDB) にしか無い。Android の Room はエンティティを持たず、
/// SeedImporter が「Room と seed の両方にあるテーブル」しか取り込まないため実機に存在しない。
/// 無ければ空で継続する (ここで失敗させるとスナップショット全体がロード不能になる)。
/// Android に載せれば CV 名検索もコアへ寄せられる。
fn load_voice_actors(
    conn: &Connection,
    idol_index_by_id: &HashMap<String, u32>,
) -> Result<Vec<IdolVoiceActor>, String> {
    if !table_exists(conn, "idol_voice_actors")? {
        return Ok(Vec::new());
    }
    let mut stmt = conn
        .prepare("SELECT id, idol_id, name, valid_from, valid_to FROM idol_voice_actors")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, Option<String>>(3)?,
                r.get::<_, Option<String>>(4)?,
            ))
        })
        .map_err(|e| e.to_string())?;
    let mut actors = Vec::new();
    for row in rows {
        let (id, idol_id, name, valid_from, valid_to) = row.map_err(|e| e.to_string())?;
        let Some(&idol) = idol_index_by_id.get(&idol_id) else { continue };
        actors.push(IdolVoiceActor { id, idol, name, valid_from, valid_to });
    }
    Ok(actors)
}

/// event_releases をロードする。Documents 専用表なので、表が無い DB (Bundle) では空を返す。
/// 親 event が孤児の行は読み飛ばす。show_id は孤児でも行自体は残す (イベント全体 BOX と
/// 同じ「公演不明」扱いに落とす方が、円盤ごと消すより被害が小さい)。
fn load_event_releases(
    conn: &Connection,
    event_index_by_id: &HashMap<String, u32>,
    show_index_by_id: &HashMap<String, u32>,
) -> Result<Vec<EventRelease>, String> {
    if !table_exists(conn, "event_releases")? {
        return Ok(Vec::new());
    }
    let mut stmt = conn
        .prepare(
            "SELECT id, event_id, show_id, product_type, title, catalog_number, release_date,
                    jacket_url, purchase_url, sort_order
             FROM event_releases",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, Option<String>>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, String>(4)?,
                r.get::<_, Option<String>>(5)?,
                r.get::<_, Option<String>>(6)?,
                r.get::<_, Option<String>>(7)?,
                r.get::<_, Option<String>>(8)?,
                r.get::<_, Option<i64>>(9)?,
            ))
        })
        .map_err(|e| e.to_string())?;
    let mut releases = Vec::new();
    for row in rows {
        let (id, event_id, show_id, product_type, title, catalog_number, release_date, jacket_url, purchase_url, sort_order) =
            row.map_err(|e| e.to_string())?;
        let Some(&event) = event_index_by_id.get(&event_id) else { continue };
        let show = show_id.as_ref().and_then(|sid| show_index_by_id.get(sid)).copied();
        releases.push(EventRelease {
            id,
            event,
            show,
            product_type,
            title,
            catalog_number,
            release_date,
            jacket_url,
            purchase_url,
            sort_order: sort_order.unwrap_or(0),
        });
    }
    Ok(releases)
}

/// meta 表 (key → value)。value NULL の行は載せない (getValue の観測結果は行なしと同じ)。
fn load_meta(conn: &Connection) -> Result<HashMap<String, String>, String> {
    let mut stmt = conn.prepare("SELECT key, value FROM meta").map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?)))
        .map_err(|e| e.to_string())?;
    let mut meta = HashMap::new();
    for row in rows {
        let (key, value) = row.map_err(|e| e.to_string())?;
        if let Some(value) = value {
            meta.insert(key, value);
        }
    }
    Ok(meta)
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
        assert!(s.brands.len() >= 5, "brands={}", s.brands.len());
        assert!(s.venues.len() >= 100, "venues={}", s.venues.len());
        // 「◯◯_by_△△」は△△側と同じ長さ (添字リンクの前提)。
        assert_eq!(s.songs.len(), s.artists_by_song.len());
        assert_eq!(s.songs.len(), s.performance_counts.len());
        assert_eq!(s.songs.len(), s.setlist_items_by_song.len());
        assert_eq!(s.songs.len(), s.variants_by_song.len());
        assert_eq!(s.idols.len(), s.songs_by_idol.len());
        assert_eq!(s.idols.len(), s.performed_items_by_idol.len());
        assert_eq!(s.idols.len(), s.cast_shows_by_idol.len());
        assert_eq!(s.idols.len(), s.units_by_idol.len());
        assert_eq!(s.idols.len(), s.brands_by_idol.len());
        assert_eq!(s.idols.len(), s.voice_actors_by_idol.len());
        assert_eq!(s.events.len(), s.shows_by_event.len());
        assert_eq!(s.events.len(), s.releases_by_event.len());
        assert_eq!(s.shows.len(), s.setlist_items_by_show.len());
        assert_eq!(s.shows.len(), s.cast_by_show.len());
        assert_eq!(s.setlist_items.len(), s.performers_by_item.len());
        assert_eq!(s.units.len(), s.members_by_unit.len());
        assert_eq!(s.units.len(), s.songs_by_unit.len());
        assert_eq!(s.brands.len(), s.idols_by_brand.len());
        assert_eq!(s.venues.len(), s.names_by_venue.len());
        assert_eq!(s.venues.len(), s.halls_by_venue.len());
        // 全体並びは全件をちょうど 1 回ずつ含む
        assert_eq!(s.brand_order.len(), s.brands.len());
        assert_eq!(s.idol_order.len(), s.idols.len());
        assert_eq!(s.unit_order.len(), s.units.len());
        assert_eq!(s.venue_order.len(), s.venues.len());
        assert_eq!(s.anniversary_order.len(), s.anniversaries.len());
        assert_eq!(s.shows_in_date_order.len(), s.shows.len());
        assert_eq!(s.events_by_name_order.len(), s.events.len());
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
        for (i, brand) in s.brands.iter().enumerate() {
            assert_eq!(s.brand_index_by_id[&brand.id] as usize, i);
        }
        for (i, venue) in s.venues.iter().enumerate().step_by(13) {
            assert_eq!(s.venue_index_by_id[&venue.id] as usize, i);
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
        assert_eq!(s.brands.len(), count("SELECT COUNT(*) FROM brands"));
        assert_eq!(s.venues.len(), count("SELECT COUNT(*) FROM venues"));
        assert_eq!(s.venue_names.len(), count("SELECT COUNT(*) FROM venue_names"));
        assert_eq!(s.venue_halls.len(), count("SELECT COUNT(*) FROM venue_halls"));
        assert_eq!(s.staff.len(), count("SELECT COUNT(*) FROM staff"));
        assert_eq!(s.anniversaries.len(), count("SELECT COUNT(*) FROM anniversaries"));
        assert_eq!(s.idol_voice_actors.len(), count("SELECT COUNT(*) FROM idol_voice_actors"));
        assert_eq!(s.meta.len(), count("SELECT COUNT(*) FROM meta WHERE value IS NOT NULL"));
        let performer_links: usize = s.performers_by_item.iter().map(Vec::len).sum();
        assert_eq!(performer_links, count("SELECT COUNT(*) FROM setlist_performers"));
        let cast_links: usize = s.cast_by_show.iter().map(Vec::len).sum();
        assert_eq!(cast_links, count("SELECT COUNT(*) FROM show_cast"));
        let member_links: usize = s.members_by_unit.iter().map(Vec::len).sum();
        assert_eq!(member_links, count("SELECT COUNT(*) FROM unit_members"));
        let brand_links: usize = s.idols_by_brand.iter().map(Vec::len).sum();
        assert_eq!(brand_links, count("SELECT COUNT(*) FROM idol_brands"));
        let brand_links_rev: usize = s.brands_by_idol.iter().map(Vec::len).sum();
        assert_eq!(brand_links, brand_links_rev);
        // event_releases は Documents 専用表 → Bundle には無く空でロードされる
        assert!(s.event_releases.is_empty());
        assert!(s.releases_by_event.iter().all(Vec::is_empty));
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
    fn brand_order_matches_sql() {
        // Bundle の brands は sort_order がユニークなので SQL と逐語比較できる。
        let s = snapshot();
        let c = conn();
        let mut stmt = c.prepare("SELECT id FROM brands ORDER BY sort_order").unwrap();
        let sql_ids: Vec<String> =
            stmt.query_map([], |r| r.get(0)).unwrap().collect::<Result<_, _>>().unwrap();
        let snap_ids: Vec<&str> =
            s.brand_order.iter().map(|&i| s.brands[i as usize].id.as_str()).collect();
        assert_eq!(sql_ids, snap_ids);
        // brand() の O(1) 引きも往復すること
        for brand in &s.brands {
            assert_eq!(s.brand(&brand.id).map(|b| b.sort_order), Some(brand.sort_order));
        }
    }

    #[test]
    fn idols_by_brand_match_sql_membership_query() {
        // fetchIdols(brandId:) 相当:
        //   SELECT DISTINCT i.* FROM idols i JOIN idol_brands ib ON i.id = ib.idol_id
        //   WHERE ib.brand_id = ? AND i.is_external = 0 ORDER BY i.sort_order
        // を全ブランドで突き合わせる (Bundle は idols.sort_order がユニークなので逐語一致)。
        let s = snapshot();
        let c = conn();
        for (bi, brand) in s.brands.iter().enumerate() {
            let mut stmt = c
                .prepare(
                    "SELECT DISTINCT i.id FROM idols i
                     JOIN idol_brands ib ON i.id = ib.idol_id
                     WHERE ib.brand_id = ? AND i.is_external = 0
                     ORDER BY i.sort_order",
                )
                .unwrap();
            let sql_ids: Vec<String> = stmt
                .query_map([&brand.id], |r| r.get(0))
                .unwrap()
                .collect::<Result<_, _>>()
                .unwrap();
            let snap_ids: Vec<&str> = s.idols_by_brand[bi]
                .iter()
                .filter(|l| !s.idols[l.idol as usize].is_external)
                .map(|l| s.idols[l.idol as usize].id.as_str())
                .collect();
            assert_eq!(sql_ids, snap_ids, "brand={}", brand.id);
        }
        // 逆引きの往復: brands_by_idol に載る brand の idols_by_brand に自分がいる
        for (ii, links) in s.brands_by_idol.iter().enumerate().step_by(7) {
            for l in links {
                assert!(s.idols_by_brand[l.brand as usize]
                    .iter()
                    .any(|m| m.idol as usize == ii && m.is_primary == l.is_primary));
            }
        }
    }

    #[test]
    fn voice_actor_resolution_matches_sql() {
        // fetchCurrentVoiceActor / fetchVoiceActorHistory / fetchIdolsByVoiceActor の3クエリを
        // 全アイドル・全 CV 名で SQL と突き合わせる。
        let s = snapshot();
        let c = conn();
        for (ii, idol) in s.idols.iter().enumerate() {
            // 現任: WHERE valid_to IS NULL ORDER BY IFNULL(valid_from,'') DESC LIMIT 1
            let sql_current: Option<String> = c
                .query_row(
                    "SELECT name FROM idol_voice_actors
                     WHERE idol_id = ? AND valid_to IS NULL
                     ORDER BY IFNULL(valid_from, '') DESC
                     LIMIT 1",
                    [&idol.id],
                    |r| r.get(0),
                )
                .ok();
            assert_eq!(
                s.current_voice_actor(ii as u32).map(|va| va.name.clone()),
                sql_current,
                "idol={}",
                idol.id
            );
            // 履歴: ORDER BY IFNULL(valid_from,'') DESC (同値は未規定 → 集合一致 + 単調性)
            let mut stmt = c
                .prepare(
                    "SELECT id FROM idol_voice_actors WHERE idol_id = ?
                     ORDER BY IFNULL(valid_from, '') DESC",
                )
                .unwrap();
            let sql_ids: Vec<String> = stmt
                .query_map([&idol.id], |r| r.get(0))
                .unwrap()
                .collect::<Result<_, _>>()
                .unwrap();
            let snap: Vec<&IdolVoiceActor> = s.voice_actors_by_idol[ii]
                .iter()
                .map(|&i| &s.idol_voice_actors[i as usize])
                .collect();
            let snap_ids: std::collections::HashSet<&str> =
                snap.iter().map(|va| va.id.as_str()).collect();
            assert_eq!(sql_ids.len(), snap_ids.len());
            assert!(sql_ids.iter().all(|id| snap_ids.contains(id.as_str())));
            let keys: Vec<String> =
                snap.iter().map(|va| va.valid_from.clone().unwrap_or_default()).collect();
            assert!(keys.windows(2).all(|w| w[0] >= w[1]), "valid_from DESC が崩れている");
        }
        // CV 名逆引き (歴代すべて対象・DISTINCT・sort_order 順)
        for (name, idol_indexes) in &s.idols_by_voice_actor_name {
            let mut stmt = c
                .prepare(
                    "SELECT DISTINCT i.id FROM idols i
                     JOIN idol_voice_actors v ON v.idol_id = i.id
                     WHERE v.name = ?
                     ORDER BY i.sort_order",
                )
                .unwrap();
            let sql_ids: Vec<String> = stmt
                .query_map([name], |r| r.get(0))
                .unwrap()
                .collect::<Result<_, _>>()
                .unwrap();
            let snap_ids: Vec<&str> =
                idol_indexes.iter().map(|&i| s.idols[i as usize].id.as_str()).collect();
            assert_eq!(sql_ids, snap_ids, "va={name}");
        }
    }

    #[test]
    fn venue_directory_matches_sql() {
        let s = snapshot();
        let c = conn();
        // venue_order: Bundle は sort_order ユニークなので逐語一致
        let mut stmt = c.prepare("SELECT id FROM venues ORDER BY sort_order").unwrap();
        let sql_ids: Vec<String> =
            stmt.query_map([], |r| r.get(0)).unwrap().collect::<Result<_, _>>().unwrap();
        let snap_ids: Vec<&str> =
            s.venue_order.iter().map(|&i| s.venues[i as usize].id.as_str()).collect();
        assert_eq!(sql_ids, snap_ids);
        // names / halls の親リンクが正しく束なっていること
        for (vi, names) in s.names_by_venue.iter().enumerate() {
            for &ni in names {
                assert_eq!(s.venue_names[ni as usize].venue as usize, vi);
            }
        }
        for (vi, halls) in s.halls_by_venue.iter().enumerate() {
            for &hi in halls {
                assert_eq!(s.venue_halls[hi as usize].venue as usize, vi);
            }
        }
        let name_links: usize = s.names_by_venue.iter().map(Vec::len).sum();
        assert_eq!(name_links, s.venue_names.len());
        let hall_links: usize = s.halls_by_venue.iter().map(Vec::len).sum();
        assert_eq!(hall_links, s.venue_halls.len());
    }

    #[test]
    fn shows_by_venue_match_sql() {
        // showsByVenue 相当 (venue_id = ? OR venue = ? / ORDER BY date DESC) を
        // 公演数の多い venue_id で突き合わせる。同日内は SQL 未規定 → 集合一致 + 単調性。
        let s = snapshot();
        let c = conn();
        let (vid, list) = s
            .shows_by_venue_id
            .iter()
            .max_by_key(|(_, v)| v.len())
            .expect("venue_id つき公演がある");
        assert!(list.len() >= 5, "最多会場の公演数={}", list.len());
        let mut stmt = c
            .prepare("SELECT id FROM shows WHERE venue_id = ? ORDER BY date DESC")
            .unwrap();
        let sql_ids: Vec<String> =
            stmt.query_map([vid], |r| r.get(0)).unwrap().collect::<Result<_, _>>().unwrap();
        let snap_ids: std::collections::HashSet<&str> =
            list.iter().map(|&i| s.shows[i as usize].id.as_str()).collect();
        assert_eq!(sql_ids.len(), snap_ids.len());
        assert!(sql_ids.iter().all(|id| snap_ids.contains(id.as_str())));
        let dates: Vec<&String> = list.iter().map(|&i| &s.shows[i as usize].date).collect();
        assert!(dates.windows(2).all(|w| w[0] >= w[1]), "date DESC が崩れている");
        // 生文字列マップ: shows.venue を持つ全行が自分のラベルの下に入っている
        for (i, show) in s.shows.iter().enumerate() {
            if let Some(label) = &show.venue {
                assert!(s.shows_by_venue_label[label].contains(&(i as u32)));
            }
        }
    }

    #[test]
    fn shows_in_date_order_supports_calendar_range() {
        // カレンダーの範囲抽出 (WHERE date BETWEEN ? AND ? ORDER BY date, sort_order) が
        // 二分探索 + 部分列で SQL と一致すること。同 (date, sort_order) は未規定 → 集合一致。
        let s = snapshot();
        let c = conn();
        let (start, end) = ("2023-01-01", "2023-12-31");
        let lo = s
            .shows_in_date_order
            .partition_point(|&i| s.shows[i as usize].date.as_str() < start);
        let hi = s
            .shows_in_date_order
            .partition_point(|&i| s.shows[i as usize].date.as_str() <= end);
        let range = &s.shows_in_date_order[lo..hi];
        let mut stmt = c
            .prepare("SELECT id FROM shows WHERE date >= ? AND date <= ? ORDER BY date, sort_order")
            .unwrap();
        let sql_ids: Vec<String> = stmt
            .query_map([start, end], |r| r.get(0))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        assert!(!sql_ids.is_empty(), "2023 年に公演がない Bundle はおかしい");
        let snap_ids: std::collections::HashSet<&str> =
            range.iter().map(|&i| s.shows[i as usize].id.as_str()).collect();
        assert_eq!(sql_ids.len(), snap_ids.len());
        assert!(sql_ids.iter().all(|id| snap_ids.contains(id.as_str())));
        let keys: Vec<(&String, i64)> = range
            .iter()
            .map(|&i| (&s.shows[i as usize].date, s.shows[i as usize].sort_order))
            .collect();
        assert!(keys.windows(2).all(|w| w[0] <= w[1]));
        // 末尾 = 最新公演 (fetchLatestShow の ORDER BY date DESC LIMIT 1 と同じ date)
        let sql_latest: String = c
            .query_row("SELECT MAX(date) FROM shows", [], |r| r.get(0))
            .unwrap();
        let last = *s.shows_in_date_order.last().unwrap();
        assert_eq!(s.shows[last as usize].date, sql_latest);
    }

    #[test]
    fn anniversaries_and_staff_match_sql() {
        let s = snapshot();
        let c = conn();
        // Timeline milestoneBars の ORDER BY date (同日は未規定 → 単調性 + 集合一致)
        let mut stmt = c.prepare("SELECT id FROM anniversaries ORDER BY date").unwrap();
        let sql_ids: Vec<String> =
            stmt.query_map([], |r| r.get(0)).unwrap().collect::<Result<_, _>>().unwrap();
        let snap_ids: std::collections::HashSet<&str> = s
            .anniversary_order
            .iter()
            .map(|&i| s.anniversaries[i as usize].id.as_str())
            .collect();
        assert_eq!(sql_ids.len(), snap_ids.len());
        assert!(sql_ids.iter().all(|id| snap_ids.contains(id.as_str())));
        let dates: Vec<&String> =
            s.anniversary_order.iter().map(|&i| &s.anniversaries[i as usize].date).collect();
        assert!(dates.windows(2).all(|w| w[0] <= w[1]));
        // staff: カレンダーが使う birthday つきの行が SQL と同数
        let sql_staff_bd: usize = c
            .query_row("SELECT COUNT(*) FROM staff WHERE birthday IS NOT NULL", [], |r| {
                r.get::<_, i64>(0)
            })
            .unwrap() as usize;
        let snap_staff_bd = s.staff.iter().filter(|st| st.birthday.is_some()).count();
        assert_eq!(snap_staff_bd, sql_staff_bd);
    }

    #[test]
    fn meta_values_match_sql() {
        let s = snapshot();
        let c = conn();
        let mut stmt = c.prepare("SELECT key, value FROM meta").unwrap();
        let rows: Vec<(String, Option<String>)> = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        assert!(!rows.is_empty());
        for (key, value) in rows {
            assert_eq!(s.meta_value(&key), value.as_deref(), "key={key}");
        }
        assert_eq!(s.meta_value("存在しないキー"), None);
    }

    #[test]
    fn documents_only_fields_default_to_none_on_bundle() {
        // Bundle DB には Documents 専用列が無い → 全行 None で読める (動的検出の既定値側)。
        let s = snapshot();
        assert!(s.events.iter().all(|e| e.has_streaming.is_none() && e.has_live_viewing.is_none()));
        assert!(s.shows.iter().all(|sh| sh.has_streaming.is_none() && sh.has_live_viewing.is_none()));
        assert!(s.brands.iter().all(|b| b.icon_url.is_none()));
    }

    #[test]
    fn documents_only_columns_and_tables_load_when_present() {
        // 移行済み Documents DB を模したミニ DB で動的検出の「あれば読む」側を検証する。
        // has_streaming / has_live_viewing / brands.icon_url / event_releases が実値で返ること。
        let dir = std::env::temp_dir();
        let path = dir.join(format!("imas_core_docs_schema_{}.sqlite", std::process::id()));
        let path_str = path.to_str().unwrap().to_string();
        let _ = std::fs::remove_file(&path);
        {
            let c = Connection::open(&path).unwrap();
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
                     joint_brand_ids TEXT, ticket_open_date TEXT,
                     has_streaming INTEGER, has_live_viewing INTEGER);
                 CREATE TABLE shows (id TEXT PRIMARY KEY, event_id TEXT NOT NULL,
                     name TEXT NOT NULL, date TEXT NOT NULL, venue TEXT, venue_city TEXT,
                     start_time TEXT, sort_order INTEGER NOT NULL DEFAULT 0, performer_type TEXT,
                     venue_id TEXT, hall TEXT, stream_platform TEXT,
                     has_streaming INTEGER, has_live_viewing INTEGER);
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
                     short_name TEXT NOT NULL, color TEXT, sort_order INTEGER NOT NULL,
                     icon_url TEXT);
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
                 CREATE TABLE event_releases (id TEXT PRIMARY KEY, event_id TEXT NOT NULL,
                     show_id TEXT, product_type TEXT NOT NULL, title TEXT NOT NULL,
                     catalog_number TEXT, release_date TEXT, jacket_url TEXT, purchase_url TEXT,
                     sort_order INTEGER NOT NULL DEFAULT 0);
                 INSERT INTO events (id, name, event_type, has_streaming, has_live_viewing)
                     VALUES ('ev1', 'テストライブ', 'live', 1, 0);
                 INSERT INTO shows (id, event_id, name, date, has_streaming, has_live_viewing)
                     VALUES ('sh1', 'ev1', 'DAY1', '2026-01-01', 0, 1),
                            ('sh2', 'ev1', 'DAY2', '2026-01-02', NULL, NULL);
                 INSERT INTO brands (id, name, short_name, sort_order, icon_url)
                     VALUES ('b1', 'テストブランド', 'TB', 1, 'https://example.com/icon.png');
                 INSERT INTO event_releases (id, event_id, show_id, product_type, title,
                                             release_date, sort_order)
                     VALUES ('er2', 'ev1', NULL, 'dvd_box', 'BOX', NULL, 5),
                            ('er1', 'ev1', 'sh1', 'blu_ray', 'DAY1 BD', '2026-06-01', 1),
                            ('er3', 'ev1', 'ghost_show', 'dvd', '孤児show', '2026-06-01', 0),
                            ('er4', 'ghost_event', 'sh1', 'dvd', '孤児event', NULL, 0);
                 INSERT INTO meta (key, value) VALUES ('data_version', '42'), ('nil_key', NULL);",
            )
            .unwrap();
        }
        let s = load_snapshot(&path_str).expect("Documents 相当のミニ DB もロードできる");
        let _ = std::fs::remove_file(&path);

        let ev = s.event("ev1").unwrap();
        assert_eq!(ev.has_streaming, Some(true));
        assert_eq!(ev.has_live_viewing, Some(false));
        let sh1 = s.show("sh1").unwrap();
        assert_eq!(sh1.has_streaming, Some(false));
        assert_eq!(sh1.has_live_viewing, Some(true));
        let sh2 = s.show("sh2").unwrap();
        assert_eq!(sh2.has_streaming, None);
        assert_eq!(sh2.has_live_viewing, None);
        assert_eq!(s.brand("b1").unwrap().icon_url.as_deref(), Some("https://example.com/icon.png"));

        // event_releases: 親 event 孤児 (er4) だけ落ち、show 孤児 (er3) は show=None で残る。
        assert_eq!(s.event_releases.len(), 3);
        let ei = s.event_index_by_id["ev1"] as usize;
        let titles: Vec<&str> = s.releases_by_event[ei]
            .iter()
            .map(|&i| s.event_releases[i as usize].title.as_str())
            .collect();
        // (release_date ASC NULL 先頭, sort_order ASC): BOX(NULL,5) → 孤児show(6/1,0) → DAY1 BD(6/1,1)
        assert_eq!(titles, vec!["BOX", "孤児show", "DAY1 BD"]);
        let orphan = s.event_releases.iter().find(|er| er.title == "孤児show").unwrap();
        assert!(orphan.show.is_none());
        let day1 = s.event_releases.iter().find(|er| er.title == "DAY1 BD").unwrap();
        assert_eq!(day1.show.map(|i| s.shows[i as usize].id.clone()).as_deref(), Some("sh1"));

        // meta: NULL 値の行は「行なし」と同じ観測になる
        assert_eq!(s.meta_value("data_version"), Some("42"));
        assert_eq!(s.meta_value("nil_key"), None);
    }

    #[test]
    fn missing_file_is_an_error_not_a_panic() {
        assert!(load_snapshot("/nonexistent/never.sqlite").is_err());
    }
    /// Android (Room) は idol_voice_actors エンティティを持たず、SeedImporter が
    /// 「Room と seed の両方にあるテーブル」しか取り込まないため実機 DB に存在しない。
    /// songs.jasrac_code も iOS 専用列。どちらも欠けた DB でロードが通ることを固定する
    /// (以前はここで load 全体が失敗し、Android のスナップショットが常に未ロードだった)。
    #[test]
    fn loads_when_ios_only_table_and_column_are_absent() {
        let dir = std::env::temp_dir().join(format!("imas_core_android_shape_{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let path = dir.join("android_like.sqlite");
        let _ = std::fs::remove_file(&path);
        {
            let src = Connection::open_with_flags(bundle_db(), OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
            let names: Vec<String> = {
                let mut stmt = src
                    .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name <> 'idol_voice_actors'")
                    .unwrap();
                let rows = stmt.query_map([], |r| r.get::<_, String>(0)).unwrap();
                rows.filter_map(Result::ok).collect()
            };
            let dst = Connection::open(&path).unwrap();
            dst.execute("ATTACH DATABASE ? AS src", [bundle_db()]).unwrap();
            for t in &names {
                let sql: Option<String> = src
                    .query_row("SELECT sql FROM sqlite_master WHERE type='table' AND name=?", [t], |r| r.get(0))
                    .unwrap_or(None);
                let Some(mut sql) = sql else { continue };
                if t == "songs" {
                    // iOS 専用列を落とした songs を作る
                    sql = sql.replace(", jasrac_code TEXT", "").replace("jasrac_code TEXT,", "");
                }
                if dst.execute_batch(&sql).is_err() { continue }
                let cols: Vec<String> = {
                    let mut stmt = dst.prepare(&format!("PRAGMA table_info({t})")).unwrap();
                    let rows = stmt.query_map([], |r| r.get::<_, String>(1)).unwrap();
                    rows.filter_map(Result::ok).collect()
                };
                let list = cols.join(",");
                let _ = dst.execute_batch(&format!("INSERT INTO {t} ({list}) SELECT {list} FROM src.{t}"));
            }
            dst.execute_batch("DETACH DATABASE src").unwrap();
        }

        let snap = load_snapshot(path.to_str().unwrap())
            .expect("iOS 専用の表・列が無くてもロードできる");
        assert!(snap.songs.len() >= 3000, "songs={}", snap.songs.len());
        assert!(snap.songs.iter().all(|s| s.jasrac_code.is_none()));
        let _ = std::fs::remove_file(&path);
    }
}
