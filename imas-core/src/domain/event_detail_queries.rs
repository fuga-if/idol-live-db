//! イベント詳細まわりのスナップショットクエリ (純粋ロジック)。
//!
//! SQL 時代の対応 (iOS の分割ファイル横断):
//! - [`shows_by_event`]                 ← AppDatabase+EventQueries.fetchShowsByEventQuery
//! - [`show_record`]                    ← AppDatabase+SongQueries.fetchShowQuery
//! - [`latest_show`]                    ← AppDatabase+StatsQueries.fetchLatestShowQuery
//! - [`setlist`]                        ← AppDatabase+EventQueries.fetchSetlistQuery
//! - [`setlist_performers_by_item`]     ← AppDatabase+EventQueries.fetchAllPerformersQuery
//! - [`show_cast_idol_ids`]             ← AppDatabase+IdolQueries.fetchShowIdolIdsQuery と
//!   fetchShowCastIdolsQuery (同一データの 2 表現なので 1 本化)
//! - [`original_artist_ids_map`]        ← AppDatabase+EventQueries.fetchOriginalArtistIdsQuery
//! - [`original_song_ids_for_show_cast`]← AppDatabase+EventQueries.fetchOriginalSongIdsQuery
//! - [`shows_at_venue`] / [`shows_on_date`] ← AppDatabase+EventQueries.showsByVenueQuery / showsByDateQuery
//! - [`all_shows_with_event_name`]      ← AppDatabase+EventQueries.fetchAllShowsQuery
//! - [`search_shows_with_event_name`]   ← AppDatabase+EventQueries.searchShowsQuery
//! - [`venue_directory`]                ← AppDatabase+EventQueries.fetchVenueDirectoryQuery
//! - [`event_ids_at_venue`]             ← AppDatabase+EventQueries.fetchEventIdsAtVenueQuery
//! - [`venues_matching`]                ← AppDatabase+EventQueries.fetchVenuesMatchingQuery
//! - [`event_record`]                   ← AppDatabase+SongQueries.fetchEventQuery
//! - [`event_stats`]                    ← AppDatabase+EventQueries.fetchEventStatsQuery
//! - [`event_attendance`]               ← AppDatabase+EventQueries.fetchEventAttendanceQuery
//! - [`event_releases`]                 ← AppDatabase+SongQueries.fetchEventReleasesQuery
//!
//! SQL の暗黙挙動をコードで明示して固定する (等価性はテストの照合で保証):
//! - `ORDER BY` の NULL 位置: SQLite は ASC で NULL 先頭 / DESC で NULL 末尾。
//!   Rust の `Option` は `None < Some` なので ASC はそのまま一致する。
//! - 文字列比較は BINARY 照合 (= バイト列比較)。Rust の `str` の `Ord` と同じ。
//! - `LIKE '%q%'` は ASCII だけ大文字小文字を無視する部分一致 (song_list_queries と同じ実装)。
//! - `SELECT DISTINCT` / `Set` 化で SQL が並びを未規定にしていた箇所は、添字または
//!   idol の sort_order を最終キーにして決定的にする (プラットフォーム間で同一結果を
//!   返すのが共有コアの目的なので、非決定性は残さない)。

use crate::domain::snapshot::Snapshot;
use std::cmp::Reverse;
use std::collections::{HashMap, HashSet};

// =============================================================================
// FFI 射影 Record (uniffi は型 derive のみ / ロジックはこのファイルの関数側)
// =============================================================================

/// shows 1 行の全域射影 (GRDB `Show` 相当)。event 添字は event_id 文字列へ戻して渡す。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ShowRecord {
    pub id: String,
    pub event_id: String,
    pub name: String,
    /// YYYY-MM-DD。
    pub date: String,
    pub venue: Option<String>,
    pub venue_city: Option<String>,
    pub start_time: Option<String>,
    pub sort_order: i64,
    pub performer_type: Option<String>,
    pub venue_id: Option<String>,
    pub hall: Option<String>,
    pub stream_platform: Option<String>,
    /// Documents 専用列。Bundle DB では None。
    pub has_streaming: Option<bool>,
    /// Documents 専用列。Bundle DB では None。
    pub has_live_viewing: Option<bool>,
}

/// events 1 行の全域射影 (GRDB `Event` 相当)。イベント詳細と単一取得で使う。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct EventDetailRecord {
    pub id: String,
    pub brand_id: Option<String>,
    pub name: String,
    pub event_type: String,
    pub is_streaming: bool,
    pub is_solo: bool,
    pub kind: String,
    pub ticket_open_date: Option<String>,
    pub ticket_deadline: Option<String>,
    pub ticket_lottery_date: Option<String>,
    pub ticket_url: Option<String>,
    pub joint_brand_ids: Option<String>,
    /// Documents 専用列。Bundle DB では None。
    pub has_streaming: Option<bool>,
    /// Documents 専用列。Bundle DB では None。
    pub has_live_viewing: Option<bool>,
}

/// セトリ 1 行 (iOS `SetlistRow`: setlist_items × songs の射影)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, Hash)]
pub struct SetlistEntryRecord {
    /// setlist_items.id (出演者マップのキー)。
    pub id: String,
    pub position: i64,
    pub section: Option<String>,
    pub notes: Option<String>,
    pub unit_name: Option<String>,
    pub song_id: String,
    pub song_title: String,
    pub apple_music_id: Option<String>,
    pub artwork_url: Option<String>,
    pub preview_url: Option<String>,
    pub song_brand_id: Option<String>,
}

/// セトリ曲の歌唱メンバー 1 行 (iOS `PerformerRow`)。
/// iOS の `id` は idol_id と同値だったので idol_id に一本化してある。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistPerformerRecord {
    pub idol_id: String,
    /// 表示名 = 現任 CV 名 (交代待ちで現任不在ならアイドル名)。
    /// SQL の `COALESCE((SELECT v.name ... valid_to IS NULL ...), i.name)` 相当。
    pub display_name: String,
    pub idol_name: String,
    pub idol_color: Option<String>,
}

/// ピッカー用の公演 1 行 (iOS `ShowWithEventName`)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, Hash)]
pub struct ShowWithEventNameRecord {
    pub id: String,
    pub event_id: String,
    pub name: String,
    pub date: String,
    pub venue: Option<String>,
    pub event_name: String,
}

/// イベント統計 (iOS `EventStats`)。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct EventStatsRecord {
    pub show_count: u32,
    pub total_songs: u32,
    pub unique_songs: u32,
    pub cast_count: u32,
}

/// DAY 別出席表 (iOS `EventAttendance`)。
///
/// brandIdols は id 列で渡し、実体化はプラットフォーム側の idol 取得 API に任せる
/// (Phase 2 の「射影 Record / id 列で渡す」規約)。集合はキー・値とも決定的な順で
/// 並べてあるので、受け側はそのまま Set 化して良い。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct EventAttendanceRecord {
    /// 欠席判定の母集団 (sort_order 順)。
    pub brand_idol_ids: Vec<String>,
    /// 配下公演 (date, sort_order 順)。
    pub shows: Vec<ShowRecord>,
    /// show_id → 出席 idol_id 集合 (sort_order 順)。出席者ゼロの show はキーごと無い
    /// (iOS が SQL 行から辞書を組み立てていた挙動と同じ)。
    pub presence_by_show: HashMap<String, Vec<String>>,
    /// show_id → cast_role='lead' の idol_id 集合。
    pub lead_by_show: HashMap<String, Vec<String>>,
    /// show_id → cast_role='guest' の idol_id 集合。
    pub guest_by_show: HashMap<String, Vec<String>>,
}

/// ライブ円盤 1 行 (iOS `EventRelease`)。
///
/// show_id はスナップショットで解決済みの公演 id。元表の show_id が孤児 (削除済み公演)
/// の行は None に落ちる (ローダの「公演不明扱いで行は残す」契約)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct EventReleaseRecord {
    pub id: String,
    pub event_id: String,
    pub show_id: Option<String>,
    pub product_type: String,
    pub title: String,
    pub catalog_number: Option<String>,
    pub release_date: Option<String>,
    pub jacket_url: Option<String>,
    pub purchase_url: Option<String>,
    pub sort_order: i64,
}

/// 会場マスタ 1 行 (iOS `Venue`)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct VenueRecord {
    pub id: String,
    pub name: String,
    pub name_kana: Option<String>,
    pub prefecture: Option<String>,
    pub city: Option<String>,
    pub aliases: Option<String>,
    pub capacity: Option<i64>,
    pub sort_order: i64,
}

/// 会場の期間つき名称履歴 1 行 (iOS `VenueName`)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct VenueNameRecord {
    pub id: String,
    pub venue_id: String,
    pub name: String,
    pub valid_from: Option<String>,
    pub valid_to: Option<String>,
}

/// 会場のホール 1 行 (iOS `VenueHall`)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct VenueHallRecord {
    pub id: String,
    pub venue_id: String,
    pub name: String,
    pub capacity: Option<i64>,
}

