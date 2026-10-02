//! 歌詞と再生位置の連動・行の「ここ好き」の FFI 口。規則は domain::lyric_sync。

use crate::domain::lyric_sync as d;

/// いま歌われている行の添字 (`starts` は表示順の各行の開始 ms)。イントロ中は `None`。
#[uniffi::export]
pub fn lyric_active_line(starts: Vec<Option<i64>>, position_ms: i64) -> Option<u32> {
    d::active_line(&starts, position_ms)
}

/// 再生位置に追従できるだけの記録があるか。
#[uniffi::export]
pub fn lyric_has_timing(starts: Vec<Option<i64>>) -> bool {
    d::has_timing(&starts)
}

/// 記録モードで次にタップしてもらう行 (`kinds` は各行の種別 `lyric`/`marker`/`blank`)。
#[uniffi::export]
pub fn lyric_next_recordable(kinds: Vec<String>, after: Option<u32>) -> Option<u32> {
    d::next_recordable(&kinds, after)
}

/// 「ここ好き」の保存値を行 ID の並びに戻す。
#[uniffi::export]
pub fn lyric_likes_parse(stored: Option<String>) -> Vec<String> {
    d::parse_likes(stored.as_deref())
}

/// 行の「ここ好き」を付け外しした後の保存値。`None` なら印を消す。
#[uniffi::export]
pub fn lyric_likes_toggle(stored: Option<String>, line_id: String) -> Option<String> {
    d::toggle_like(stored.as_deref(), &line_id)
}
