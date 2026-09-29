//! ゲーム進捗 (自己ベスト・連続達成) の FFI 面。ロジックは domain::game_progress。
//!
//! 保存の実体は各 OS のまま (iOS: UserDefaults / Android: SharedPreferences)。
//! ここを通るのは **「今の保存値 → 新しい保存値」の計算だけ**で、ストアは
//! 「読む → 呼ぶ → 書く」に痩せる。
//!
//! 日付は epoch 秒ではなく端末ローカル日の文字列で受け取る。暦法 (和暦・仏暦) や
//! 夏時間の解決はラッパの責務で、iOS は `DailyPick.dayKey()` /
//! `DailyPick.previousDayKey()` の戻り値をそのまま渡す。理由は
//! domain::game_progress と domain::daily_pick のモジュールコメント参照。

use crate::domain::game_progress::{
    self, DailySheetGate, GameProgressUpdate, GameRecord, GameStreakState,
};

/// 1 セッション分の結果を記録した後の保存値 (記録 + 連続達成) と、
/// 結果画面の「自己ベスト更新！」バッジ判定を 1 回で返す。
///
/// 呼び出し側は返ってきた `record` / `streak` をそのまま保存するだけでよい
/// (`did_record == false` なら入力と同値なので保存を省いてもよい)。
#[uniffi::export]
pub fn game_progress_apply_result(
    record: GameRecord,
    streak: GameStreakState,
    score: i32,
    out_of: i32,
    today_key: String,
    yesterday_key: String,
) -> GameProgressUpdate {
    game_progress::apply_result(&record, &streak, score, out_of, &today_key, &yesterday_key)
}

/// 表示用の連続達成日数 (今日・昨日まで達成なら継続中、それより古ければ 0)。
#[uniffi::export]
pub fn game_progress_display_streak(
    streak: GameStreakState,
    today_key: String,
    yesterday_key: String,
) -> i32 {
    streak.display_streak(&today_key, &yesterday_key)
}

/// 今日ぶんのデイリーチャレンジを達成済みか。
#[uniffi::export]
pub fn game_progress_did_clear_today(streak: GameStreakState, today_key: String) -> bool {
    streak.did_clear_today(&today_key)
}

/// 自己ベストの正答率 (0–100 の四捨五入)。まだ記録が無ければ `None`
/// (ハブは「—」、結果画面は今回の率で代用するので、文言はラッパ側で決める)。
#[uniffi::export]
pub fn game_progress_best_rate_percent(record: GameRecord) -> Option<i32> {
    record.best_rate_percent()
}

/// 日替わりシート (起動時の『今日の1曲』) を今日出すか + 保存し直す日。
#[uniffi::export]
pub fn game_progress_daily_sheet_gate(
    last_shown_day: Option<String>,
    today_key: String,
) -> DailySheetGate {
    game_progress::daily_sheet_gate(last_shown_day.as_deref(), &today_key)
}

#[cfg(test)]
mod tests {
    use super::*;

    // MARK: - 委譲の疎通

    const TODAY: &str = "2026-08-25";
    const YESTERDAY: &str = "2026-08-24";

    fn cleared(day: &str, streak: i32, total: i32) -> GameStreakState {
        GameStreakState { streak, total_days: total, last_cleared_day: Some(day.to_string()) }
    }

    /// 日キー 2 つの並び順が入れ替わっていないことまで見る。
    /// 入れ替わると「昨日達成」が「今日はもう達成済み」と読み替わり、
    /// 連続日数が 5 ではなく 4 のまま据え置かれる。
    #[test]
    fn apply_result_passes_the_day_keys_in_order() {
        let got = game_progress_apply_result(
            GameRecord::default(),
            cleared(YESTERDAY, 4, 12),
            3,
            5,
            TODAY.to_string(),
            YESTERDAY.to_string(),
        );
        assert_eq!(got.streak, cleared(TODAY, 5, 13));
        assert_eq!(got.record.last_score, 3);
        assert_eq!(got.record.last_out_of, 5);
        assert!(got.did_record);
    }

    #[test]
    fn display_streak_and_did_clear_today_delegate() {
        let streak = cleared(YESTERDAY, 7, 20);
        assert_eq!(
            game_progress_display_streak(streak.clone(), TODAY.to_string(), YESTERDAY.to_string()),
            7
        );
        assert!(!game_progress_did_clear_today(streak, TODAY.to_string()));
        assert!(game_progress_did_clear_today(cleared(TODAY, 7, 20), TODAY.to_string()));
    }

    /// `Option<String>` を借用へ落とす橋渡しが、未表示 (None) でも同日 2 回目でも壊れないこと。
    #[test]
    fn daily_sheet_gate_delegates_both_arms() {
        assert!(game_progress_daily_sheet_gate(None, TODAY.to_string()).should_show);
        let repeat = game_progress_daily_sheet_gate(Some(TODAY.to_string()), TODAY.to_string());
        assert!(!repeat.should_show);
        assert_eq!(repeat.last_shown_day, TODAY);
    }
}