/// 会場マスタ一式 (iOS `VenueDirectory`)。小さい (数百行) ので一括で渡し、
/// 当時名やキャパの解決はプラットフォーム側のメモリ上で行う (N+1 回避も iOS 準拠)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct VenueDirectoryRecord {
    /// sort_order 順 (iOS `Venue.order(sort_order)`)。
    pub venues: Vec<VenueRecord>,
    /// テーブル出現順 (SQL 時代の fetchAll も ORDER BY なし)。
    pub names: Vec<VenueNameRecord>,
    /// テーブル出現順。
    pub halls: Vec<VenueHallRecord>,
}

// =============================================================================
// 共通ヘルパ
// =============================================================================

/// SQLite の `LIKE '%needle%'` 相当: ASCII のみ大文字小文字を無視する部分一致。
/// (song_list_queries と同じ実装。needle 先頭バイトは UTF-8 継続バイトと衝突しないため
/// バイト列照合でも文字境界を跨いだ誤一致は起きない。)
fn like_contains(haystack: &str, needle: &str) -> bool {
    let (h, n) = (haystack.as_bytes(), needle.as_bytes());
    if n.is_empty() {
        return true; // LIKE '%%' は非 NULL の全行に一致
    }
    if n.len() > h.len() {
        return false;
    }
    h.windows(n.len()).any(|w| w.eq_ignore_ascii_case(n))
}

/// `ORDER BY sort_order` (idols) の明示キー。NULL 先頭 (Option の None < Some) +
/// 添字タイブレークで決定的にする。
fn idol_sort_key(snap: &Snapshot, idol: u32) -> (Option<i64>, u32) {
    (snap.idols[idol as usize].sort_order, idol)
}

/// idol 添字集合 → sort_order 順の idol_id 列。SQL が Set で返していた (並び未規定の)
/// 集合を、出席表の表示順 (sort_order) で決定化して渡すための共通処理。
fn idol_set_to_sorted_ids(snap: &Snapshot, set: &HashSet<u32>) -> Vec<String> {
    let mut indexes: Vec<u32> = set.iter().copied().collect();
    indexes.sort_by_key(|&i| idol_sort_key(snap, i));
    indexes.into_iter().map(|i| snap.idols[i as usize].id.clone()).collect()
}

/// `ORDER BY date DESC` (shows) の明示キー。SQL では同日の並びが未規定だったので
/// (sort_order ASC, 添字) で決定化する (ローダの shows_by_venue_id と同じ規約)。
fn show_date_desc_key(snap: &Snapshot, show: u32) -> (Reverse<String>, i64, u32) {
    let s = &snap.shows[show as usize];
    (Reverse(s.date.clone()), s.sort_order, show)
}

fn show_record_at(snap: &Snapshot, show: u32) -> ShowRecord {
    let s = &snap.shows[show as usize];
    ShowRecord {
        id: s.id.clone(),
        event_id: snap.events[s.event as usize].id.clone(),
        name: s.name.clone(),
        date: s.date.clone(),
        venue: s.venue.clone(),
        venue_city: s.venue_city.clone(),
        start_time: s.start_time.clone(),
        sort_order: s.sort_order,
        performer_type: s.performer_type.clone(),
        venue_id: s.venue_id.clone(),
        hall: s.hall.clone(),
        stream_platform: s.stream_platform.clone(),
        has_streaming: s.has_streaming,
        has_live_viewing: s.has_live_viewing,
    }
}

fn show_with_event_name_at(snap: &Snapshot, show: u32) -> ShowWithEventNameRecord {
    let s = &snap.shows[show as usize];
    let e = &snap.events[s.event as usize];
    ShowWithEventNameRecord {
        id: s.id.clone(),
        event_id: e.id.clone(),
        name: s.name.clone(),
        date: s.date.clone(),
        venue: s.venue.clone(),
        event_name: e.name.clone(),
    }
}

// =============================================================================
// 公演 (shows)
// =============================================================================

/// イベント配下の公演一覧 (iOS fetchShows(eventId:) = `.order(date, sort_order)`)。
/// 並びは shows_by_event が前計算済み。未知 event_id は空。
pub fn shows_by_event(snap: &Snapshot, event_id: &str) -> Vec<ShowRecord> {
    let Some(&e) = snap.event_index_by_id.get(event_id) else { return vec![] };
    snap.shows_by_event[e as usize]
        .iter()
        .map(|&s| show_record_at(snap, s))
        .collect()
}

/// 単一公演 (iOS fetchShow(id:))。
pub fn show_record(snap: &Snapshot, id: &str) -> Option<ShowRecord> {
    snap.show_index_by_id.get(id).map(|&s| show_record_at(snap, s))
}

/// 直近公演 = 日付最大 (iOS fetchLatestShow = `ORDER BY date DESC LIMIT 1`)。
/// SQL は同日最大が複数ある場合にどれを返すか未規定 → 前計算済み日付順の末尾
/// (date, sort_order, 添字 が最大の公演) で決定化する。
pub fn latest_show(snap: &Snapshot) -> Option<ShowRecord> {
    snap.shows_in_date_order.last().map(|&s| show_record_at(snap, s))
}

/// 会場での公演一覧 (iOS showsByVenueQuery)。
///
/// `venue` は会場マスタ ID (`venue_...`) が正だが、ID 未付与の過去公演を拾う後方互換で
/// 「venue_id 一致 または 生の venue 文字列一致」の OR (iOS 側コメントの経緯そのまま)。
/// `ORDER BY date DESC`。同日は (sort_order, 添字) で決定化。
pub fn shows_at_venue(snap: &Snapshot, venue: &str) -> Vec<ShowRecord> {
    let mut indexes: Vec<u32> = Vec::new();
    if let Some(list) = snap.shows_by_venue_id.get(venue) {
        indexes.extend_from_slice(list);
    }
    if let Some(list) = snap.shows_by_venue_label.get(venue) {
        indexes.extend_from_slice(list);
    }
    // venue_id と venue が同じ値の公演は OR の両側にヒットする (SQL では 1 行) → 重複排除。
    indexes.sort_by_key(|&s| show_date_desc_key(snap, s));
    indexes.dedup();
    indexes.into_iter().map(|s| show_record_at(snap, s)).collect()
}

/// 指定日の公演一覧 (iOS showsByDateQuery = `WHERE date = ? ORDER BY sort_order`)。
/// 前計算済みの (date, sort_order, 添字) 順列を二分探索して該当区間をそのまま流す。
pub fn shows_on_date(snap: &Snapshot, date: &str) -> Vec<ShowRecord> {
    let order = &snap.shows_in_date_order;
    let lower = order.partition_point(|&s| snap.shows[s as usize].date.as_str() < date);
    let upper = order.partition_point(|&s| snap.shows[s as usize].date.as_str() <= date);
    order[lower..upper].iter().map(|&s| show_record_at(snap, s)).collect()
}

/// (date DESC, sort_order, 添字) の全公演順列。all/search の共通土台。
fn shows_newest_first(snap: &Snapshot) -> Vec<u32> {
    let mut indexes: Vec<u32> = (0..snap.shows.len() as u32).collect();
    indexes.sort_by_key(|&s| show_date_desc_key(snap, s));
    indexes
}

/// ピッカー初期表示の公演一覧 (iOS fetchAllShows = events JOIN で新しい順 LIMIT ?)。
/// JOIN はスナップショットでは常に成立する (FK 孤児 show はロード時に除外済み)。
pub fn all_shows_with_event_name(snap: &Snapshot, limit: u32) -> Vec<ShowWithEventNameRecord> {
    shows_newest_first(snap)
        .into_iter()
        .take(limit as usize)
        .map(|s| show_with_event_name_at(snap, s))
        .collect()
}

/// ピッカー用の公演検索 (iOS searchShows = 公演名 or イベント名の LIKE 部分一致、新しい順)。
pub fn search_shows_with_event_name(
    snap: &Snapshot,
    query: &str,
    limit: u32,
) -> Vec<ShowWithEventNameRecord> {
    shows_newest_first(snap)
        .into_iter()
        .filter(|&s| {
            let show = &snap.shows[s as usize];
            like_contains(&show.name, query)
                || like_contains(&snap.events[show.event as usize].name, query)
        })
        .take(limit as usize)
        .map(|s| show_with_event_name_at(snap, s))
        .collect()
}

// =============================================================================
// セトリ・出演者
// =============================================================================

/// 公演のセットリスト (iOS fetchSetlist = setlist_items JOIN songs、position 順)。
/// 並びは setlist_items_by_show が前計算済み (同 position は添字で決定化)。
pub fn setlist(snap: &Snapshot, show_id: &str) -> Vec<SetlistEntryRecord> {
    let Some(&s) = snap.show_index_by_id.get(show_id) else { return vec![] };
    snap.setlist_items_by_show[s as usize]
        .iter()
        .map(|&i| {
            let item = &snap.setlist_items[i as usize];
            let song = &snap.songs[item.song as usize];
            SetlistEntryRecord {
                id: item.id.clone(),
                position: item.position,
                section: item.section.clone(),
                notes: item.notes.clone(),
                unit_name: item.unit_name.clone(),
                song_id: song.id.clone(),
                song_title: song.title.clone(),
                apple_music_id: song.apple_music_id.clone(),
                artwork_url: song.artwork_url.clone(),
                preview_url: song.preview_url.clone(),
                song_brand_id: song.brand_id.clone(),
            }
        })
        .collect()
}

