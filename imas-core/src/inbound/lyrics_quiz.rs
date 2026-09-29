//! 歌詞クイズの FFI 面。ロジックは domain::lyrics_quiz。
//!
//! 呼び出しの順:
//! - 画面を開く / ブランドを切り替える → [`lyrics_quiz_pool_estimate`]
//! - ゲーム開始 → [`lyrics_quiz_session`] で曲の並び (予備込み) をまとめて受け取る
//! - 1 曲の歌詞が届いた → [`lyrics_quiz_excerpt`]。`None` ならその曲を飛ばす
//! - ヒント表示 → [`lyrics_quiz_hint_state`]、選択肢をタップ → [`lyrics_quiz_answer`]
//! - 結果を見る → [`lyrics_quiz_session_result`] → `game_progress_apply_result`
//!
//! ⚠️ 歌詞の断片 (`LyricsQuizLine` / `LyricsQuizExcerpt`) は画面に出す間だけ持つこと
//! (JASRAC 許諾の条件。domain::lyrics_quiz のモジュールコメント参照)。

use crate::domain::lyrics_quiz::{
    self as lq, LyricsQuizExcerpt, LyricsQuizHintKind, LyricsQuizHintState, LyricsQuizLine,
    LyricsQuizMode, LyricsQuizPoolEstimate, LyricsQuizQuestion, LyricsQuizSongRef,
    LYRICS_QUIZ_SPARE_SONGS,
};
use crate::domain::prng::SplitMix64;
use crate::domain::quiz_generation::{
    self as quiz, QuizAnswerOutcome, QuizSessionResult, QuizTally, SESSION_LENGTH,
    SONG_QUIZ_MAX_POINTS,
};

/// 出題設定画面の候補数。`published_song_ids` は `GET /lyrics/published` の中身。
#[uniffi::export]
pub fn lyrics_quiz_pool_estimate(
    songs: Vec<LyricsQuizSongRef>,
    published_song_ids: Vec<String>,
    selected_brand_ids: Vec<String>,
) -> LyricsQuizPoolEstimate {
    lq::lyrics_quiz_pool_estimate(&songs, &published_song_ids, &selected_brand_ids)
}

/// 1 ゲーム分の曲の並び (出題数 + 予備)。返る index は引数 `songs` を指す。候補不足なら空。
#[uniffi::export]
pub fn lyrics_quiz_session(
    songs: Vec<LyricsQuizSongRef>,
    published_song_ids: Vec<String>,
    selected_brand_ids: Vec<String>,
    seed: u64,
) -> Vec<LyricsQuizQuestion> {
    lq::lyrics_quiz_session(
        &songs,
        &published_song_ids,
        &selected_brand_ids,
        SESSION_LENGTH + LYRICS_QUIZ_SPARE_SONGS,
        &mut SplitMix64(seed),
    )
}

/// 1 曲の歌詞から出題を切り出す。出題に向かない歌詞なら `None`。
#[uniffi::export]
pub fn lyrics_quiz_excerpt(
    lines: Vec<LyricsQuizLine>,
    song_title: String,
    has_singer: bool,
    mode: LyricsQuizMode,
    seed: u64,
) -> Option<LyricsQuizExcerpt> {
    lq::lyrics_quiz_excerpt(&lines, &song_title, has_singer, mode, &mut SplitMix64(seed))
}

/// 獲得点と次に開けるヒント。
#[uniffi::export]
pub fn lyrics_quiz_hint_state(
    hints: Vec<LyricsQuizHintKind>,
    revealed: u32,
    answered: bool,
) -> LyricsQuizHintState {
    lq::lyrics_quiz_hint_state(&hints, revealed, answered)
}

/// 解答。曲名当ては曲 id、続きはどれは選択肢の位置 (文字列) を渡す。
#[uniffi::export]
pub fn lyrics_quiz_answer(
    revealed: u32,
    picked: String,
    answer: String,
    before: QuizTally,
) -> QuizAnswerOutcome {
    lq::lyrics_quiz_answer(revealed, &picked, &answer, &before, SESSION_LENGTH)
}

/// セッション終了時のリザルト (自己ベストは `game_progress_apply_result` 側)。
#[uniffi::export]
pub fn lyrics_quiz_session_result(tally: QuizTally) -> QuizSessionResult {
    quiz::quiz_session_result(&tally, SONG_QUIZ_MAX_POINTS, SESSION_LENGTH)
}

/// 4 択が組める最低曲数 (設定画面の案内文用)。
#[uniffi::export]
pub fn lyrics_quiz_minimum_pool() -> u32 {
    lq::lyrics_quiz_minimum_pool()
}
