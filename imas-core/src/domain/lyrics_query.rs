//! 歌詞検索でサーバに送る式の組み立て (iOS `LyricsSearchQuery.simple` から移した)。

/// 検索欄の入力 (空白区切り) を式にする。**空白は AND**。
///
/// OR ではなく AND にしたのは、OR だと 2 語打つと 1 語より結果が増えるため。絞ろうとして
/// 増えるのは直感に反する (夢 = 1,273 曲 / 夢 + 翼 は AND 98 曲・OR 1,308 曲)。
///
/// 語は必ず `"…"` で囲う。歌詞は全角スペースで区切られている (「空を描いて行くよ　ここで光るよ」)
/// ので、囲わないと空白 = AND として割れる。語の中の `"` は落とす。空白は全角も含む。
/// 語が無ければ空文字 (検索しない)。
pub fn simple_lyrics_query(raw: &str) -> String {
    raw.split(char::is_whitespace)
        .map(|term| term.replace('"', ""))
        .filter(|term| !term.is_empty())
        .map(|term| format!("\"{term}\""))
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terms_are_quoted_and_joined_as_and() {
        assert_eq!(simple_lyrics_query("夢 翼"), "\"夢\" \"翼\"");
        assert_eq!(simple_lyrics_query("  夢\u{3000}翼\t\n"), "\"夢\" \"翼\"", "全角スペースも区切り");
        assert_eq!(simple_lyrics_query("\"夢\" \"\""), "\"夢\"", "語の中の引用符は落とし、空になった語は捨てる");
        assert_eq!(simple_lyrics_query("   "), "");
        assert_eq!(simple_lyrics_query(""), "");
    }
}
