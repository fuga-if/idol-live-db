//! 生テーブル群 → `Snapshot` の索引構築 (純粋・DB 非依存)。
//!
//! SQLite から読んだ生の行 (`RawTables`) だけを入力に取り、`Snapshot` の逆引き索引と
//! 前計算済みの並びを組み立てる。ここに SQLite ドライバは持ち込まない: ブラウザ (wasm) からも
//! 同じ構築コードで `Snapshot` を作れるようにするため
//! (`outbound` は wasm 対象から除外されている)。
//!
//! 並び順の規約は `domain/snapshot.rs` の各フィールド doc が正。

use std::collections::{BTreeMap, HashMap};

use crate::domain::snapshot::{
    Anniversary, Brand, BrandMemberLink, Creator, Event, EventRelease, Idol, IdolBrandLink,
    IdolSongLink,
    IdolVoiceActor, SetlistItem, Show, ShowCastLink, Snapshot, Song, SongArtistLink, Staff, Unit,
    Venue, VenueHall, VenueName,
};
use crate::domain::text_search_index::TextSearchIndex;

/// `Snapshot` を組むのに要る生テーブル一式。
///
/// 添字リンク (`Show::event` など) を持つ表は、親の id→添字マップで解決済みの状態で渡す
/// (どこで読んだかに依らず、ここに来る時点でリンクは張られている)。
/// 結合表 5 つ (`song_artists` / `setlist_performers` / `show_cast` / `unit_members` /
/// `idol_brands`) だけは素の行のまま渡し、添字への解決は `build` が行う。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RawTables {
    pub songs: Vec<Song>,
    pub idols: Vec<Idol>,
    pub events: Vec<Event>,
    pub units: Vec<Unit>,
    pub brands: Vec<Brand>,
    pub creators: Vec<Creator>,
    pub venues: Vec<Venue>,
    pub staff: Vec<Staff>,
    pub anniversaries: Vec<Anniversary>,
    /// **順序の決まった型で持つ。** ここは配る形でもあるので、`HashMap` だと
    /// 実行のたびに JSON のキー順が変わり、出力が byte 一致しなくなる。
    pub meta: BTreeMap<String, String>,
    pub shows: Vec<Show>,
    pub setlist_items: Vec<SetlistItem>,
    pub venue_names: Vec<VenueName>,
    pub venue_halls: Vec<VenueHall>,
    pub idol_voice_actors: Vec<IdolVoiceActor>,
    pub event_releases: Vec<EventRelease>,
    /// (song_id, idol_id, role)
    pub song_artists: Vec<(String, String, Option<String>)>,
    /// (setlist_item_id, idol_id)
    pub setlist_performers: Vec<(String, String)>,
    /// (show_id, idol_id, cast_role)
    pub show_cast: Vec<(String, String, Option<String>)>,
    /// (unit_id, idol_id)
    pub unit_members: Vec<(String, String)>,
    /// (idol_id, brand_id, is_primary)
    pub idol_brands: Vec<(String, String, Option<i64>)>,
}

/// 生テーブルから `Snapshot` を組む。
pub fn build(raw: RawTables) -> Snapshot {
    let RawTables {
        songs,
        idols,
        events,
        units,
        brands,
        creators,
        venues,
        staff,
        anniversaries,
        meta,
        shows,
        setlist_items,
        venue_names,
        venue_halls,
        idol_voice_actors,
        event_releases,
        song_artists,
        setlist_performers,
        show_cast,
        unit_members,
        idol_brands,
    } = raw;

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

    let show_index_by_id: HashMap<String, u32> =
        shows.iter().enumerate().map(|(i, s)| (s.id.clone(), i as u32)).collect();

    // 以降は逆引き索引の構築。並び順の規約 (どの SQL の ORDER BY を前計算したものか) は
    // domain/snapshot.rs の各フィールド doc が正。ここでは同じ順序でソートを払う。

    // song_artists → 双方向リンク。
    let mut artists_by_song: Vec<Vec<SongArtistLink>> = vec![Vec::new(); songs.len()];
    let mut songs_by_idol: Vec<Vec<IdolSongLink>> = vec![Vec::new(); idols.len()];
    {
        for (song_id, idol_id, role) in song_artists {
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
        for (item_id, idol_id) in setlist_performers {
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
        for (show_id, idol_id, cast_role) in show_cast {
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
        for (unit_id, idol_id) in unit_members {
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
        for (idol_id, brand_id, is_primary) in idol_brands {
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

    // 検索用の畳み込みは**ここで 1 回だけ**やる。打鍵ごとに行を畳むと
    // 1 文字ごとに char::to_lowercase が走り、曲名検索が 7.4ms かかっていた。
    let song_search = songs
        .iter()
        .map(|s| TextSearchIndex::new([Some(s.title.as_str()), s.title_kana.as_deref()].into_iter().flatten()))
        .collect();
    // 横断検索は名前と読みだけ (元 SQL がそう)。広げると当たり方が変わる。
    let idol_search = idols
        .iter()
        .map(|d| TextSearchIndex::new([Some(d.name.as_str()), d.name_kana.as_deref()].into_iter().flatten()))
        .collect();
    // ピッカーはローマ字・別名・CV 名まで見る (声優名で探すのが主要な導線)。
    let idol_picker_search = idols
        .iter()
        .enumerate()
        .map(|(i, d)| {
            let mut v: Vec<&str> = [
                Some(d.name.as_str()),
                d.name_kana.as_deref(),
                d.name_romaji.as_deref(),
                d.aliases.as_deref(),
            ]
            .into_iter()
            .flatten()
            .collect();
            v.extend(
                voice_actors_by_idol[i]
                    .iter()
                    .map(|&a| idol_voice_actors[a as usize].name.as_str()),
            );
            TextSearchIndex::new(v)
        })
        .collect();
    let event_search = events
        .iter()
        .map(|e| TextSearchIndex::new([Some(e.name.as_str()), e.name_kana.as_deref()].into_iter().flatten()))
        .collect();
    let show_venue_search = shows
        .iter()
        .map(|sh| TextSearchIndex::new(sh.venue.as_deref()))
        .collect();
    let venue_search = venues
        .iter()
        .map(|v| {
            let mut spellings: Vec<&str> =
                [Some(v.name.as_str()), v.name_kana.as_deref()].into_iter().flatten().collect();
            // 別名は改行区切り (改名前の名前・略称)。1 行ずつ別のフィールドにする。
            if let Some(a) = &v.aliases {
                spellings.extend(a.lines().map(str::trim).filter(|l| !l.is_empty()));
            }
            TextSearchIndex::new(spellings)
        })
        .collect();

    Snapshot {
        song_search,
        idol_search,
        idol_picker_search,
        event_search,
        show_venue_search,
        venue_search,
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
    }
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
