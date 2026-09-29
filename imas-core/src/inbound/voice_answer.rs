//! 声で答えるイントロドンの照合の FFI 面。規則は [`crate::domain::voice_answer`]。
//! かな・ローマ字・英字への変換と読みの取り出しは OS が行い、変換済みの文字列を渡す。

use crate::domain::voice_answer::{self as domain, VoiceAnswerTargets, VoiceHeard};

/// 曲名の飾り (括弧の中・` / ` 以降・`feat.` 以降・記号) を落とす。変換の前に通す。
#[uniffi::export]
pub fn voice_strip_title_decorations(title: String) -> String {
    domain::strip_title_decorations(&title)
}

/// OS が変換した正解の綴りから、照合に使うものを選ぶ (出題ごとに 1 回)。
#[uniffi::export]
pub fn voice_answer_targets(
    normalized: String,
    katakana: String,
    romaji: String,
    reading: String,
    latin: String,
) -> VoiceAnswerTargets {
    domain::voice_answer_targets(&normalized, &katakana, &romaji, &reading, &latin)
}

/// 漢字を含むか (含むときだけ読みを取って `VoiceHeard.reading` に入れる)。
#[uniffi::export]
pub fn voice_needs_reading(text: String) -> bool {
    domain::needs_reading(&text)
}

/// 聞き取った文字列 (変換済み) が正解に当たるか。聞き取りが更新されるたびに 1 回。
#[uniffi::export]
pub fn voice_answer_matches(targets: VoiceAnswerTargets, heard: VoiceHeard) -> bool {
    domain::voice_answer_matches(&targets, &heard)
}
