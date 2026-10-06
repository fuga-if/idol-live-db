//! 歌詞の投稿の FFI 面。規則は [`crate::domain::lyric_submission`]。

use crate::domain::lyric_submission::{self as domain, LyricSubmissionCheck, LyricSubmissionIssue};

/// 入力のたびに通す。整えた本文・行数・文字数・注意・送れるか。
#[uniffi::export]
pub fn lyric_submission_check(text: String, agreed_to_guideline: bool) -> LyricSubmissionCheck {
    domain::check_submission(&text, agreed_to_guideline)
}

/// 注意の文。
#[uniffi::export]
pub fn lyric_submission_issue_message(issue: LyricSubmissionIssue) -> String {
    domain::issue_message(&issue)
}

/// 送信を止める注意か (止めないものは注意として出すだけ)。
#[uniffi::export]
pub fn lyric_submission_issue_blocks(issue: LyricSubmissionIssue) -> bool {
    domain::blocks_submit(&issue)
}

/// 本文の文字数の上限 (UTF-16)。
#[uniffi::export]
pub fn lyric_submission_max_chars() -> u32 {
    domain::MAX_CHARS
}

/// 歌詞カードの文字認識の片を、歌詞の行に並べ直す (読み順・段組み・ルビ外し・空行)。
#[uniffi::export]
pub fn lyric_ocr_layout(pieces: Vec<crate::domain::lyric_ocr::OcrPiece>) -> crate::domain::lyric_ocr::LyricOcrLayout {
    crate::domain::lyric_ocr::layout(&pieces)
}

/// 読み取った本文を入力欄に足す (空なら置き換え、書きかけなら空行を挟んで後ろへ)。
#[uniffi::export]
pub fn lyric_ocr_append(draft: String, recognized: String) -> String {
    crate::domain::lyric_ocr::append_to_draft(&draft, &recognized)
}

/// その曲に歌詞を投稿できるか (アイマス系ブランドの非カバー曲だけ)。
#[uniffi::export]
pub fn lyric_submission_allowed(brand_id: String, song_type: Option<String>, singer_label: Option<String>) -> bool {
    domain::submission_allowed(&brand_id, song_type.as_deref(), singer_label.as_deref())
}

/// 投稿ガイドライン (読みもの画面に並べる塊)。
#[uniffi::export]
pub fn lyric_submission_guideline() -> Vec<domain::LyricGuideBlock> {
    domain::guideline()
}

/// 歌詞カードの読み取りの使い方 (手順と説明)。
#[uniffi::export]
pub fn lyric_ocr_steps() -> Vec<crate::domain::lyric_ocr::LyricOcrStep> {
    crate::domain::lyric_ocr::steps()
}

/// 1 片の読み取り候補から 1 つ選ぶ (辞書に無い英単語が少ないもの)。見直しが要るかも返す。
#[uniffi::export]
pub fn lyric_ocr_pick_candidate(candidates: Vec<crate::domain::lyric_ocr::OcrCandidate>) -> crate::domain::lyric_ocr::OcrChoice {
    crate::domain::lyric_ocr::pick_candidate(&candidates)
}

/// 綴りを確かめる英単語 (OS の辞書に通す)。
#[uniffi::export]
pub fn lyric_ocr_latin_words(text: String) -> Vec<String> {
    crate::domain::lyric_ocr::latin_words(&text)
}
