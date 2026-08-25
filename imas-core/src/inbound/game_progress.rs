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

    // このモジュールが FFI 面に出している関数の checksum シンボル一覧。
    //
    // UniFFI は export 属性を付けた関数ごとに、引数なしの
    // `uniffi_imas_core_checksum_func_<関数名>` を no_mangle で生成する。ここで
    // extern 宣言して実際に呼ぶことで、「エクスポートが消えた / 改名された」を
    // リンクエラーとして検出する (iOS `GameProgressStore.swift` / Android
    // `GameProgressStore.kt` が参照する生成シンボルが揃っていることの Rust 側の保証)。
    //
    // なぜ tests/ffi_surface.rs の集中一覧だけに任せないか: 別ファイルの一覧は
    // エクスポートを足したときの追記を忘れても「テスト緑」のまま通ってしまい、
    // Swift/Kotlin ラッパのリンク時まで発覚しない (回帰: Phase 8 sync の 20 関数、
    // および本モジュールの 5 関数が、いずれも未登録のまま「テスト緑」と報告された)。
    // エクスポート本体と同じファイルに置けば、関数を触る差分とこの一覧を触る差分が
    // 必ず同じ場所に並ぶので乖離しにくい。
    extern "C" {
        fn uniffi_imas_core_checksum_func_game_progress_apply_result() -> u16;
        fn uniffi_imas_core_checksum_func_game_progress_display_streak() -> u16;
        fn uniffi_imas_core_checksum_func_game_progress_did_clear_today() -> u16;
        fn uniffi_imas_core_checksum_func_game_progress_best_rate_percent() -> u16;
        fn uniffi_imas_core_checksum_func_game_progress_daily_sheet_gate() -> u16;
    }

    /// 上の一覧に並べたシンボルの数。`every_export_in_this_module_is_listed` の基準値。
    const DECLARED_CHECKSUMS: usize = 5;

    /// 一覧の各シンボルを実際に呼ぶ。呼び出せること自体がリンク成功の証明で、
    /// 戻り値は署名を変えれば変わる値なので固定しない。
    #[test]
    fn every_listed_export_has_an_ffi_checksum_symbol() {
        let checksums = unsafe {
            [
                uniffi_imas_core_checksum_func_game_progress_apply_result(),
                uniffi_imas_core_checksum_func_game_progress_display_streak(),
                uniffi_imas_core_checksum_func_game_progress_did_clear_today(),
                uniffi_imas_core_checksum_func_game_progress_best_rate_percent(),
                uniffi_imas_core_checksum_func_game_progress_daily_sheet_gate(),
            ]
        };
        assert_eq!(checksums.len(), DECLARED_CHECKSUMS);
    }

    /// 「エクスポートを足したのに上の一覧へ載せ忘れた」を落とす。
    ///
    /// リンクエラーが捕まえるのは「消えた・改名された」だけで、**増えた分は素通りする**。
    /// 未登録のまま増える事故がまさに今回の指摘なので、自ファイルのソースを読んで
    /// export 属性の個数を数え、宣言済みシンボル数と突き合わせる。
    #[test]
    fn every_export_in_this_module_is_listed() {
        // 属性名を 2 つに割って書くのは、この比較用のリテラル自身が
        // ソース中の出現として数えられてしまうのを防ぐため。
        let attribute = concat!("#[uniffi", "::export]");
        let exported = include_str!("game_progress.rs").matches(attribute).count();
        assert_eq!(
            exported, DECLARED_CHECKSUMS,
            "エクスポートを増減したら上の checksum 一覧と DECLARED_CHECKSUMS も直すこと。\
             一覧に無い関数は改名・削除してもこのテストが緑のまま通り、\
             Swift/Kotlin ラッパのリンク時まで発覚しない"
        );
    }

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

    #[test]
    fn best_rate_percent_delegates() {
        assert_eq!(game_progress_best_rate_percent(GameRecord::default()), None);
        let record = GameRecord { best_score: 5, best_out_of: 8, ..GameRecord::default() };
        assert_eq!(game_progress_best_rate_percent(record), Some(63));
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
