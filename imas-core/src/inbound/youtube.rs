//! YouTube の URL の FFI 面。規則は [`crate::domain::youtube`]。

use crate::domain::youtube::{self as domain, YouTubeEmbedPlayer, YouTubePlayerEvent, YouTubeVideoRef};

/// 動画の URL の列を 1 回で読む (動画 id とサムネイル。入力と同じ並び)。
#[uniffi::export]
pub fn youtube_video_refs(urls: Vec<String>) -> Vec<YouTubeVideoRef> {
    domain::video_refs(&urls)
}

/// 投稿の前の先行判定: http(s) で、ホストが YouTube のものか (パスの形はサーバが見る)。
#[uniffi::export]
pub fn youtube_is_upload_url(url: String) -> bool {
    domain::is_youtube_url(&url)
}

/// 参考動画をアプリ内で再生する埋め込みプレーヤー。動画 id が読めなければ `None`。
#[uniffi::export]
pub fn youtube_embed_player(url: String) -> Option<YouTubeEmbedPlayer> {
    domain::embed_player(&url)
}

/// プレーヤーのページが送った文字列を知らせに読む。
#[uniffi::export]
pub fn youtube_player_event(message: String) -> YouTubePlayerEvent {
    domain::player_event(&message)
}
