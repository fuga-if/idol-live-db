//! かなの「行」への分類 (あ行・か行 …)。曲一覧のよみ目次に使う。
//!
//! 判定の前に検索と同じ畳み込み ([`crate::domain::text_search_index::prepare_needle`])
//! を通すので、カタカナ表記も濁点付きも同じ行に入る。目次と検索で当たり方がずれない。

use crate::domain::text_search_index::prepare_needle;

/// 見出しに使う行の名前を返す。かなでも英数でもないものは「その他」。
pub fn kana_row_label(text: &str) -> &'static str {
    let folded = String::from_utf8(prepare_needle(text)).unwrap_or_default();
    let Some(c) = folded.chars().next() else { return "その他" };
    if c.is_ascii_alphanumeric() {
        return "英数";
    }
    // 範囲の端に注意: `ゔ` (U+3094) は `ん` (U+3093) の**後ろ**にあるので
    // 「わ行」の範囲に巻き込まれる。小書きの `ゕゖ` (U+3095..=U+3096) も同じ理由で
    // 素直に上から並べると「その他」に落ちる。どちらも先に拾う。
    match c {
        // う + 濁点。畳み込みが `う゛` を 1 文字にするので実データに現れる。
        'ゔ' => "あ",
        // 小書きの か / け。
        'ゕ'..='ゖ' => "か",
        'ぁ'..='お' => "あ",
        'か'..='ご' => "か",
        'さ'..='ぞ' => "さ",
        'た'..='ど' => "た",
        'な'..='の' => "な",
        'は'..='ぽ' => "は",
        'ま'..='も' => "ま",
        'ゃ'..='よ' => "や",
        'ら'..='ろ' => "ら",
        'ゎ'..='ん' => "わ",
        _ => "その他",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn katakana_and_dakuten_land_in_the_same_row_as_their_plain_form() {
        assert_eq!(kana_row_label("あいうえお"), "あ");
        assert_eq!(kana_row_label("オネガイ"), "あ");
        assert_eq!(kana_row_label("がっこう"), "か");
        assert_eq!(kana_row_label("ぱすてる"), "は");
    }

    #[test]
    fn the_characters_at_the_end_of_the_hiragana_block_are_not_lost() {
        // ゔ は ん の後ろ、ゕゖ はさらに後ろにある。
        assert_eq!(kana_row_label("ゔぃじょん"), "あ");
        assert_eq!(kana_row_label("ヴィジョン"), "あ");
        assert_eq!(kana_row_label("ゕ"), "か");
    }

    #[test]
    fn latin_digits_and_symbols_are_separated() {
        assert_eq!(kana_row_label("Thank You!"), "英数");
        assert_eq!(kana_row_label("9:02pm"), "英数");
        assert_eq!(kana_row_label("★"), "その他");
        assert_eq!(kana_row_label(""), "その他");
        // 漢字始まりは「その他」(よみが空の曲でだけ起きる)。
        assert_eq!(kana_row_label("夢"), "その他");
    }
}
