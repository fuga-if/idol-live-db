//! マスタ DB の不変インメモリスナップショット (Phase 2 の中核)。
//!
//! 設計 (docs/SHARED_CORE_STUDY.md「インメモリスナップショット方式」):
//! - SQLite は永続の正 (CloudKit 同期の着地・UserMark 保全)。読み取りはここには来ない。
//! - 本構造体は起動時 + sync 後に outbound::sqlite_loader が一括構築する派生キャッシュ。
//!   不変なのでロック不要・メインスレッドから同期で読んで良い (µs 級)。
//! - 実測 (2026-08-25): 12万行ロード 61ms / +37MB / 全曲走査 268µs (Mac, release)。
//! - **user_marks (担当/お気に入り/メモ/回収) は載せない**。ユーザーデータは書き込みが
//!   頻繁でプラットフォーム側が正。必要な判定は解決済み id 集合を引数で受け取る
//!   (SongListFiltering と同じ流儀)。
//!
//! 索引は「クエリ関数が O(1)/O(log n) で入れる形」をロード時に前計算する。
//! 行の参照は Vec の添字 (u32) で持つ (String id の再引きを避ける)。
//! SQL 時代に毎回払っていた ORDER BY (sort_order 順・日付順・position 順) も
//! 構築時に一度だけ払い、クエリ側は前計算済みの並びをそのまま流す。

use std::collections::HashMap;

/// songs 全カラム。GRDB Record / Room Entity と同じ「Record = Entity 兼用」の現実的判断。
#[derive(Debug, Clone)]
pub struct Song {
    pub id: String,
    pub title: String,
    pub title_kana: Option<String>,
    pub brand_id: Option<String>,
    pub song_type: Option<String>,
    pub release_date: Option<String>,
    pub duration_sec: Option<i64>,
    pub composer: Option<String>,
    pub lyricist: Option<String>,
    pub arranger: Option<String>,
    pub cd_series: Option<String>,
    pub cd_title: Option<String>,
    pub artwork_url: Option<String>,
    pub preview_url: Option<String>,
    pub apple_music_id: Option<String>,
    pub apple_music_album_id: Option<String>,
    pub isrc: Option<String>,
    pub lyrics_url: Option<String>,
    pub parent_song_id: Option<String>,
    pub singer_label: Option<String>,
    pub unit_name: Option<String>,
    pub unit_id: Option<String>,
    pub series_group: Option<String>,
    pub jasrac_code: Option<String>,
}

/// idols の主要カラム (一覧・歌唱者表示・検索に要るもの)。
#[derive(Debug, Clone)]
pub struct Idol {
    pub id: String,
    pub brand_id: Option<String>,
    pub name: String,
    pub name_kana: Option<String>,
    pub color: Option<String>,
    pub sort_order: Option<i64>,
    pub nickname: Option<String>,
    pub aliases: Option<String>,
    pub attribute: Option<String>,
    pub is_external: bool,
    pub birthday: Option<String>,
    pub debut_date: Option<String>,
}

/// events 全カラム (Bundle スキーマ基準)。
///
/// has_streaming / has_live_viewing はアプリ側マイグレーションが Documents DB にだけ
/// 足す列で、Bundle の master.sqlite には無い。曲スライスのクエリはどれも参照しない
/// ので載せない (イベントスライス移送時に列の有無を動的検出して拡張する)。
#[derive(Debug, Clone)]
pub struct Event {
    pub id: String,
    pub brand_id: Option<String>,
    pub name: String,
    pub event_type: String,
    /// 互換のため残置 (iOS Event と同じ注記)。新コードからは参照しない。
    pub is_streaming: bool,
    /// 互換のため残置。新コードからは参照しない。
    pub is_solo: bool,
    /// イベント種別 ("live"/"festival"/"release_event"/"radio"/"stream")。
    /// 回収判定の「リアルライブのみ」(live/festival) の絞り込みに使う。
    pub kind: String,
    pub ticket_open_date: Option<String>,
    pub ticket_deadline: Option<String>,
    pub ticket_lottery_date: Option<String>,
    pub ticket_url: Option<String>,
    /// 合同ライブの追加ブランド ID (カンマ区切り)。nil なら単一ブランド。
    pub joint_brand_ids: Option<String>,
}