/// セトリ全曲の歌唱メンバー一括取得 (iOS fetchAllPerformers。N+1 防止)。
///
/// キーは setlist_items.id。SQL は行順未規定のまま辞書に詰めていた → 各曲内は
/// idol の sort_order 順 (performers_by_item の前計算) で決定化。歌唱メンバーの居ない
/// 曲はキーごと載らない (iOS が SQL 行から組み立てていた挙動と同じ)。
pub fn setlist_performers_by_item(
    snap: &Snapshot,
    show_id: &str,
) -> HashMap<String, Vec<SetlistPerformerRecord>> {
    let Some(&s) = snap.show_index_by_id.get(show_id) else { return HashMap::new() };
    let mut result: HashMap<String, Vec<SetlistPerformerRecord>> = HashMap::new();
    for &i in &snap.setlist_items_by_show[s as usize] {
        let performers = &snap.performers_by_item[i as usize];
        if performers.is_empty() {
            continue;
        }
        let rows = performers
            .iter()
            .map(|&idol| {
                let record = &snap.idols[idol as usize];
                // 表示名は現任 CV (valid_to IS NULL の最新 valid_from)。不在ならアイドル名。
                let display_name = snap
                    .current_voice_actor(idol)
                    .map_or_else(|| record.name.clone(), |va| va.name.clone());
                SetlistPerformerRecord {
                    idol_id: record.id.clone(),
                    display_name,
                    idol_name: record.name.clone(),
                    idol_color: record.color.clone(),
                }
            })
            .collect();
        result.insert(snap.setlist_items[i as usize].id.clone(), rows);
    }
    result
}

/// 公演の出演キャスト idol_id 列 (show_cast、sort_order 順)。
///
/// iOS の fetchShowIdolIds (Set) と fetchShowCastIdols ([Idol] sort_order 順) は
/// 同じ show_cast の 2 表現なので 1 本に集約した。Set が欲しい側は受けてから集合化する。
pub fn show_cast_idol_ids(snap: &Snapshot, show_id: &str) -> Vec<String> {
    let Some(&s) = snap.show_index_by_id.get(show_id) else { return vec![] };
    snap.cast_by_show[s as usize]
        .iter()
        .map(|link| snap.idols[link.idol as usize].id.clone())
        .collect()
}

/// song_id → 原曲アーティスト (role='original') の idol_id 集合 (iOS fetchOriginalArtistIds)。
/// SQL の行有無と同じく、original を 1 人も持たない曲・未知 id はキーごと載らない。
/// 値の並びは idol の sort_order 順 (artists_by_song の前計算) で決定化。
pub fn original_artist_ids_map(
    snap: &Snapshot,
    song_ids: &[String],
) -> HashMap<String, Vec<String>> {
    let mut result = HashMap::new();
    for song_id in song_ids {
        let Some(&s) = snap.song_index_by_id.get(song_id) else { continue };
        let ids: Vec<String> = snap.artists_by_song[s as usize]
            .iter()
            .filter(|link| link.role == "original")
            .map(|link| snap.idols[link.idol as usize].id.clone())
            .collect();
        if !ids.is_empty() {
            result.insert(song_id.clone(), ids);
        }
    }
    result
}

/// 指定公演の出演キャストがオリメンの曲 song_id 集合 (iOS fetchOriginalSongIds)。
/// 「この公演の出演者が歌う曲」で予想ピッカーを絞るのに使う。
/// SQL は `SELECT DISTINCT` で並び未規定 → 曲の添字昇順 (= rowid 順) で決定化。
pub fn original_song_ids_for_show_cast(snap: &Snapshot, show_id: &str) -> Vec<String> {
    let Some(&s) = snap.show_index_by_id.get(show_id) else { return vec![] };
    let mut songs: HashSet<u32> = HashSet::new();
    for link in &snap.cast_by_show[s as usize] {
        for song_link in &snap.songs_by_idol[link.idol as usize] {
            if song_link.role == "original" {
                songs.insert(song_link.song);
            }
        }
    }
    let mut indexes: Vec<u32> = songs.into_iter().collect();
    indexes.sort_unstable();
    indexes.into_iter().map(|i| snap.songs[i as usize].id.clone()).collect()
}

// =============================================================================
// 会場 (venues)
// =============================================================================

/// 会場マスタ一式 (iOS fetchVenueDirectory)。
pub fn venue_directory(snap: &Snapshot) -> VenueDirectoryRecord {
    let venues = snap
        .venue_order
        .iter()
        .map(|&v| {
            let venue = &snap.venues[v as usize];
            VenueRecord {
                id: venue.id.clone(),
                name: venue.name.clone(),
                name_kana: venue.name_kana.clone(),
                prefecture: venue.prefecture.clone(),
                city: venue.city.clone(),
                aliases: venue.aliases.clone(),
                capacity: venue.capacity,
                sort_order: venue.sort_order,
            }
        })
        .collect();
    let names = snap
        .venue_names
        .iter()
        .map(|n| VenueNameRecord {
            id: n.id.clone(),
            venue_id: snap.venues[n.venue as usize].id.clone(),
            name: n.name.clone(),
            valid_from: n.valid_from.clone(),
            valid_to: n.valid_to.clone(),
        })
        .collect();
    let halls = snap
        .venue_halls
        .iter()
        .map(|h| VenueHallRecord {
            id: h.id.clone(),
            venue_id: snap.venues[h.venue as usize].id.clone(),
            name: h.name.clone(),
            capacity: h.capacity,
        })
        .collect();
    VenueDirectoryRecord { venues, names, halls }
}

/// 指定会場 (venue_id) で公演があったイベントの id 集合 (iOS fetchEventIdsAtVenue)。
/// SQL の `SELECT DISTINCT` は並び未規定 → 会場の公演リスト (date DESC) の初出順で決定化。
/// 受け側は Set として扱う。
pub fn event_ids_at_venue(snap: &Snapshot, venue_id: &str) -> Vec<String> {
    let Some(list) = snap.shows_by_venue_id.get(venue_id) else { return vec![] };
    let mut seen: HashSet<u32> = HashSet::new();
    let mut result = Vec::new();
    for &s in list {
        let e = snap.shows[s as usize].event;
        if seen.insert(e) {
            result.push(snap.events[e as usize].id.clone());
        }
    }
    result
}

/// 検索語に一致した会場を event_id ごとに 1 件 (= MIN(venue)) 返す (iOS fetchVenuesMatching)。
/// 「武道館」で検索したときに、なぜヒットしたか行に会場名で見せるための逆引き。
///
/// iOS は `LOWER(venue) LIKE '%query.lowercased()%'` — LIKE 自体が ASCII 大小無視なので、
/// 意味を持つのは Swift の Unicode 小文字化だけ。Rust の `to_lowercase` で同じに揃える。
pub fn venues_matching(
    snap: &Snapshot,
    query: &str,
    event_ids: &[String],
) -> HashMap<String, String> {
    if query.is_empty() || event_ids.is_empty() {
        return HashMap::new();
    }
    let needle = query.to_lowercase();
    let mut result: HashMap<String, String> = HashMap::new();
    for event_id in event_ids {
        let Some(&e) = snap.event_index_by_id.get(event_id) else { continue };
        // MIN(venue): 一致した venue 文字列のバイト列最小 (NULL は WHERE で除外済み)。
        let min_venue = snap.shows_by_event[e as usize]
            .iter()
            .filter_map(|&s| snap.shows[s as usize].venue.as_deref())
            .filter(|v| like_contains(v, &needle))
            .min();
        if let Some(v) = min_venue {
            // 同一 event_id が入力に重複していても結果は 1 件 (SQL の GROUP BY と同じ)。
            result.insert(event_id.clone(), v.to_string());
        }
    }
    result
}

// =============================================================================
// イベント詳細
// =============================================================================

/// 単一イベント (iOS fetchEvent(id:))。
pub fn event_record(snap: &Snapshot, id: &str) -> Option<EventDetailRecord> {
    snap.event_index_by_id.get(id).map(|&e| {
        let event = &snap.events[e as usize];
        EventDetailRecord {
            id: event.id.clone(),
            brand_id: event.brand_id.clone(),
            name: event.name.clone(),
            event_type: event.event_type.clone(),
            is_streaming: event.is_streaming,
            is_solo: event.is_solo,
            kind: event.kind.clone(),
            ticket_open_date: event.ticket_open_date.clone(),
            ticket_deadline: event.ticket_deadline.clone(),
            ticket_lottery_date: event.ticket_lottery_date.clone(),
            ticket_url: event.ticket_url.clone(),
            joint_brand_ids: event.joint_brand_ids.clone(),
            has_streaming: event.has_streaming,
            has_live_viewing: event.has_live_viewing,
        }
    })
}

