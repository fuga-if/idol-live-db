//! 歌詞行を「語のまとまり」に切る。コールのアンカーを指で選ぶための単位。
//!
//! ## なぜ要るか
//!
//! コールのアンカー選択は「開始文字と終了文字を順にタップ」か「長押しからなぞる」
//! だった。どちらも**指で 1 文字を狙わせる**ので当てにくく、しかも 1 回タップした
//! だけでは何も起きず、見た目に出ない「終点待ち」に入る。押したのに何も起きない、
//! もう一度押したら意図しない範囲が選ばれる、という状態になっていた。
//!
//! 実際のコールのアンカーはほぼ「語」か「短いフレーズ」なので、**触った位置の語を
//! ひとまとまりで返す**ことにする。1 タップで確定できる。
//!
//! ## 切り方
//!
//! 形態素解析はしない。**同じ種類の文字が続く限りひとまとまり**という機械的な規則にする。
//! 予測できることの方が大事で、辞書に依存すると「なぜここで切れたのか」が説明できない。
//!
//! ```text
//! ダミー歌詞のサンプル行です → [ダミー][歌詞][の][サンプル][行][です]
//! ```
//!
//! - 漢字 (々 と繰り返し記号を含む)
//! - ひらがな
//! - カタカナ (長音符 ー と中黒 ・ を含む — 「ミュージック・アワー」で切れない)
//! - 英数字 (アポストロフィを含む — "don't" で切れない)
//! - それ以外 (記号・空白) は 1 文字ずつ
//!
//! 長音符と小書き仮名は直前の種別に付ける。単独では意味を持たないので、
//! 「ー」だけが選ばれると使えないアンカーになる。

/// 文字の種別。同じ種別が続く限り 1 つのまとまりにする。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Class {
    Kanji,
    Hiragana,
    Katakana,
    Alnum,
    /// 記号・空白。ひとまとまりにせず 1 文字ずつ切る。
    Other,
}

/// 直前の種別に吸収される文字 (単独では語にならない)。
fn is_trailing(c: char) -> bool {
    matches!(c,
        'ー' | 'ｰ' | '〜' | '～'          // 長音・波ダッシュ
        | '々' | '〻' | 'ヽ' | 'ヾ' | 'ゝ' | 'ゞ' // 繰り返し記号
        | '・'                              // カタカナ語の中黒
        | '\'' | '\u{2019}'                 // don't / don’t
    )
}

fn classify(c: char) -> Class {
    match c {
        'ぁ'..='ゟ' => Class::Hiragana,
        'ァ'..='ヿ' | 'ｦ'..='ﾟ' => Class::Katakana,
        '\u{4E00}'..='\u{9FFF}' | '\u{3400}'..='\u{4DBF}' | '\u{F900}'..='\u{FAFF}' => Class::Kanji,
        c if c.is_alphanumeric() => Class::Alnum,
        _ => Class::Other,
    }
}

/// 歌詞行の中の 1 まとまり。位置は **Unicode スカラー**単位
/// (コールのアンカーがスカラー添字で保存されているのに合わせる)。
#[derive(uniffi::Record, Debug, Clone, PartialEq, Eq)]
pub struct LyricChunk {
    pub start: u32,
    pub end: u32,
    pub text: String,
}

/// 行を語のまとまりに切る。
pub fn chunks(line: &str) -> Vec<LyricChunk> {
    let mut out: Vec<LyricChunk> = Vec::new();
    let mut current: Option<(u32, Class, String)> = None;
    let mut pos: u32 = 0;

    // `chars()` は Unicode スカラーを 1 つずつ返すので、位置はそのまま +1 でよい
    // (コールのアンカーもスカラー添字で保存されている)。
    for c in line.chars() {
        let class = classify(c);

        match &mut current {
            // 長音符等は直前のまとまりに吸収する (単独では使えないアンカーになる)。
            Some((_, _, text)) if is_trailing(c) => {
                text.push(c);
            }
            Some((_, cls, text)) if *cls == class && class != Class::Other => {
                text.push(c);
            }
            _ => {
                if let Some((start, _, text)) = current.take() {
                    out.push(LyricChunk { start, end: start + text.chars().count() as u32, text });
                }
                // 先頭が長音符等でも、付ける先が無ければ普通の 1 文字として扱う。
                current = Some((pos, class, c.to_string()));
            }
        }
        pos += 1;
    }
    if let Some((start, _, text)) = current {
        out.push(LyricChunk { start, end: start + text.chars().count() as u32, text });
    }
    out
}

