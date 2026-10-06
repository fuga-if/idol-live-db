//! お気に入りの曲から載せる曲を選ぶ FFI 面。ロジックは domain::favorite_song_picks。

use crate::domain::favorite_song_picks::{FavoriteSongPicks, ProfileSongInput};

/// 選ぶ画面に並べるもの (`chosen` が None ならまだ選んでいない)。
#[uniffi::export]
pub fn favorite_song_picks(
    chosen: Option<Vec<String>>,
    favorites: Vec<ProfileSongInput>,
) -> FavoriteSongPicks {
    crate::domain::favorite_song_picks::favorite_song_picks(chosen.as_deref(), &favorites)
}

/// 1 曲を載せる / 外した後の選択。
#[uniffi::export]
pub fn favorite_song_toggle(
    chosen: Option<Vec<String>>,
    favorites: Vec<ProfileSongInput>,
    song_id: String,
) -> Vec<String> {
    crate::domain::favorite_song_picks::favorite_song_toggle(
        chosen.as_deref(),
        &favorites,
        &song_id,
    )
}

/// 並べ替えた選択を整える (お気に入りに今ある曲だけ・重複なし・上限まで)。
#[uniffi::export]
pub fn favorite_song_normalize(ids: Vec<String>, favorites: Vec<ProfileSongInput>) -> Vec<String> {
    crate::domain::favorite_song_picks::favorite_song_normalize(&ids, &favorites)
}
