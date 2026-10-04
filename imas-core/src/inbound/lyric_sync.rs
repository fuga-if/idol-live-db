//! 歌詞と再生位置の連動・行の「ここ好き」の FFI 口。規則は domain::lyric_sync。

use crate::domain::lyric_sync as d;
pub use crate::domain::lyric_sync::{LyricAside, LyricLikeHeat, LyricOverlaySplit, LyricRuby, LyricRubyChoice, LyricSpan};

/// いま歌われている行の添字 (`starts` は表示順の各行の開始 ms)。イントロ中は `None`。
#[uniffi::export]
pub fn lyric_active_line(starts: Vec<Option<i64>>, position_ms: i64) -> Option<u32> {
    d::active_line(&starts, position_ms)
}

/// 再生位置に追従できるだけの記録があるか。
#[uniffi::export]
pub fn lyric_has_timing(starts: Vec<Option<i64>>) -> bool {
    d::has_timing(&starts)
}

/// 記録モードで次にタップしてもらう行 (`kinds` は各行の種別 `lyric`/`marker`/`blank`)。
#[uniffi::export]
pub fn lyric_next_recordable(kinds: Vec<String>, after: Option<u32>) -> Option<u32> {
    d::next_recordable(&kinds, after)
}

/// 「ここ好き」の保存値を行 ID の並びに戻す。
#[uniffi::export]
pub fn lyric_likes_parse(stored: Option<String>) -> Vec<String> {
    d::parse_likes(stored.as_deref())
}

/// 行の「ここ好き」を付け外しした後の保存値。`None` なら印を消す。
#[uniffi::export]
pub fn lyric_likes_toggle(stored: Option<String>, line_id: String) -> Option<String> {
    d::toggle_like(stored.as_deref(), &line_id)
}

/// 行ごとの「ここ好き」人数を、曲を `buckets` 等分した山にする (シークバー用)。
#[uniffi::export]
pub fn lyric_like_heat(starts: Vec<Option<i64>>, counts: Vec<u32>, duration_ms: i64, buckets: u32) -> LyricLikeHeat {
    d::like_heat(&starts, &counts, duration_ms, buckets)
}

/// 時刻のある行の帯 (始まり〜次の行の始まり)、時刻順。タイミング編集のタイムラインに使う。
#[uniffi::export]
pub fn lyric_line_spans(starts: Vec<Option<i64>>, duration_ms: i64) -> Vec<LyricSpan> {
    d::line_spans(&starts, duration_ms)
}

/// コールの帯 (時刻順、次のコールまで・最長 3 秒)。タイミング編集のコールの段に使う。
#[uniffi::export]
pub fn lyric_call_spans(starts: Vec<Option<i64>>, duration_ms: i64) -> Vec<LyricSpan> {
    d::call_spans(&starts, duration_ms)
}

/// いま出すコールの添字 (`starts` はコールを曲の順に並べた開始 ms)。間が空いたら `None`。
#[uniffi::export]
pub fn lyric_active_call(starts: Vec<Option<i64>>, position_ms: i64) -> Option<u32> {
    d::active_call(&starts, position_ms)
}

/// 行の本文を括弧の外 (メイン) と中 (被せ) に分ける。歌詞プレイヤーの 2 段目に使う。
#[uniffi::export]
pub fn lyric_overlay_split(text: String) -> LyricOverlaySplit {
    d::split_overlay(&text)
}

/// 被せの行か (`layer` は保存された指定 `overlay` / `main`、無ければ括弧で決める)。
#[uniffi::export]
pub fn lyric_is_overlay_line(text: String, layer: Option<String>) -> bool {
    d::is_overlay_line(&text, layer.as_deref())
}

/// いま光らせる被せの行の添字 (`starts` は被せの行だけ時刻、他は None)。
#[uniffi::export]
pub fn lyric_active_overlay(starts: Vec<Option<i64>>, position_ms: i64) -> Option<u32> {
    d::active_overlay(&starts, position_ms)
}

/// 被せの行の帯 (タイミング編集の被せの段)。
#[uniffi::export]
pub fn lyric_overlay_spans(starts: Vec<Option<i64>>, duration_ms: i64) -> Vec<LyricSpan> {
    d::overlay_spans(&starts, duration_ms)
}

/// パート分けを付ける曲か (原唱者が 2 人以上)。ソロ曲では入口も帯も出さない。
#[uniffi::export]
pub fn lyric_parts_applicable(original_artist_count: u32) -> bool {
    d::parts_applicable(original_artist_count)
}

/// 「同時」のコールが掛かっている歌詞と同じ文字か (行を出さず、歌詞のその部分に印を付ける)。
/// `timing` はコールの出し方 (`over` / `after`)。
#[uniffi::export]
pub fn lyric_call_echoes_lyric(anchor_text: String, call_text: String, timing: String) -> bool {
    d::call_echoes_lyric(&anchor_text, &call_text, &timing)
}

/// 行の中のコールが歌詞と同じ文字か (同時、または歌詞の括弧の中に掛かっている)。`start`/`end` はスカラー位置。
#[uniffi::export]
pub fn lyric_call_echoes_line(line_text: String, start: u32, end: u32, call_text: String, timing: String) -> bool {
    d::call_echoes_line(&line_text, start, end, &call_text, &timing)
}

/// 行の中の振り仮名 (《》)。画面は親字の上に小さく出す。
#[uniffi::export]
pub fn lyric_ruby_spans(text: String) -> Vec<LyricRuby> {
    d::ruby_spans(&text)
}

/// 区切り編集で並べる振り仮名の候補 (いまの振り仮名と、振り仮名にできる括弧)。
#[uniffi::export]
pub fn lyric_ruby_choices(text: String) -> Vec<LyricRubyChoice> {
    d::ruby_choices(&text)
}

/// 括弧で書いた脇の字の範囲 (括弧ごと)。画面は一段小さく薄く出す。
#[uniffi::export]
pub fn lyric_aside_spans(text: String) -> Vec<LyricAside> {
    d::aside_spans(&text)
}

/// 行の本文の範囲を、被せを外したメインの行 (`lyric_overlay_split` の main) の中の範囲に置き直す。
/// まるごと括弧の中なら `None`。
#[uniffi::export]
pub fn lyric_main_range(text: String, start: u32, end: u32) -> Option<LyricAside> {
    d::main_range(&text, start, end)
}
