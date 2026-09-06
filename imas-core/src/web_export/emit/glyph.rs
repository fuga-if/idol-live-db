//! 絵の代わりに札や丸へ置く短い文字 (ブランドカードの見出し・アイドルのモノグラム)。
//!
//! 「何文字まで入るか」は出面の枠の都合なので `web_export` に置く (アプリは縮めて省略記号で
//! 切るが、出面は札として整う長さに切る)。名前そのものの規則 (`Idol::short_name`) は domain。

use crate::domain::snapshot::Idol;

/// ブランドカードの見出し。短縮名をそのまま出し、長すぎるものだけ丸める。
pub fn brand_glyph(short_name: &str) -> String {
    const MAX_CHARS: usize = 6;
    short_name.chars().take(MAX_CHARS).collect()
}

/// アイドルの丸に置く短い名。4 文字までは `Idol::short_name` (nickname > given_name > name) の
/// まま、長い名 (アナスタシア・アスラン=ベルゼビュートⅡ世 など) は先頭 2 文字。
/// 48px の丸で読めるのは 4 文字までで、縮めて省略記号で切るより頭文字の札として整う。
pub fn idol_monogram(idol: &Idol) -> String {
    const FULL_MAX_CHARS: usize = 4;
    const INITIAL_CHARS: usize = 2;
    let short_name = idol.short_name();
    if short_name.chars().count() <= FULL_MAX_CHARS {
        short_name.to_string()
    } else {
        short_name.chars().take(INITIAL_CHARS).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn idol(name: &str, given_name: Option<&str>, nickname: Option<&str>) -> Idol {
        Idol {
            name: name.to_string(),
            given_name: given_name.map(str::to_string),
            nickname: nickname.map(str::to_string),
            ..Idol::default()
        }
    }

    #[test]
    fn brand_glyph_keeps_short_names_and_rounds_long_ones() {
        assert_eq!(brand_glyph("ML"), "ML");
        assert_eq!(brand_glyph("シャイニーカラーズ"), "シャイニーカ");
    }

    #[test]
    fn idol_monogram_takes_the_short_name_when_it_fits() {
        // 名の選び方そのものは domain::snapshot::idol_short_name の受け持ち。
        assert_eq!(idol_monogram(&idol("春日未来", Some("未来"), None)), "未来");
        assert_eq!(idol_monogram(&idol("園田海未", Some("海未"), Some("うみ"))), "うみ");
        assert_eq!(idol_monogram(&idol("ジュリア", None, None)), "ジュリア");
        assert_eq!(idol_monogram(&idol("音無小鳥", None, None)), "音無小鳥");
    }

    #[test]
    fn idol_monogram_cuts_long_names_to_two_initials() {
        assert_eq!(idol_monogram(&idol("アナスタシア", None, None)), "アナ");
        assert_eq!(idol_monogram(&idol("アスラン=ベルゼビュートⅡ世", None, None)), "アス");
        assert_eq!(idol_monogram(&idol("園田海未", None, Some("うみちゃん"))), "うみ");
    }
}
