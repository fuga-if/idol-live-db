//! YouTube の URL の FFI 面。規則は [`crate::domain::youtube`]。

use crate::domain::youtube::{self as domain, YouTubeVideoRef};

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
