//! 日替わりピックの FFI 面。ロジックは domain::daily_pick。
//!
//! 端末ローカル日が単位で、しかも原本 Swift 同様に**端末の暦法設定** (和暦・仏暦 等) に
//! 従う必要がある。暦法は OS からしか分からず chrono はグレゴリオ暦固定なので、
//! epoch 秒ではなく暦法解決済みのローカル日付成分をラッパから受け取る
//! (iOS: `Calendar.current.dateComponents([.year, .month, .day], from:)`)。
//!
//! 「前日」に対応する FFI は無い。前日算出は端末カレンダーの演算
//! (夏時間・era 跨ぎ・暦ごとのうるう規則) が必要なのでラッパ側の責務で、
//! 1 日戻した日付の成分を同じ `daily_pick_day_key` に通す
//! (iOS: `Calendar.current.date(byAdding: .day, value: -1, to:)`)。
//! 設計意図の詳細は domain::daily_pick のモジュールコメント参照。

use crate::domain::daily_pick::{self, DailyPickBrandCandidates, DailyPickKind};

#[uniffi::export]
pub fn daily_pick_day_key(local_year: i32, local_month: i32, local_day: i32) -> String {
    daily_pick::day_key(local_year, local_month, local_day)
}

#[uniffi::export]
pub fn daily_pick_stable_index(seed: String, modulo: i64) -> i64 {
    daily_pick::stable_index(&seed, modulo)
}

#[uniffi::export]
pub fn daily_pick_song_index(day_key: String, brand_id: String, count: i64) -> i64 {
    daily_pick::song_index(&day_key, &brand_id, count)
}

/// 全ブランド分の「今日の 1 曲」を 1 回の FFI 呼び出しで解決する一括版。
/// 返り値は `brands` と同順の index 列。呼び出し側が自国の曲 ID 配列を index で引く。
#[uniffi::export]
pub fn daily_pick_song_indices(day_key: String, brands: Vec<DailyPickBrandCandidates>) -> Vec<u32> {
    daily_pick::song_indices(&day_key, &brands)
}

#[uniffi::export]
pub fn daily_pick_idol_index(day_key: String, brand_id: String, count: i64) -> i64 {
    daily_pick::idol_index(&day_key, &brand_id, count)
}

/// 全ブランド分の「今日のアイドル」を 1 回の FFI 呼び出しで解決する一括版
/// (`daily_pick_song_indices` と同じ規約)。
#[uniffi::export]
pub fn daily_pick_idol_indices(day_key: String, brands: Vec<DailyPickBrandCandidates>) -> Vec<u32> {
    daily_pick::idol_indices(&day_key, &brands)
}

/// 起動時の日替わりシートがその日どちらを出すか (偶数日=曲 / 奇数日=アイドル)。
///
/// 日付キー文字列ではなく日の成分を受け取るのは、キーの表記が端末の暦法で変わるため
/// (domain::daily_pick::sheet_kind のコメント参照)。
#[uniffi::export]
pub fn daily_pick_sheet_kind(local_day: i32) -> DailyPickKind {
    daily_pick::sheet_kind(local_day)
}