/// イベント統計 (iOS fetchEventStats: 公演数・のべ曲数・ユニーク曲数・キャスト数)。
/// 未知 event_id は全ゼロ (SQL の CTE が空になるのと同じ)。
pub fn event_stats(snap: &Snapshot, event_id: &str) -> EventStatsRecord {
    let Some(&e) = snap.event_index_by_id.get(event_id) else {
        return EventStatsRecord::default();
    };
    let shows = &snap.shows_by_event[e as usize];
    let mut total_songs = 0u32;
    let mut unique_songs: HashSet<u32> = HashSet::new();
    let mut cast: HashSet<u32> = HashSet::new();
    for &s in shows {
        let items = &snap.setlist_items_by_show[s as usize];
        total_songs += items.len() as u32;
        for &i in items {
            // COUNT(DISTINCT song_id)
            unique_songs.insert(snap.setlist_items[i as usize].song);
        }
        for link in &snap.cast_by_show[s as usize] {
            // COUNT(DISTINCT idol_id)
            cast.insert(link.idol);
        }
    }
    EventStatsRecord {
        show_count: shows.len() as u32,
        total_songs,
        unique_songs: unique_songs.len() as u32,
        cast_count: cast.len() as u32,
    }
}

/// DAY 別出席表 (iOS fetchEventAttendance)。ロジックは iOS の忠実な移植:
///
/// - 母集団 (brandIdols) は idols.brand_id 直参照 (idol_brands ではない。多重所属の
///   ゲストを欠席候補に出さないため — AS が ML 13th で「欠席」誤表示される事故の対策)。
/// - primary + joint_brand_ids の 3 ブランド以上 (MOIW 等の越境フェス) は選抜出演なので
///   母集団を「実出演者 (show_cast ∪ 歌唱)」に切り替える。
/// - ライブ初日より後に実装されたアイドル (debut_date) は未実装期として母集団から除外。
///   debut_date NULL は安全側で含める。
/// - 出席判定は setlist_performers (歌唱) ∪ show_cast。過去公演の show_cast 欠損と
///   未来公演のセトリ未入力を互いに補う。
/// - event が無い / brand_id NULL / 母集団ゼロは None (iOS の guard と同じ)。
pub fn event_attendance(snap: &Snapshot, event_id: &str) -> Option<EventAttendanceRecord> {
    let &e = snap.event_index_by_id.get(event_id)?;
    let event = &snap.events[e as usize];
    let brand_id = event.brand_id.as_deref()?;

    let joint: Vec<&str> = event
        .joint_brand_ids
        .as_deref()
        .map(|s| s.split(',').map(str::trim).filter(|p| !p.is_empty()).collect())
        .unwrap_or_default();
    // 件数判定 (>= 3) は iOS 同様に重複を数える。照合は Set で行う。
    let candidate_count = 1 + joint.len();
    let candidate_set: HashSet<&str> = std::iter::once(brand_id).chain(joint).collect();

    let shows = &snap.shows_by_event[e as usize];
    let event_start_date = shows.first().map(|&s| snap.shows[s as usize].date.as_str());

    // 出演実績 (show_cast ∪ 歌唱) の idol 集合。>= 3 ブランドの母集団に使う。
    let mut performed: HashSet<u32> = HashSet::new();
    if candidate_count >= 3 {
        for &s in shows {
            for link in &snap.cast_by_show[s as usize] {
                performed.insert(link.idol);
            }
            for &i in &snap.setlist_items_by_show[s as usize] {
                performed.extend(snap.performers_by_item[i as usize].iter().copied());
            }
        }
    }

    // 母集団。idol_order (sort_order 順の前計算) を条件で絞る = `ORDER BY sort_order`。
    let brand_idol_ids: Vec<String> = snap
        .idol_order
        .iter()
        .filter(|&&i| {
            let idol = &snap.idols[i as usize];
            if idol.is_external {
                return false;
            }
            if candidate_count >= 3 {
                return performed.contains(&i);
            }
            if !idol.brand_id.as_deref().is_some_and(|b| candidate_set.contains(b)) {
                return false;
            }
            match (event_start_date, idol.debut_date.as_deref()) {
                // debut_date <= ライブ初日 (文字列比較 = 日付比較)。NULL は含める。
                (Some(start), Some(debut)) => debut <= start,
                _ => true,
            }
        })
        .map(|&i| snap.idols[i as usize].id.clone())
        .collect();
    if brand_idol_ids.is_empty() {
        return None;
    }

    // 出席判定 (brand 絞りあり) と役割 (lead/guest。brand 絞りなし — iOS の SQL と同じ)。
    let mut presence_by_show = HashMap::new();
    let mut lead_by_show = HashMap::new();
    let mut guest_by_show = HashMap::new();
    for &s in shows {
        let show_id = &snap.shows[s as usize].id;
        let in_candidate_brand = |idol: u32| {
            snap.idols[idol as usize]
                .brand_id
                .as_deref()
                .is_some_and(|b| candidate_set.contains(b))
        };

        let mut present: HashSet<u32> = HashSet::new();
        for &i in &snap.setlist_items_by_show[s as usize] {
            present.extend(
                snap.performers_by_item[i as usize]
                    .iter()
                    .copied()
                    .filter(|&idol| in_candidate_brand(idol)),
            );
        }
        let mut lead: Vec<String> = Vec::new();
        let mut guest: Vec<String> = Vec::new();
        for link in &snap.cast_by_show[s as usize] {
            if in_candidate_brand(link.idol) {
                present.insert(link.idol);
            }
            // cast_by_show は sort_order 順に前計算済みなのでそのまま決定的な並びになる。
            match link.cast_role.as_str() {
                "lead" => lead.push(snap.idols[link.idol as usize].id.clone()),
                "guest" => guest.push(snap.idols[link.idol as usize].id.clone()),
                _ => {}
            }
        }
        if !present.is_empty() {
            presence_by_show.insert(show_id.clone(), idol_set_to_sorted_ids(snap, &present));
        }
        if !lead.is_empty() {
            lead_by_show.insert(show_id.clone(), lead);
        }
        if !guest.is_empty() {
            guest_by_show.insert(show_id.clone(), guest);
        }
    }

    Some(EventAttendanceRecord {
        brand_idol_ids,
        shows: shows.iter().map(|&s| show_record_at(snap, s)).collect(),
        presence_by_show,
        lead_by_show,
        guest_by_show,
    })
}

/// イベントの映像円盤一覧 (iOS fetchEventReleases = `ORDER BY release_date ASC, sort_order ASC`)。
/// 並びは releases_by_event が前計算済み (NULL release_date は ASC の先頭)。
/// event_releases 表の無い DB (Bundle) では常に空。
pub fn event_releases(snap: &Snapshot, event_id: &str) -> Vec<EventReleaseRecord> {
    let Some(&e) = snap.event_index_by_id.get(event_id) else { return vec![] };
    snap.releases_by_event[e as usize]
        .iter()
        .map(|&r| {
            let release = &snap.event_releases[r as usize];
            EventReleaseRecord {
                id: release.id.clone(),
                event_id: snap.events[release.event as usize].id.clone(),
                show_id: release.show.map(|s| snap.shows[s as usize].id.clone()),
                product_type: release.product_type.clone(),
                title: release.title.clone(),
                catalog_number: release.catalog_number.clone(),
                release_date: release.release_date.clone(),
                jacket_url: release.jacket_url.clone(),
                purchase_url: release.purchase_url.clone(),
                sort_order: release.sort_order,
            }
        })
        .collect()
}

