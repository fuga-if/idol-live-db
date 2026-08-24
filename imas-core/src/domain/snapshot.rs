//! マスタ DB の不変インメモリスナップショット (Phase 2 の中核)。
//!
//! 設計 (docs/SHARED_CORE_STUDY.md「インメモリスナップショット方式」):
//! - SQLite は永続の正 (CloudKit 同期の着地・UserMark 保全)。読み取りはここには来ない。
//! - 本構造体は起動時 + sync 後に outbound::sqlite_loader が一括構築する派生キャッシュ。
//!   不変なのでロック不要・メインスレッドから同期で読んで良い (µs 級)。
//! - 実測 (2026-08-25): 12万行ロード 61ms / +37MB / 全曲走査 268µs (Mac, release)。
//!
//! 索引は「クエリ関数が O(1)/O(log n) で入れる形」をロード時に前計算する。
//! 行の参照は Vec の添字 (u32) で持つ (String id の再引きを避ける)。

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

/// 曲→歌唱者リンク。`idol` は idols Vec の添字。
#[derive(Debug, Clone)]
pub struct SongArtistLink {
    pub idol: u32,
    pub role: String,
}

/// 不変スナップショット本体。構築は outbound::sqlite_loader のみが行う。
#[derive(Debug, Default)]
pub struct Snapshot {
    pub songs: Vec<Song>,
    pub idols: Vec<Idol>,
    /// songs と同じ添字。リンクは idol の sort_order 順に格納済み
    /// (SQL 時代の `ORDER BY i.sort_order` を構築時に前計算)。
    pub artists_by_song: Vec<Vec<SongArtistLink>>,
    /// idols と同じ添字。歌唱に関わる song 添字群。
    pub songs_by_idol: Vec<Vec<u32>>,
    /// songs と同じ添字。setlist_items における披露回数。
    pub performance_counts: Vec<u32>,
    pub song_index_by_id: HashMap<String, u32>,
    pub idol_index_by_id: HashMap<String, u32>,
}

impl Snapshot {
    pub fn song(&self, id: &str) -> Option<&Song> {
        self.song_index_by_id.get(id).map(|&i| &self.songs[i as usize])
    }

    pub fn idol(&self, id: &str) -> Option<&Idol> {
        self.idol_index_by_id.get(id).map(|&i| &self.idols[i as usize])
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
}
