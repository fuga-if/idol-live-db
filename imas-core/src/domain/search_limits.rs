//! 検索の件数と文字数の上限 (面ごとの定数)。
//!
//! 面ごとに値が違うのは意図 (Q-06)。値を変えるときは、どの面の話かをここで確かめる。

/// アプリ (iOS / Android) の横断検索で、エンティティ種別ごとに並べる件数の上限。
/// iOS `searchQuery` の `.limit(20)` の写し。
pub const GLOBAL_SEARCH_LIMIT: usize = 20;

/// Web の横断検索で、種別ごとに並べる件数の上限。
///
/// アプリの上限は [`GLOBAL_SEARCH_LIMIT`] (20)。面ごとに違うのは意図 (Q-06)。
pub const WEB_SEARCH_LIMIT_PER_KIND: usize = 30;

/// Web で歌詞を探すときの最小文字数。1 文字は索引で絞れず全走査になるので 2 文字から。
///
/// Worker の最小文字数 1 は TS 側 (imas-live-api) に別にある。
pub const WEB_LYRICS_SEARCH_MIN_CHARS: usize = 2;
