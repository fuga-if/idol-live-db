//! 絵の代わりに札へ置く短い文字。
//!
//! 「何文字まで入るか」は出面の枠の都合なので `web_export` に置く。
//! 名前そのものの規則 (`Idol::short_name` 等) は domain。

/// ブランドカードの見出し。短縮名をそのまま出し、長すぎるものだけ丸める。
pub fn brand_glyph(short_name: &str) -> String {
    const MAX_CHARS: usize = 6;
    short_name.chars().take(MAX_CHARS).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn brand_glyph_keeps_short_names_and_rounds_long_ones() {
        assert_eq!(brand_glyph("ML"), "ML");
        assert_eq!(brand_glyph("シャイニーカラーズ"), "シャイニーカ");
    }
}