/// shows 全カラム (Bundle スキーマ基準)。event は events Vec の添字。
/// has_streaming / has_live_viewing は Event と同じ理由で未ロード。
#[derive(Debug, Clone)]
pub struct Show {
    pub id: String,
    /// 親イベント (events の添字)。FK 孤児はロード時に読み飛ばすので必ず有効。
    pub event: u32,
    pub name: String,
    /// YYYY-MM-DD。並びの前計算はすべてこの文字列順 (辞書順 = 日付順)。
    pub date: String,
    pub venue: Option<String>,
    pub venue_city: Option<String>,
    pub start_time: Option<String>,
    pub sort_order: i64,
    pub performer_type: Option<String>,
    pub venue_id: Option<String>,
    pub hall: Option<String>,
    pub stream_platform: Option<String>,
}

/// setlist_items の行。show / song は各 Vec の添字。
#[derive(Debug, Clone)]
pub struct SetlistItem {
    pub id: String,
    pub show: u32,
    pub song: u32,
    pub position: i64,
    pub section: Option<String>,
    pub notes: Option<String>,
    /// この披露限りのユニット表記 (恒常ユニットは songs.unit_name 側)。
    pub unit_name: Option<String>,
}

/// units 全カラム。
#[derive(Debug, Clone)]
pub struct Unit {
    pub id: String,
    pub brand_id: String,
    pub name: String,
    pub is_permanent: bool,
    pub name_alt: Option<String>,
}

/// 曲→歌唱者リンク。`idol` は idols Vec の添字。
#[derive(Debug, Clone)]
pub struct SongArtistLink {
    pub idol: u32,
    pub role: String,
}

/// アイドル→曲リンク (song_artists の逆引き)。`song` は songs Vec の添字。
/// role を持つのは fetchIdolSongs(role:) 相当の role 絞り込みを O(links) で行うため。
#[derive(Debug, Clone)]
pub struct IdolSongLink {
    pub song: u32,
    pub role: String,
}

/// 公演→出演者リンク (show_cast)。`idol` は idols Vec の添字。
/// cast_role は 'member' / 'lead' / 'guest' (スキーマ既定 'member')。
#[derive(Debug, Clone)]
pub struct ShowCastLink {
    pub idol: u32,
    pub cast_role: String,
}

/// 不変スナップショット本体。構築は outbound::sqlite_loader のみが行う。
///
/// 「◯◯_by_△△」の Vec は △△ 側と同じ添字で並ぶ逆引き索引。各索引の並び順は
/// SQL 時代の ORDER BY を構築時に前計算したもの (各フィールドの doc に明記)。
/// SQL では未規定だった同順位の並びは、添字を最終キーに使って決定的にしてある
/// (プラットフォーム間で同一結果を返すことが共有コアの目的なので、非決定性は残さない)。
#[derive(Debug, Default)]
pub struct Snapshot {
    pub songs: Vec<Song>,
    pub idols: Vec<Idol>,
    pub events: Vec<Event>,
    pub shows: Vec<Show>,
    pub setlist_items: Vec<SetlistItem>,
    pub units: Vec<Unit>,

    /// songs と同じ添字。リンクは idol の sort_order 順に格納済み
    /// (SQL 時代の `ORDER BY i.sort_order` を構築時に前計算)。
    pub artists_by_song: Vec<Vec<SongArtistLink>>,
    /// idols と同じ添字。song_artists の逆引き (role つき)。
    /// release_date 降順 (SQL 時代の fetchIdolSongs `ORDER BY s.release_date DESC`)。
    /// NULL の release_date は末尾 (SQLite の DESC と同じ NULLS LAST)。
    pub songs_by_idol: Vec<Vec<IdolSongLink>>,
    /// songs と同じ添字。setlist_items における披露回数
    /// (= setlist_items_by_song の各長さ。二重集計しないよう構築時に導出)。
    pub performance_counts: Vec<u32>,

    /// events と同じ添字。配下 show の添字を (date ASC, sort_order ASC) で格納
    /// (iOS fetchShows(eventId:) の `.order(date, sort_order)` と同じ)。
    pub shows_by_event: Vec<Vec<u32>>,
    /// shows と同じ添字。セトリ項目の添字を position 昇順で格納。
    pub setlist_items_by_show: Vec<Vec<u32>>,
    /// songs と同じ添字。披露履歴 (fetchSongPerformanceHistory) の表示順:
    /// show.date DESC。SQL では同日内が未規定だったので、同日は
    /// (show.sort_order ASC, position ASC) で決定的にしてある。
    pub setlist_items_by_song: Vec<Vec<u32>>,
    /// setlist_items と同じ添字。その披露の歌唱メンバー (setlist_performers)。
    /// idol の sort_order 順。
    pub performers_by_item: Vec<Vec<u32>>,
    /// idols と同じ添字。setlist_performers の逆引き (歌った setlist_item 添字群)。
    /// setlist_items_by_song と同じ (show.date DESC) 順 — fetchIdolSongHistory /
    /// fetchIdolPerformedSongs が新しい順で走査するため。
    pub performed_items_by_idol: Vec<Vec<u32>>,