/// スカラー位置 `scalar` を含むまとまりを返す。範囲外なら `None`。
///
/// 指が触れた位置から「その語」を引くのに使う。行末 (`scalar == 長さ`) は
/// 最後のまとまりに寄せる — 行の右端を触ったときに何も選べないと使いにくい。
pub fn chunk_at(line: &str, scalar: u32) -> Option<LyricChunk> {
    let all = chunks(line);
    all.iter()
        .find(|c| c.start <= scalar && scalar < c.end)
        .or_else(|| all.last().filter(|c| scalar >= c.end))
        .cloned()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn texts(line: &str) -> Vec<String> {
        chunks(line).into_iter().map(|c| c.text).collect()
    }

    #[test]
    fn splits_on_character_class() {
        assert_eq!(
            texts("ダミー歌詞のサンプル行です"),
            ["ダミー", "歌詞", "の", "サンプル", "行", "です"]
        );
    }

    #[test]
    fn keeps_long_vowel_and_nakaguro_inside_katakana() {
        // 「ミュージック・アワー」で中黒や長音符では切らない。単独の「ー」を
        // 選ばせても使えるアンカーにならない。
        assert_eq!(texts("ミュージック・アワー"), ["ミュージック・アワー"]);
    }

    #[test]
    fn keeps_apostrophe_inside_latin_words() {
        assert_eq!(texts("don't stop"), ["don't", " ", "stop"]);
    }

    #[test]
    fn punctuation_is_its_own_chunk() {
        assert_eq!(texts("行こう！今すぐ"), ["行", "こう", "！", "今", "すぐ"]);
    }

    #[test]
    fn positions_are_scalar_offsets() {
        let got = chunks("ダミー歌詞");
        assert_eq!(got[0], LyricChunk { start: 0, end: 3, text: "ダミー".into() });
        assert_eq!(got[1], LyricChunk { start: 3, end: 5, text: "歌詞".into() });
    }

    #[test]
    fn chunk_at_finds_the_word_under_the_finger() {
        // 「歌詞」の 2 文字目を触っても「歌詞」全体が返る。
        assert_eq!(chunk_at("ダミー歌詞のサンプル", 4).unwrap().text, "歌詞");
        assert_eq!(chunk_at("ダミー歌詞のサンプル", 0).unwrap().text, "ダミー");
    }

    #[test]
    fn chunk_at_past_the_end_falls_back_to_the_last_chunk() {
        // 行の右端の余白を触ったときに何も選べないと使いにくい。
        assert_eq!(chunk_at("ダミー歌詞", 99).unwrap().text, "歌詞");
    }

    #[test]
    fn empty_line_has_no_chunks() {
        assert!(chunks("").is_empty());
        assert!(chunk_at("", 0).is_none());
    }

    #[test]
    fn chunks_cover_the_whole_line_without_gaps() {
        // アンカーの位置計算がズレないこと。どの行でも「隙間なく連続」でなければならない。
        for line in ["ダミー歌詞のサンプル行です", "行こう！今すぐ", "don't stop", "ミュージック・アワー"] {
            let got = chunks(line);
            assert_eq!(got.first().unwrap().start, 0, "{line}");
            assert_eq!(got.last().unwrap().end, line.chars().count() as u32, "{line}");
            for pair in got.windows(2) {
                assert_eq!(pair[0].end, pair[1].start, "{line}");
            }
        }
    }
}
