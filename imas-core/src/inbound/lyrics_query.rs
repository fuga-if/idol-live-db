//! 歌詞検索の式の FFI 面。規則は [`crate::domain::lyrics_query`]。

/// 検索欄の入力を、サーバに送る歌詞検索の式にする (空白は AND、語は `"…"` で囲う)。
/// 語が無ければ空文字。
#[uniffi::export]
pub fn simple_lyrics_query(raw: String) -> String {
    crate::domain::lyrics_query::simple_lyrics_query(&raw)
}