    /// shows と同じ添字。show_cast の出演者リンク。idol の sort_order 順。
    pub cast_by_show: Vec<Vec<ShowCastLink>>,
    /// idols と同じ添字。show_cast の逆引き (出演した show 添字群)。show.date DESC。
    pub cast_shows_by_idol: Vec<Vec<u32>>,

    /// units と同じ添字。メンバー idol 添字を sort_order 順で格納。
    pub members_by_unit: Vec<Vec<u32>>,
    /// idols と同じ添字。所属ユニット添字を unit.name 昇順で格納
    /// (iOS fetchIdolUnits の `ORDER BY u.name`。BINARY 照合 = バイト列比較で一致)。
    pub units_by_idol: Vec<Vec<u32>>,
    /// units と同じ添字。songs.unit_id によるユニット持ち曲。release_date 昇順
    /// (iOS fetchUnitSongs の `.order(release_date)`。NULL は先頭 = SQLite ASC と同じ)。
    pub songs_by_unit: Vec<Vec<u32>>,

    /// songs と同じ添字。この曲を親 (parent_song_id) とする派生曲の添字群。
    /// (title_kana, title) 昇順 — fetchVariantSongs の family 表示順
    /// (根が先頭・続いて子が 50 音順) の「子」の部分を前計算したもの。
    pub variants_by_song: Vec<Vec<u32>>,

    pub song_index_by_id: HashMap<String, u32>,
    pub idol_index_by_id: HashMap<String, u32>,
    pub event_index_by_id: HashMap<String, u32>,
    pub show_index_by_id: HashMap<String, u32>,
    pub unit_index_by_id: HashMap<String, u32>,
}

impl Snapshot {
    pub fn song(&self, id: &str) -> Option<&Song> {
        self.song_index_by_id.get(id).map(|&i| &self.songs[i as usize])
    }

    pub fn idol(&self, id: &str) -> Option<&Idol> {
        self.idol_index_by_id.get(id).map(|&i| &self.idols[i as usize])
    }

    pub fn event(&self, id: &str) -> Option<&Event> {
        self.event_index_by_id.get(id).map(|&i| &self.events[i as usize])
    }

    pub fn show(&self, id: &str) -> Option<&Show> {
        self.show_index_by_id.get(id).map(|&i| &self.shows[i as usize])
    }

    pub fn unit(&self, id: &str) -> Option<&Unit> {
        self.unit_index_by_id.get(id).map(|&i| &self.units[i as usize])
    }

    /// 歌唱者 (role 指定時はその role のみ) を sort_order 順で返す。
    pub fn song_artists(&self, song_id: &str, role: Option<&str>) -> Vec<&Idol> {
        let Some(&si) = self.song_index_by_id.get(song_id) else { return vec![] };
        self.artists_by_song[si as usize]
            .iter()
            .filter(|l| role.is_none_or(|r| l.role == r))
            .map(|l| &self.idols[l.idol as usize])
            .collect()
    }

    /// 派生曲一族の根 (parent_song_id を 1 段遡る)。自分が根ならそのまま。
    ///
    /// fetchVariantSongs と同じく「自分が派生側でも親側でも同じ一族」を引くための入口。
    /// parent_song_id が壊れて未知 id を指す場合は自分を根とみなす (孤児で落ちない)。
    pub fn variant_root(&self, song: u32) -> u32 {
        match &self.songs[song as usize].parent_song_id {
            Some(pid) => self.song_index_by_id.get(pid).copied().unwrap_or(song),
            None => song,
        }
    }

    /// show_cast における cast_role。行が無い (= セトリだけの出演) なら None。
    /// SQL 時代の `COALESCE(..., 'member')` の 'member' 既定はクエリ層で補うこと
    /// (「行が無い」と「member と明記」を区別できる情報を落とさないため)。
    pub fn show_cast_role(&self, show: u32, idol: u32) -> Option<&str> {
        self.cast_by_show[show as usize]
            .iter()
            .find(|l| l.idol == idol)
            .map(|l| l.cast_role.as_str())
    }
}
