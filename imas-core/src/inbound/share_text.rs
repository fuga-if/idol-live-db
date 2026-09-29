//! 共有文言・共有 URL の FFI 面。ロジックは domain::share_text。
//!
//! 共有シート / X アプリの起動と画像カードの描画は各 OS のまま。ここを通るのは
//! 「どの文字列を渡すか」だけで、呼び出し側は組み立てを一切持たない。
//!
//! 1 ユーザー操作 = 1 呼び出し: 共有ボタンを出す時点で `*_payload` を 1 回、
//! 「X にポスト」/「その他でシェア」を押した時点で `share_payload_*` を 1 回呼ぶ。

use crate::domain::quiz_generation::QuizGrade;
use crate::domain::share_text::{
    self, IntroDonShareInput, SetlistShareInput, SharePayload,
};

// -- 共有 URL (Universal Links) ---------------------------------------------

/// イベント詳細への共有 URL。
#[uniffi::export]
pub fn share_event_url(id: String) -> String {
    share_text::event_url(&id)
}

/// 公演セトリへの共有 URL。
#[uniffi::export]
pub fn share_show_url(id: String) -> String {
    share_text::show_url(&id)
}

/// みんなの投票のお題への共有 URL。
#[uniffi::export]
pub fn share_poll_url(id: String) -> String {
    share_text::poll_url(&id)
}

// -- ペイロードの消費 --------------------------------------------------------

/// 標準シェアシートに渡すプレーンテキスト (本文 + 改行 + URL)。
#[uniffi::export]
pub fn share_payload_plain_text(payload: SharePayload) -> String {
    payload.plain_text()
}

/// 「X にポスト」で開く投稿画面 URL。本文と URL を別パラメータで渡すのでリンクカードが出る。
#[uniffi::export]
pub fn share_payload_x_post_url(payload: SharePayload) -> String {
    payload.x_post_url()
}

// -- 画面ごとの共有文 --------------------------------------------------------

/// イベント詳細のシェア文 (イベント名 + Universal Link)。
#[uniffi::export]
pub fn share_event_text(event_id: String, event_name: String) -> String {
    share_text::event_share_text(&event_id, &event_name)
}

/// 公演セトリのシェア文 (公演名 + 日付/会場 + 曲目 + Universal Link)。
#[uniffi::export]
pub fn share_setlist_text(input: SetlistShareInput) -> String {
    share_text::setlist_share_text(&input)
}

/// セトリ予想の「〇〇に投票しました！」。`song_titles` が空なら共有導線ごと隠す前提。
#[uniffi::export]
pub fn share_prediction_votes_payload(
    show_id: String,
    show_name: String,
    song_titles: Vec<String>,
) -> SharePayload {
    share_text::prediction_votes_payload(&show_id, &show_name, &song_titles)
}

/// みんなの投票の「〇〇に投票しました！」。
#[uniffi::export]
pub fn share_poll_votes_payload(
    poll_id: String,
    poll_title: String,
    entity_names: Vec<String>,
) -> SharePayload {
    share_text::poll_votes_payload(&poll_id, &poll_title, &entity_names)
}

/// お題そのもののシェア (まだ投票していない人への誘い)。
///
/// `ends_at_epoch_ms` はお題の締切、`tz_offset_seconds` は **その締切時点での**
/// 端末 TZ の UTC オフセット秒 (iOS `TimeZone.current.secondsFromGMT(for:)`)。
/// 締切は `is_active == true` のときだけ文面に載る。
#[uniffi::export]
pub fn share_poll_invite_payload(
    poll_id: String,
    title: String,
    ends_at_epoch_ms: Option<i64>,
    is_active: bool,
    tz_offset_seconds: i32,
) -> SharePayload {
    share_text::poll_invite_payload(
        &poll_id,
        &title,
        ends_at_epoch_ms,
        is_active,
        tz_offset_seconds,
    )
}

/// クイズ結果のシェア文。`game_display_name` は `GameKind.displayName`。
#[uniffi::export]
pub fn share_quiz_result_text(
    game_display_name: String,
    points: u32,
    max_points: u32,
    grade: QuizGrade,
    correct: u32,
    questions: u32,
) -> String {
    share_text::quiz_result_share_text(
        &game_display_name,
        points,
        max_points,
        grade,
        correct,
        questions,
    )
}

/// イントロドン結果のシェア文。
#[uniffi::export]
pub fn share_intro_don_text(input: IntroDonShareInput) -> String {
    share_text::intro_don_share_text(&input)
}
