//! Spotify 連携の FFI 面。判断は domain::spotify。

use crate::domain::spotify::{
    self, SongClues, SpotifyClientIdCheck, SpotifyFailure, SpotifySetupGuide, SpotifyTrackCandidate,
};
use crate::inbound::snapshot_store::{SnapshotError, SnapshotStore};

/// 設定画面の案内 (手順・貼る値・注意)。
#[uniffi::export]
pub fn spotify_setup_guide() -> SpotifySetupGuide {
    spotify::setup_guide()
}

/// 貼られた Client ID を確かめる。
#[uniffi::export]
pub fn spotify_check_client_id(input: String) -> SpotifyClientIdCheck {
    spotify::check_client_id(&input)
}

/// 書き出したプレイリストに付ける説明。
#[uniffi::export]
pub fn spotify_playlist_description() -> String {
    spotify::PLAYLIST_DESCRIPTION.to_string()
}

/// うまくいかなかったときの文。
#[uniffi::export]
pub fn spotify_failure_message(failure: SpotifyFailure) -> String {
    spotify::failure_message(failure)
}

/// 書き出しの結果の文。
#[uniffi::export]
pub fn spotify_export_summary(added: u32, missing: u32) -> String {
    spotify::export_summary(added, missing)
}

#[uniffi::export]
impl SnapshotStore {
    /// 曲を Spotify で探す検索語 (試す順)。曲を知らなければ空。
    pub fn spotify_search_queries(&self, song_id: String) -> Result<Vec<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(SongClues::from_snapshot(&snap, &song_id)
            .map(|c| spotify::search_queries(&c))
            .unwrap_or_default())
    }

    /// 検索結果から同じ曲を選ぶ (`candidates` の何番目か)。無ければ `None`。
    pub fn spotify_pick_track(
        &self,
        song_id: String,
        candidates: Vec<SpotifyTrackCandidate>,
    ) -> Result<Option<u32>, SnapshotError> {
        let snap = self.current()?;
        Ok(SongClues::from_snapshot(&snap, &song_id)
            .and_then(|c| spotify::pick_track(&c, &candidates))
            .map(|i| i as u32))
    }
}