// =============================================================================
// テスト: 元 SQL を rusqlite で直接実行した結果との照合 (等価性の保証)
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::outbound::sqlite_loader::load_snapshot;
    use rusqlite::{Connection, OpenFlags};
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

    /// Swift `String.likeEscaped` の写経 (テスト側で元 SQL を組むのに使う)。
    fn like_escaped(s: &str) -> String {
        s.replace('\\', "\\\\").replace('%', "\\%").replace('_', "\\_")
    }

    fn all_event_ids(db: &Connection) -> Vec<String> {
        let mut stmt = db.prepare("SELECT id FROM events").unwrap();
        stmt.query_map([], |r| r.get(0)).unwrap().collect::<Result<_, _>>().unwrap()
    }

    fn string_column(db: &Connection, sql: &str, params: &[&dyn rusqlite::ToSql]) -> Vec<String> {
        let mut stmt = db.prepare(sql).unwrap();
        stmt.query_map(params, |r| r.get::<_, String>(0))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap()
    }

    /// ORDER BY キーが同値の区間を集合として比較する等価判定 (song_list_queries と同じ)。
    /// SQLite のソータは同値キーの並びが未規定なので、キー列一致 + 同値区間のメンバー
    /// 一致を等価とみなす。
    fn assert_matches_up_to_ties<T, K>(label: &str, actual: &[T], expected: &[T], key: impl Fn(&T) -> K)
    where
        T: std::hash::Hash + Eq + std::fmt::Debug,
        K: PartialEq + std::fmt::Debug,
    {
        assert_eq!(actual.len(), expected.len(), "{label}: 件数");
        let mut start = 0;
        while start < expected.len() {
            let k = key(&expected[start]);
            let mut end = start;
            while end < expected.len() && key(&expected[end]) == k {
                end += 1;
            }
            let expected_group: HashSet<&T> = expected[start..end].iter().collect();
            let actual_group: HashSet<&T> = actual[start..end].iter().collect();
            assert_eq!(actual_group, expected_group, "{label}: キー {k:?} の同順位グループ");
            start = end;
        }
    }

    /// show id → (date, sort_order)。shows 系クエリの ORDER BY キー。
    fn show_key(id: &String) -> (String, i64) {
        let s = &snap().shows[snap().show_index_by_id[id] as usize];
        (s.date.clone(), s.sort_order)
    }

    // ---- 公演 (shows) ----

    #[test]
    fn shows_by_event_matches_sql_for_all_events() {
        let db = conn();
        let mut checked_multi = 0;
        for event_id in all_event_ids(&db) {
            let expected = string_column(
                &db,
                "SELECT id FROM shows WHERE event_id = ? ORDER BY date, sort_order",
                &[&event_id],
            );
            let actual: Vec<String> =
                shows_by_event(snap(), &event_id).into_iter().map(|s| s.id).collect();
            assert_matches_up_to_ties(&format!("event {event_id}"), &actual, &expected, show_key);
            if expected.len() >= 2 {
                checked_multi += 1;
            }
        }
        assert!(checked_multi > 50, "複数公演イベントが十分ある前提 ({checked_multi})");
        assert!(shows_by_event(snap(), "存在しないイベント").is_empty());
    }

    #[test]
    fn show_record_fields_match_sql() {
        let db = conn();
        let mut stmt = db
            .prepare(
                "SELECT id, event_id, name, date, venue, venue_city, start_time, sort_order,
                        performer_type, venue_id, hall, stream_platform
                 FROM shows WHERE id = ?",
            )
            .unwrap();
        let mut checked = 0;
        for s in snap().shows.iter().step_by(17) {
            let expected = stmt
                .query_row([&s.id], |r| {
                    Ok(ShowRecord {
                        id: r.get(0)?,
                        event_id: r.get(1)?,
                        name: r.get(2)?,
                        date: r.get(3)?,
                        venue: r.get(4)?,
                        venue_city: r.get(5)?,
                        start_time: r.get(6)?,
                        // NULL 既定 0 はローダの規約 (Show.sort_order は非 Optional)。
                        sort_order: r.get::<_, Option<i64>>(7)?.unwrap_or(0),
                        performer_type: r.get(8)?,
                        venue_id: r.get(9)?,
                        hall: r.get(10)?,
                        stream_platform: r.get(11)?,
                        has_streaming: None,
                        has_live_viewing: None,
                    })
                })
                .unwrap();
            let actual = show_record(snap(), &s.id).expect("スナップショットに居る show");
            assert_eq!(actual, expected, "show {}", s.id);
            checked += 1;
        }
        assert!(checked > 50, "サンプル数 ({checked})");
        assert!(show_record(snap(), "存在しない公演").is_none());
    }

    #[test]
    fn latest_show_matches_sql() {
        let db = conn();
        let max_date: String =
            db.query_row("SELECT MAX(date) FROM shows", [], |r| r.get(0)).unwrap();
        let candidates = string_column(&db, "SELECT id FROM shows WHERE date = ?", &[&max_date]);
        let actual = latest_show(snap()).expect("公演は 1 件以上ある");
        assert_eq!(actual.date, max_date);
        // ORDER BY date DESC LIMIT 1 の同日タイは SQL 未規定 → 最大日の中の 1 件であること。
        assert!(candidates.contains(&actual.id), "{} は {max_date} の公演", actual.id);
    }

    #[test]
    fn shows_at_venue_matches_sql() {
        let db = conn();
        // 公演数の多い venue_id 3 件 + 生ラベルのみ (venue_id 未付与) の会場 + 未知値。
        let mut targets = string_column(
            &db,
            "SELECT venue_id FROM shows WHERE venue_id IS NOT NULL
             GROUP BY venue_id ORDER BY COUNT(*) DESC, venue_id LIMIT 3",
            &[],
        );
        targets.extend(string_column(
            &db,
            "SELECT venue FROM shows WHERE venue IS NOT NULL AND venue_id IS NULL
             GROUP BY venue ORDER BY COUNT(*) DESC, venue LIMIT 2",
            &[],
        ));
        assert!(targets.len() >= 4, "対象会場が取れる前提 ({targets:?})");
        for venue in &targets {
            let expected = string_column(
                &db,
                "SELECT id FROM shows WHERE venue_id = ?1 OR venue = ?1 ORDER BY date DESC",
                &[venue],
            );
            let actual: Vec<String> =
                shows_at_venue(snap(), venue).into_iter().map(|s| s.id).collect();
            assert!(!expected.is_empty(), "{venue} は公演を持つ前提");
            // SQL の ORDER BY は date のみ → 同日の並びは date キーで区間比較。
            assert_matches_up_to_ties(&format!("venue {venue}"), &actual, &expected, |id| {
                show_key(id).0
            });
        }
        assert!(shows_at_venue(snap(), "存在しない会場xyz").is_empty());
    }

    #[test]
    fn shows_on_date_matches_sql() {
        let db = conn();
        // 同日複数公演の日 3 件 (sort_order の並びが効くケース) + 未知日。
        let dates = string_column(
            &db,
            "SELECT date FROM shows GROUP BY date HAVING COUNT(*) >= 2
             ORDER BY COUNT(*) DESC, date LIMIT 3",
            &[],
        );
        assert_eq!(dates.len(), 3, "同日複数公演の日がある前提");
        for date in &dates {
            let expected = string_column(
                &db,
                "SELECT id FROM shows WHERE date = ? ORDER BY sort_order",
                &[date],
            );
            let actual: Vec<String> =
                shows_on_date(snap(), date).into_iter().map(|s| s.id).collect();
            assert!(expected.len() >= 2);
            assert_matches_up_to_ties(&format!("date {date}"), &actual, &expected, |id| {
                show_key(id).1
            });
        }
        assert!(shows_on_date(snap(), "1900-01-01").is_empty());
    }

    #[test]
    fn all_shows_with_event_name_matches_sql() {
        let db = conn();
        let mut stmt = db
            .prepare(
                "SELECT s.id, s.event_id, s.name, s.date, s.venue, e.name AS event_name
                 FROM shows s JOIN events e ON s.event_id = e.id
                 ORDER BY s.date DESC LIMIT ?",
            )
            .unwrap();
        let mut fetch = |limit: i64| -> Vec<ShowWithEventNameRecord> {
            stmt.query_map([limit], |r| {
                Ok(ShowWithEventNameRecord {
                    id: r.get(0)?,
                    event_id: r.get(1)?,
                    name: r.get(2)?,
                    date: r.get(3)?,
                    venue: r.get(4)?,
                    event_name: r.get(5)?,
                })
            })
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap()
        };
        // 全件 (LIMIT が届かない大きさ) はレコード内容ごと区間照合。
        let expected = fetch(1_000_000);
        let actual = all_shows_with_event_name(snap(), 1_000_000);
        assert!(expected.len() > 100);
        assert_matches_up_to_ties("all_shows 全件", &actual, &expected, |r| r.date.clone());
        // 小さい LIMIT は同日途中で切れても日付列は必ず一致する。
        let expected_dates: Vec<String> = fetch(50).into_iter().map(|r| r.date).collect();
        let actual_dates: Vec<String> =
            all_shows_with_event_name(snap(), 50).into_iter().map(|r| r.date).collect();
        assert_eq!(actual_dates, expected_dates);
    }

    #[test]
    fn search_shows_with_event_name_matches_sql() {
        let db = conn();
        // 大小混在 (LIKE の ASCII 大小無視)・日本語・likeEscaped が効く '%' 入り・ゼロ件。
        let queries = ["DAY", "day", "ミリオン", "10th", "100%", "存在しないクエリzz"];
        for query in queries {
            let pattern = format!("%{}%", like_escaped(query));
            let expected = string_column(
                &db,
                "SELECT s.id FROM shows s JOIN events e ON s.event_id = e.id
                 WHERE s.name LIKE ?1 ESCAPE '\\' OR e.name LIKE ?1 ESCAPE '\\'
                 ORDER BY s.date DESC LIMIT 1000000",
                &[&pattern],
            );
            let actual: Vec<String> = search_shows_with_event_name(snap(), query, 1_000_000)
                .into_iter()
                .map(|r| r.id)
                .collect();
            assert_matches_up_to_ties(&format!("query {query}"), &actual, &expected, |id| {
                show_key(id).0
            });
        }
        // 大小無視が実データで退化していないこと (DAY と day は同一ヒット)。
        let upper = search_shows_with_event_name(snap(), "DAY", 1_000_000);
        let lower = search_shows_with_event_name(snap(), "day", 1_000_000);
        assert!(!upper.is_empty());
        assert_eq!(upper, lower);
    }

    // ---- セトリ・出演者 ----

    #[test]
    fn setlist_matches_sql() {
        let db = conn();
        let mut stmt = db
            .prepare(
                "SELECT si.id, si.position, si.section, si.notes, si.unit_name,
                        s.id, s.title, s.apple_music_id, s.artwork_url, s.preview_url, s.brand_id
                 FROM setlist_items si JOIN songs s ON si.song_id = s.id
                 WHERE si.show_id = ? ORDER BY si.position",
            )
            .unwrap();
        let mut checked = 0;
        for show in snap().shows.iter().step_by(11) {
            let expected: Vec<SetlistEntryRecord> = stmt
                .query_map([&show.id], |r| {
                    Ok(SetlistEntryRecord {
                        id: r.get(0)?,
                        position: r.get(1)?,
                        section: r.get(2)?,
                        notes: r.get(3)?,
                        unit_name: r.get(4)?,
                        song_id: r.get(5)?,
                        song_title: r.get(6)?,
                        apple_music_id: r.get(7)?,
                        artwork_url: r.get(8)?,
                        preview_url: r.get(9)?,
                        song_brand_id: r.get(10)?,
                    })
                })
                .unwrap()
                .collect::<Result<_, _>>()
                .unwrap();
            let actual = setlist(snap(), &show.id);
            assert_matches_up_to_ties(&format!("setlist {}", show.id), &actual, &expected, |r| {
                r.position
            });
            if !expected.is_empty() {
                checked += 1;
            }
        }
        assert!(checked > 30, "セトリつき公演のサンプル数 ({checked})");
        assert!(setlist(snap(), "存在しない公演").is_empty());
    }

    #[test]
    fn setlist_performers_match_sql() {
        let db = conn();
        // 行の並びは SQL 未規定なので item ごとの集合で照合する。
        type PerformerSet = HashSet<(String, String, Option<String>, String)>;
        let mut stmt = db
            .prepare(
                "SELECT sp.setlist_item_id,
                        i.id AS performer_id,
                        COALESCE((SELECT v.name FROM idol_voice_actors v
                                  WHERE v.idol_id = i.id AND v.valid_to IS NULL
                                  ORDER BY IFNULL(v.valid_from,'') DESC LIMIT 1), i.name) AS cast_name,
                        i.color AS idol_color, i.name AS idol_name
                 FROM setlist_items si
                 JOIN setlist_performers sp ON si.id = sp.setlist_item_id
                 JOIN idols i ON i.id = sp.idol_id
                 WHERE si.show_id = ?",
            )
            .unwrap();
        let mut checked = 0;
        for show in snap().shows.iter().step_by(13) {
            let mut expected: HashMap<String, PerformerSet> = HashMap::new();
            let rows = stmt
                .query_map([&show.id], |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, String>(1)?,
                        r.get::<_, String>(2)?,
                        r.get::<_, Option<String>>(3)?,
                        r.get::<_, String>(4)?,
                    ))
                })
                .unwrap();
            for row in rows {
                let (item_id, idol_id, cast_name, color, idol_name) = row.unwrap();
                expected.entry(item_id).or_default().insert((idol_id, cast_name, color, idol_name));
            }
            let actual: HashMap<String, PerformerSet> =
                setlist_performers_by_item(snap(), &show.id)
                    .into_iter()
                    .map(|(item_id, rows)| {
                        let set = rows
                            .into_iter()
                            .map(|p| (p.idol_id, p.display_name, p.idol_color, p.idol_name))
                            .collect();
                        (item_id, set)
                    })
                    .collect();
            assert_eq!(actual, expected, "performers {}", show.id);
            if !expected.is_empty() {
                checked += 1;
            }
        }
        assert!(checked > 30, "歌唱メンバーつき公演のサンプル数 ({checked})");
    }

    #[test]
    fn show_cast_and_original_songs_match_sql() {
        let db = conn();
        let mut checked_cast = 0;
        let mut checked_songs = 0;
        for show in snap().shows.iter().step_by(19) {
            // fetchShowIdolIds: Set 照合 (SQL は並び未規定)。
            let expected: HashSet<String> = string_column(
                &db,
                "SELECT idol_id FROM show_cast WHERE show_id = ?",
                &[&show.id],
            )
            .into_iter()
            .collect();
            let actual_ordered = show_cast_idol_ids(snap(), &show.id);
            let actual: HashSet<String> = actual_ordered.iter().cloned().collect();
            assert_eq!(actual.len(), actual_ordered.len(), "cast は重複しない ({})", show.id);
            assert_eq!(actual, expected, "cast {}", show.id);
            if !expected.is_empty() {
                checked_cast += 1;
            }

            // fetchOriginalSongIds: DISTINCT の Set 照合。
            let expected_songs: HashSet<String> = string_column(
                &db,
                "SELECT DISTINCT sa.song_id FROM song_artists sa
                 JOIN show_cast sc ON sc.idol_id = sa.idol_id
                 WHERE sa.role = 'original' AND sc.show_id = ?",
                &[&show.id],
            )
            .into_iter()
            .collect();
            let actual_songs: HashSet<String> =
                original_song_ids_for_show_cast(snap(), &show.id).into_iter().collect();
            assert_eq!(actual_songs, expected_songs, "original songs {}", show.id);
            if !expected_songs.is_empty() {
                checked_songs += 1;
            }
        }
        assert!(checked_cast > 20, "キャストつき公演のサンプル数 ({checked_cast})");
        assert!(checked_songs > 20, "オリメン曲ありのサンプル数 ({checked_songs})");
        assert!(show_cast_idol_ids(snap(), "存在しない公演").is_empty());
    }

    #[test]
    fn original_artist_ids_map_matches_sql() {
        let db = conn();
        // original あり/なし混在の実在曲 + 未知 id。
        let mut song_ids: Vec<String> =
            snap().songs.iter().step_by(7).map(|s| s.id.clone()).collect();
        song_ids.push("存在しない曲".to_string());
        let placeholders = vec!["?"; song_ids.len()].join(",");
        let sql = format!(
            "SELECT song_id, idol_id FROM song_artists
             WHERE song_id IN ({placeholders}) AND role = 'original'"
        );
        let mut stmt = db.prepare(&sql).unwrap();
        let mut expected: HashMap<String, HashSet<String>> = HashMap::new();
        let rows = stmt
            .query_map(rusqlite::params_from_iter(song_ids.iter()), |r| {
                Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
            })
            .unwrap();
        for row in rows {
            let (song_id, idol_id) = row.unwrap();
            expected.entry(song_id).or_default().insert(idol_id);
        }
        assert!(expected.len() > 100, "original つき曲が十分ある前提");
        let actual: HashMap<String, HashSet<String>> =
            original_artist_ids_map(snap(), &song_ids)
                .into_iter()
                .map(|(song_id, ids)| (song_id, ids.into_iter().collect()))
                .collect();
        assert_eq!(actual, expected);
    }

    // ---- 会場 ----

    #[test]
    fn venue_directory_matches_sql() {
        let db = conn();
        let directory = venue_directory(snap());

        let expected_venues = string_column(&db, "SELECT id FROM venues ORDER BY sort_order", &[]);
        let actual_venues: Vec<String> = directory.venues.iter().map(|v| v.id.clone()).collect();
        assert!(!expected_venues.is_empty());
        // bundle の venues.sort_order はユニーク (引き継ぎメモ) → 逐語一致する。
        assert_eq!(actual_venues, expected_venues);

        // names / halls は ORDER BY なしの fetchAll → id で引き当てて全フィールド照合。
        let mut stmt = db
            .prepare("SELECT venue_id, name, valid_from, valid_to FROM venue_names WHERE id = ?")
            .unwrap();
        for name in &directory.names {
            let expected = stmt
                .query_row([&name.id], |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, String>(1)?,
                        r.get::<_, Option<String>>(2)?,
                        r.get::<_, Option<String>>(3)?,
                    ))
                })
                .unwrap();
            assert_eq!(
                (name.venue_id.clone(), name.name.clone(), name.valid_from.clone(), name.valid_to.clone()),
                expected,
                "venue_name {}",
                name.id
            );
        }
        let sql_names: i64 =
            db.query_row("SELECT COUNT(*) FROM venue_names", [], |r| r.get(0)).unwrap();
        assert_eq!(directory.names.len() as i64, sql_names);

        let mut stmt =
            db.prepare("SELECT venue_id, name, capacity FROM venue_halls WHERE id = ?").unwrap();
        for hall in &directory.halls {
            let expected = stmt
                .query_row([&hall.id], |r| {
                    Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, Option<i64>>(2)?))
                })
                .unwrap();
            assert_eq!(
                (hall.venue_id.clone(), hall.name.clone(), hall.capacity),
                expected,
                "venue_hall {}",
                hall.id
            );
        }
        let sql_halls: i64 =
            db.query_row("SELECT COUNT(*) FROM venue_halls", [], |r| r.get(0)).unwrap();
        assert_eq!(directory.halls.len() as i64, sql_halls);
    }

    #[test]
    fn event_ids_at_venue_matches_sql() {
        let db = conn();
        let venue_ids = string_column(
            &db,
            "SELECT venue_id FROM shows WHERE venue_id IS NOT NULL
             GROUP BY venue_id ORDER BY COUNT(DISTINCT event_id) DESC, venue_id LIMIT 3",
            &[],
        );
        assert_eq!(venue_ids.len(), 3);
        for venue_id in &venue_ids {
            let expected: HashSet<String> = string_column(
                &db,
                "SELECT DISTINCT event_id FROM shows WHERE venue_id = ?",
                &[venue_id],
            )
            .into_iter()
            .collect();
            let ordered = event_ids_at_venue(snap(), venue_id);
            let actual: HashSet<String> = ordered.iter().cloned().collect();
            assert_eq!(actual.len(), ordered.len(), "重複なし ({venue_id})");
            assert!(!expected.is_empty());
            assert_eq!(actual, expected, "venue {venue_id}");
        }
        assert!(event_ids_at_venue(snap(), "存在しない会場id").is_empty());
    }

    #[test]
    fn venues_matching_matches_sql() {
        let db = conn();
        let event_ids = all_event_ids(&db);
        for query in ["ホール", "ドーム", "Zepp", "zepp", "アリーナ"] {
            let placeholders = vec!["?"; event_ids.len()].join(",");
            let sql = format!(
                "SELECT event_id, MIN(venue) AS venue FROM shows
                 WHERE event_id IN ({placeholders})
                   AND venue IS NOT NULL AND LOWER(venue) LIKE ? ESCAPE '\\'
                 GROUP BY event_id"
            );
            // iOS は Swift lowercased() した検索語で LIKE を組む。
            let pattern = format!("%{}%", like_escaped(&query.to_lowercase()));
            let mut args: Vec<&dyn rusqlite::ToSql> =
                event_ids.iter().map(|id| id as &dyn rusqlite::ToSql).collect();
            args.push(&pattern);
            let mut stmt = db.prepare(&sql).unwrap();
            let expected: HashMap<String, String> = stmt
                .query_map(args.as_slice(), |r| {
                    Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
                })
                .unwrap()
                .collect::<Result<_, _>>()
                .unwrap();
            let actual = venues_matching(snap(), query, &event_ids);
            assert!(!expected.is_empty(), "{query} は 1 件以上ヒットする前提");
            assert_eq!(actual, expected, "query {query}");
        }
        // ガード節: 空クエリ・空 id 集合は空辞書。
        assert!(venues_matching(snap(), "", &event_ids).is_empty());
        assert!(venues_matching(snap(), "ホール", &[]).is_empty());
    }

    // ---- イベント詳細 ----

    #[test]
    fn event_record_matches_sql() {
        let db = conn();
        let mut stmt = db
            .prepare(
                "SELECT id, brand_id, name, event_type, is_streaming, is_solo, kind,
                        ticket_open_date, ticket_deadline, ticket_lottery_date, ticket_url,
                        joint_brand_ids
                 FROM events WHERE id = ?",
            )
            .unwrap();
        let mut checked = 0;
        for event in snap().events.iter().step_by(5) {
            let expected = stmt
                .query_row([&event.id], |r| {
                    Ok(EventDetailRecord {
                        id: r.get(0)?,
                        brand_id: r.get(1)?,
                        name: r.get(2)?,
                        event_type: r.get(3)?,
                        // NULL 既定はローダの規約 (iOS Event の decode 既定と同じ)。
                        is_streaming: r.get::<_, Option<i64>>(4)?.unwrap_or(0) != 0,
                        is_solo: r.get::<_, Option<i64>>(5)?.unwrap_or(1) != 0,
                        kind: r.get::<_, Option<String>>(6)?.unwrap_or_else(|| "live".into()),
                        ticket_open_date: r.get(7)?,
                        ticket_deadline: r.get(8)?,
                        ticket_lottery_date: r.get(9)?,
                        ticket_url: r.get(10)?,
                        joint_brand_ids: r.get(11)?,
                        has_streaming: None,
                        has_live_viewing: None,
                    })
                })
                .unwrap();
            let actual = event_record(snap(), &event.id).expect("スナップショットに居る event");
            assert_eq!(actual, expected, "event {}", event.id);
            checked += 1;
        }
        assert!(checked > 50, "サンプル数 ({checked})");
        assert!(event_record(snap(), "存在しないイベント").is_none());
    }

    #[test]
    fn event_stats_match_sql_for_all_events() {
        let db = conn();
        let mut stmt = db
            .prepare(
                "WITH event_shows AS (SELECT id FROM shows WHERE event_id = ?)
                 SELECT
                     (SELECT COUNT(*) FROM event_shows) AS show_count,
                     (SELECT COUNT(*) FROM setlist_items WHERE show_id IN (SELECT id FROM event_shows)) AS total_songs,
                     (SELECT COUNT(DISTINCT song_id) FROM setlist_items WHERE show_id IN (SELECT id FROM event_shows)) AS unique_songs,
                     (SELECT COUNT(DISTINCT idol_id) FROM show_cast WHERE show_id IN (SELECT id FROM event_shows)) AS cast_count",
            )
            .unwrap();
        let mut nonzero = 0;
        for event_id in all_event_ids(&db) {
            let expected = stmt
                .query_row([&event_id], |r| {
                    Ok(EventStatsRecord {
                        show_count: r.get::<_, i64>(0)? as u32,
                        total_songs: r.get::<_, i64>(1)? as u32,
                        unique_songs: r.get::<_, i64>(2)? as u32,
                        cast_count: r.get::<_, i64>(3)? as u32,
                    })
                })
                .unwrap();
            let actual = event_stats(snap(), &event_id);
            assert_eq!(actual, expected, "event {event_id}");
            if expected.total_songs > 0 {
                nonzero += 1;
            }
        }
        assert!(nonzero > 100, "セトリつきイベントが十分ある前提 ({nonzero})");
        // 未知 id は SQL でも全ゼロになる (CTE が空) — 同じ値を返すこと。
        assert_eq!(event_stats(snap(), "存在しないイベント"), EventStatsRecord::default());
    }

    /// fetchEventAttendanceQuery の写経を丸ごと実行し、全イベントで照合する。
    #[test]
    fn event_attendance_matches_sql_for_all_events() {
        let db = conn();
        let mut covered_cross = 0; // >= 3 ブランド (実出演者母集団) の分岐
        let mut covered_debut = 0; // debut_date 除外の分岐
        let mut covered_some = 0;
        for event_id in all_event_ids(&db) {
            let actual = event_attendance(snap(), &event_id);

            // 1) primary brand と joint_brand_ids
            let row: Option<(Option<String>, Option<String>)> = db
                .query_row(
                    "SELECT brand_id, joint_brand_ids FROM events WHERE id = ?",
                    [&event_id],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )
                .ok();
            let Some((Some(brand_id), joint_raw)) = row else {
                assert!(actual.is_none(), "brand NULL の {event_id} は None");
                continue;
            };
            let joint: Vec<String> = joint_raw
                .as_deref()
                .map(|s| {
                    s.split(',')
                        .map(str::trim)
                        .filter(|p| !p.is_empty())
                        .map(str::to_string)
                        .collect()
                })
                .unwrap_or_default();
            let mut candidates = vec![brand_id.clone()];
            candidates.extend(joint);

            // 2) shows (date, sort_order 順)
            let show_ids = string_column(
                &db,
                "SELECT id FROM shows WHERE event_id = ? ORDER BY date, sort_order",
                &[&event_id],
            );
            let event_start_date: Option<String> = db
                .query_row(
                    "SELECT date FROM shows WHERE event_id = ? ORDER BY date, sort_order LIMIT 1",
                    [&event_id],
                    |r| r.get(0),
                )
                .ok();

            // 3) brandIdols (3 分岐の写経)
            let placeholders = vec!["?"; candidates.len()].join(",");
            let expected_brand_idols: Vec<String> = if candidates.len() >= 3 {
                covered_cross += 1;
                string_column(
                    &db,
                    "SELECT id FROM idols WHERE id IN (
                         SELECT sc.idol_id FROM show_cast sc
                           JOIN shows sh ON sh.id = sc.show_id WHERE sh.event_id = ?1
                         UNION
                         SELECT sp.idol_id FROM setlist_performers sp
                           JOIN setlist_items si ON si.id = sp.setlist_item_id
                           JOIN shows sh ON sh.id = si.show_id WHERE sh.event_id = ?1
                     ) AND is_external = 0
                     ORDER BY sort_order",
                    &[&event_id],
                )
            } else if let Some(start) = &event_start_date {
                let sql = format!(
                    "SELECT id FROM idols
                     WHERE brand_id IN ({placeholders}) AND is_external = 0
                       AND (debut_date IS NULL OR debut_date <= ?)
                     ORDER BY sort_order"
                );
                let mut args: Vec<&dyn rusqlite::ToSql> =
                    candidates.iter().map(|c| c as &dyn rusqlite::ToSql).collect();
                args.push(start);
                let with_debut = string_column(&db, &sql, args.as_slice());
                let sql_all = format!(
                    "SELECT id FROM idols WHERE brand_id IN ({placeholders}) AND is_external = 0
                     ORDER BY sort_order"
                );
                let args_all: Vec<&dyn rusqlite::ToSql> =
                    candidates.iter().map(|c| c as &dyn rusqlite::ToSql).collect();
                if with_debut.len() != string_column(&db, &sql_all, args_all.as_slice()).len() {
                    covered_debut += 1;
                }
                with_debut
            } else {
                let sql = format!(
                    "SELECT id FROM idols WHERE brand_id IN ({placeholders}) AND is_external = 0
                     ORDER BY sort_order"
                );
                let args: Vec<&dyn rusqlite::ToSql> =
                    candidates.iter().map(|c| c as &dyn rusqlite::ToSql).collect();
                string_column(&db, &sql, args.as_slice())
            };
            if expected_brand_idols.is_empty() {
                assert!(actual.is_none(), "母集団ゼロの {event_id} は None");
                continue;
            }
            let actual = actual.unwrap_or_else(|| panic!("{event_id} は Some のはず"));
            covered_some += 1;
            // idols.sort_order は bundle でユニーク (引き継ぎメモ) → 逐語一致。
            assert_eq!(actual.brand_idol_ids, expected_brand_idols, "brandIdols {event_id}");
            let actual_show_ids: Vec<String> =
                actual.shows.iter().map(|s| s.id.clone()).collect();
            assert_matches_up_to_ties(&format!("shows {event_id}"), &actual_show_ids, &show_ids, show_key);

            // 4) presence (歌唱 ∪ show_cast、brand 絞りあり)
            let presence_sql = format!(
                "SELECT show_id, idol_id FROM (
                     SELECT DISTINCT si.show_id AS show_id, sp.idol_id AS idol_id
                     FROM setlist_items si
                     JOIN setlist_performers sp ON sp.setlist_item_id = si.id
                     JOIN shows sh ON sh.id = si.show_id
                     JOIN idols i ON i.id = sp.idol_id
                     WHERE sh.event_id = ? AND i.brand_id IN ({placeholders})
                     UNION
                     SELECT DISTINCT sc.show_id AS show_id, sc.idol_id AS idol_id
                     FROM show_cast sc
                     JOIN shows sh ON sh.id = sc.show_id
                     JOIN idols i ON i.id = sc.idol_id
                     WHERE sh.event_id = ? AND i.brand_id IN ({placeholders})
                 )"
            );
            let mut args: Vec<&dyn rusqlite::ToSql> = vec![&event_id];
            args.extend(candidates.iter().map(|c| c as &dyn rusqlite::ToSql));
            args.push(&event_id);
            args.extend(candidates.iter().map(|c| c as &dyn rusqlite::ToSql));
            let mut stmt = db.prepare(&presence_sql).unwrap();
            let mut expected_presence: HashMap<String, HashSet<String>> = HashMap::new();
            let rows = stmt
                .query_map(args.as_slice(), |r| {
                    Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
                })
                .unwrap();
            for row in rows {
                let (show_id, idol_id) = row.unwrap();
                expected_presence.entry(show_id).or_default().insert(idol_id);
            }
            let actual_presence: HashMap<String, HashSet<String>> = actual
                .presence_by_show
                .into_iter()
                .map(|(show_id, ids)| (show_id, ids.into_iter().collect()))
                .collect();
            assert_eq!(actual_presence, expected_presence, "presence {event_id}");

            // 5) lead / guest (brand 絞りなし)
            let mut stmt = db
                .prepare(
                    "SELECT sc.show_id, sc.idol_id, sc.cast_role
                     FROM show_cast sc JOIN shows sh ON sh.id = sc.show_id
                     WHERE sh.event_id = ? AND sc.cast_role IN ('lead', 'guest')",
                )
                .unwrap();
            let mut expected_lead: HashMap<String, HashSet<String>> = HashMap::new();
            let mut expected_guest: HashMap<String, HashSet<String>> = HashMap::new();
            let rows = stmt
                .query_map([&event_id], |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, String>(1)?,
                        r.get::<_, String>(2)?,
                    ))
                })
                .unwrap();
            for row in rows {
                let (show_id, idol_id, role) = row.unwrap();
                let map = if role == "lead" { &mut expected_lead } else { &mut expected_guest };
                map.entry(show_id).or_default().insert(idol_id);
            }
            let to_sets = |m: HashMap<String, Vec<String>>| -> HashMap<String, HashSet<String>> {
                m.into_iter().map(|(k, v)| (k, v.into_iter().collect())).collect()
            };
            assert_eq!(to_sets(actual.lead_by_show), expected_lead, "lead {event_id}");
            assert_eq!(to_sets(actual.guest_by_show), expected_guest, "guest {event_id}");
        }
        assert!(covered_some > 100, "出席表ありイベント数 ({covered_some})");
        assert!(covered_cross >= 1, ">=3 ブランドの越境フェス分岐を踏む前提");
        assert!(covered_debut >= 1, "debut_date 除外が効くイベントを踏む前提");
        assert!(event_attendance(snap(), "存在しないイベント").is_none());
    }

    // ---- リリース (event_releases) ----

    #[test]
    fn event_releases_empty_on_bundle() {
        // Bundle には event_releases 表が無い → 全イベントで空 (動的検出の既定値側)。
        for event in &snap().events {
            assert!(event_releases(snap(), &event.id).is_empty());
        }
    }

    /// 移行済み Documents DB を模した DB (Bundle のコピー + event_releases) で
    /// `ORDER BY release_date ASC, sort_order ASC` を照合する。
    #[test]
    fn event_releases_match_sql_on_documents_like_db() {
        let path = std::env::temp_dir().join(format!(
            "imas_core_event_releases_{}.sqlite",
            std::process::id()
        ));
        let path_str = path.to_str().unwrap().to_string();
        let _ = std::fs::remove_file(&path);
        std::fs::copy(db_path(), &path).expect("bundle DB をコピーできる");

        // 実在の event / show に円盤をぶら下げる (NULL release_date・孤児 show/event 込み)。
        let (event_a, event_b, show_a) = {
            let db = conn();
            let event_a: String = db
                .query_row(
                    "SELECT event_id FROM shows GROUP BY event_id
                     HAVING COUNT(*) >= 2 ORDER BY event_id LIMIT 1",
                    [],
                    |r| r.get(0),
                )
                .unwrap();
            let event_b: String = db
                .query_row("SELECT id FROM events WHERE id <> ? ORDER BY id LIMIT 1", [&event_a], |r| r.get(0))
                .unwrap();
            let show_a: String = db
                .query_row(
                    "SELECT id FROM shows WHERE event_id = ? ORDER BY date, sort_order LIMIT 1",
                    [&event_a],
                    |r| r.get(0),
                )
                .unwrap();
            (event_a, event_b, show_a)
        };
        {
            let db = Connection::open(&path).unwrap();
            db.execute_batch(
                "CREATE TABLE event_releases (
                     id TEXT PRIMARY KEY, event_id TEXT NOT NULL, show_id TEXT,
                     product_type TEXT NOT NULL, title TEXT NOT NULL, catalog_number TEXT,
                     release_date TEXT, jacket_url TEXT, purchase_url TEXT,
                     sort_order INTEGER NOT NULL DEFAULT 0)",
            )
            .unwrap();
            let mut insert = db
                .prepare(
                    "INSERT INTO event_releases
                     (id, event_id, show_id, product_type, title, catalog_number,
                      release_date, jacket_url, purchase_url, sort_order)
                     VALUES (?,?,?,?,?,?,?,?,?,?)",
                )
                .unwrap();
            // (id, event, show, release_date, sort_order)
            type ReleaseSeed<'a> = (&'a str, &'a str, Option<&'a str>, Option<&'a str>, i64);
            let rows: Vec<ReleaseSeed> = vec![
                // (id, event, show, release_date, sort_order) — 同日 sort_order 違い・
                // NULL release_date (ASC 先頭)・DAY 別円盤・孤児 show を混ぜる。
                ("er_box", &event_a, None, Some("2024-06-01"), 1),
                ("er_day1", &event_a, Some(show_a.as_str()), Some("2024-06-01"), 0),
                ("er_tbd", &event_a, None, None, 5),
                ("er_orphan_show", &event_a, Some("sh_削除済み公演"), Some("2023-01-01"), 2),
                ("er_other", &event_b, None, Some("2020-01-01"), 0),
            ];
            for (id, event_id, show_id, date, sort_order) in rows {
                insert
                    .execute(rusqlite::params![
                        id,
                        event_id,
                        show_id,
                        "bluray",
                        format!("{id} 円盤"),
                        Option::<String>::None,
                        date,
                        Option::<String>::None,
                        Option::<String>::None,
                        sort_order
                    ])
                    .unwrap();
            }
            // 孤児 event の行はロード時に読み飛ばされる (どの結果にも出ない)。
            insert
                .execute(rusqlite::params![
                    "er_orphan_event",
                    "ev_存在しないイベント",
                    Option::<String>::None,
                    "dvd",
                    "孤児円盤",
                    Option::<String>::None,
                    Some("2024-01-01"),
                    Option::<String>::None,
                    Option::<String>::None,
                    0
                ])
                .unwrap();
        }

        let docs_snap = load_snapshot(&path_str).expect("Documents 相当 DB をロードできる");
        let db = Connection::open(&path).unwrap();
        for event_id in [&event_a, &event_b] {
            let expected = string_column(
                &db,
                "SELECT id FROM event_releases WHERE event_id = ?
                 ORDER BY release_date ASC, sort_order ASC",
                &[event_id],
            );
            let actual: Vec<String> =
                event_releases(&docs_snap, event_id).into_iter().map(|r| r.id).collect();
            assert!(!expected.is_empty());
            assert_eq!(actual, expected, "event {event_id}");
        }
        // NULL release_date は ASC の先頭・孤児 show は show_id=None で行が残る。
        let releases = event_releases(&docs_snap, &event_a);
        assert_eq!(releases.first().map(|r| r.id.as_str()), Some("er_tbd"));
        let orphan = releases.iter().find(|r| r.id == "er_orphan_show").unwrap();
        assert_eq!(orphan.show_id, None);
        let day1 = releases.iter().find(|r| r.id == "er_day1").unwrap();
        assert_eq!(day1.show_id.as_deref(), Some(show_a.as_str()));
        // 孤児 event の行はどこにも現れない。
        assert!(docs_snap.event_releases.iter().all(|r| r.id != "er_orphan_event"));

        let _ = std::fs::remove_file(&path);
    }
}
