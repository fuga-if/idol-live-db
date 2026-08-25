//! ゲームの進捗記録 (自己ベスト・プレイ回数・デイリー連続達成) の更新規則。純粋ロジック。
//!
//! 原本は iOS `Views/Games/GameProgressStore.swift` と Android
//! `data/games/GameProgressStore.kt` (file-for-file の写経になっていた 2 実装)。
//! 保存の実体 (UserDefaults / SharedPreferences) は各 OS に残し、ここは
//! **「今の保存値 + 今回の結果 → 新しい保存値」** だけを引き受ける。
//! ストアは「読む → [`apply_result`] → 書く」の 3 行になり、更新規則は 1 か所になる。
//!
//! ## なぜ日付を epoch 秒ではなく「日キー文字列」で受け取るか
//!
//! 連続達成日数の単位は **「そのユーザーの 1 日」**、つまり端末ローカル日。
//! 公演日との比較に使う [`crate::domain::jst_day`] (JST 固定) とは意味が違うので統合しない
//! (原本 `GameProgressStore` のコメントにも明記されている)。
//!
//! さらに端末ローカル日は **端末の暦法設定** (和暦・仏暦 等) に従った表記のまま
//! 保存されており、chrono はグレゴリオ暦固定なので epoch 秒からは再構成できない。
//! 「前日」も夏時間・era 跨ぎ・暦ごとのうるう規則があってカレンダー演算が要る。
//! そのため日付の解決は [`crate::domain::daily_pick`] と同じ流儀で
//! **各プラットフォームの薄いラッパの責務**とし、ここは解決済みの
//! `today_key` / `yesterday_key` を受け取って**文字列一致で比較するだけ**にする
//! (iOS: `DailyPick.dayKey()` / `DailyPick.previousDayKey()`)。
//!
//! ## なぜ「保存する値」と「バッジに出す判定」を 1 回で返すか
//!
//! 原本の View は結果画面で `record(for:)` → 自己ベスト更新の判定 → `recordResult(...)`
//! の順に 3 手を踏んでいた。判定は **best が上書きされる前の値**で行う必要があり
//! (順序を崩すと常に「更新なし」になる)、この順序依存を各 OS のコードに置いたままにすると
//! 片方だけ壊れても気づけない。1 呼び出しにまとめて順序ごと固定する
//! (FFI 規約「1 ユーザー操作 = 1 呼び出し」にも合う)。

/// 1 ゲーム分の記録。端末に保存されている値そのもの (キーは `game_records_v1`)。
///
/// 壊れた保存値・想定外の負値が来てもパニックしないよう、比較と加算は飽和・
/// ゼロ除算回避で組む (FFI 越しに来る値を信用しない)。
#[derive(uniffi::Record, Clone, Debug, Default, PartialEq, Eq)]
pub struct GameRecord {
    /// 直近のスコア (正解ポイント)。
    pub last_score: i32,
    /// 直近の満点。
    pub last_out_of: i32,
    /// 自己ベスト時のスコア。
    pub best_score: i32,
    /// 自己ベスト時の満点。`0` は「まだ記録なし」。
    pub best_out_of: i32,
    /// 通算プレイ回数。
    pub play_count: i32,
}

impl GameRecord {
    /// 1 度でも遊んだか (ハブのカードが「未プレイ」を出すかの判定)。
    pub fn has_played(&self) -> bool {
        self.play_count > 0
    }

    /// 自己ベストの正答率 (0–100 の四捨五入)。まだ記録が無ければ `None`。
    ///
    /// `None` の扱いは呼び出す画面で違う (ハブは「—」、結果画面は今回の率で代用) ので、
    /// ここでは文言に落とさず「記録が無い」ことだけを返す。
    /// 端数は原本 Swift の `.rounded()` と同じ「0.5 は絶対値の大きい側へ」
    /// (Rust の `f64::round` と一致。Kotlin 側の `Math.round` も非負域では同じ)。
    pub fn best_rate_percent(&self) -> Option<i32> {
        if self.best_out_of <= 0 {
            return None;
        }
        let pct = (f64::from(self.best_score) / f64::from(self.best_out_of) * 100.0).round();
        Some(pct as i32)
    }

    /// 自己ベスト比較に使う正答率。まだ記録が無ければ `-1`。
    ///
    /// 生スコアではなく率で比べるのは、出題数が違うセッション同士を公平に扱うため
    /// (5 問で 5 点より 10 問で 6 点の方が偉いわけではない)。
    /// 記録なしを `-1` にしているので、初回は 0 点 (率 0) でも必ずベストとして残る
    /// = `best_out_of` が 0 のまま据え置かれてハブが「—」を出し続けることがない。
    fn best_rate(&self) -> f64 {
        if self.best_out_of > 0 {
            f64::from(self.best_score) / f64::from(self.best_out_of)
        } else {
            -1.0
        }
    }
}

/// デイリーチャレンジ (1 日 1 回どれかのゲームを遊べば達成) の連続記録。
/// 端末に保存されている値そのもの (キーは `game_streak_v1`)。
#[derive(uniffi::Record, Clone, Debug, Default, PartialEq, Eq)]
pub struct GameStreakState {
    /// 連続達成日数。
    pub streak: i32,
    /// 通算達成日数。
    pub total_days: i32,
    /// 最後に達成した端末ローカル日 (`"yyyy-MM-dd"`)。未達成は `None`。
    pub last_cleared_day: Option<String>,
}

impl GameStreakState {
    /// 今日ぶんのデイリーチャレンジを達成済みか。
    pub fn did_clear_today(&self, today_key: &str) -> bool {
        self.last_cleared_day.as_deref() == Some(today_key)
    }

    /// 表示用の連続日数。
    ///
    /// 保存値の `streak` は「最後に達成した日までの連続数」なので、そのまま出すと
    /// 何日も放置した後でも古い数字が残る。今日・昨日までの達成なら継続中とみなし、
    /// それより古ければ 0 を出す (今日まだ遊んでいなくても昨日ぶんは継続扱い)。
    pub fn display_streak(&self, today_key: &str, yesterday_key: &str) -> i32 {
        match self.last_cleared_day.as_deref() {
            Some(last) if last == today_key || last == yesterday_key => self.streak,
            _ => 0,
        }
    }

    /// プレイ完了を当日の達成として登録した後の状態。
    ///
    /// - 今日ぶんが登録済みなら何もしない (1 日に何回遊んでも 1 日は 1 日)。
    /// - 昨日達成していれば +1、そうでなければ 1 から数え直す
    ///   (「途切れたら 0」ではない。今日ぶんは達成しているので 1)。
    fn registering_daily_clear(&self, today_key: &str, yesterday_key: &str) -> Self {
        if self.did_clear_today(today_key) {
            return self.clone();
        }
        let continued = self.last_cleared_day.as_deref() == Some(yesterday_key);
        Self {
            // 壊れた保存値で加算があふれてもパニックさせない (i32 の上限で頭打ち)。
            streak: if continued { self.streak.saturating_add(1) } else { 1 },
            total_days: self.total_days.saturating_add(1),
            last_cleared_day: Some(today_key.to_string()),
        }
    }
}

/// [`apply_result`] の結果。保存すべき新しい値と、結果画面に出す判定をまとめて返す。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct GameProgressUpdate {
    /// 保存する新しいゲーム記録。
    pub record: GameRecord,
    /// 保存する新しい連続記録。
    pub streak: GameStreakState,
    /// 今回が自己ベスト更新だったか (結果画面の「自己ベスト更新！」バッジ)。
    /// バッジを出さないゲーム (カラーマッチ等) は無視してよい。
    pub is_new_best: bool,
    /// 記録として成立したか。`false` なら `record` / `streak` は入力そのまま
    /// (書き戻しても値は変わらないが、保存自体を省いてよい)。
    pub did_record: bool,
}

/// 1 セッション分の結果を記録した後の保存値と、自己ベスト更新の判定を返す。
///
/// `score` / `out_of` は「獲得ポイント / 満点」。
/// `today_key` / `yesterday_key` は端末ローカル日 (モジュールコメント参照)。
///
/// - `out_of <= 0` (出題 0 問で終わったセッション) は**記録しない**。
///   プレイ回数と連続記録だけが伸びるのを防ぐため、原本と同じく丸ごと無視する
///   (候補不足で 1 問も出せなかった場合がこれに当たる)。
/// - `is_new_best` だけは原本の View と同じく `out_of <= 0` でも算出する
///   (View 側は `recordResult` の早期 return と無関係にバッジ判定していた)。
pub fn apply_result(
    before: &GameRecord,
    streak: &GameStreakState,
    score: i32,
    out_of: i32,
    today_key: &str,
    yesterday_key: &str,
) -> GameProgressUpdate {
    // 自己ベスト更新の判定は **best を上書きする前** に済ませる (順序が本質)。
    // 初回プレイ (`has_played == false`) はバッジを出さない: 比較相手が無い回に
    // 「更新！」と出しても意味がないため、原本の View も同じ条件で抑えている。
    let new_rate = if out_of > 0 {
        f64::from(score) / f64::from(out_of)
    } else {
        0.0
    };
    let is_new_best = before.has_played() && new_rate > before.best_rate();

    if out_of <= 0 {
        return GameProgressUpdate {
            record: before.clone(),
            streak: streak.clone(),
            is_new_best,
            did_record: false,
        };
    }

    // 自己ベストは率で比較する (`best_rate` のコメント参照)。同率は更新しない
    // = 先に出した記録を残す。
    let beat_best = new_rate > before.best_rate();
    let record = GameRecord {
        last_score: score,
        last_out_of: out_of,
        best_score: if beat_best { score } else { before.best_score },
        best_out_of: if beat_best { out_of } else { before.best_out_of },
        play_count: before.play_count.saturating_add(1),
    };

    GameProgressUpdate {
        record,
        streak: streak.registering_daily_clear(today_key, yesterday_key),
        is_new_best,
        did_record: true,
    }
}

/// 「1 日 1 回だけ出す」日替わりシート (起動時の『今日の1曲』) のゲート結果。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct DailySheetGate {
    /// 今回の起動で出すか。
    pub should_show: bool,
    /// 保存し直す「最後に出した日」。
    pub last_shown_day: String,
}

/// 日替わりシートを今日まだ出していなければ「出す」と答え、同時に保存すべき日を返す。
///
/// 出す/出さないを跨いで戻り値の `last_shown_day` は常に今日になる
/// (出さない = 既に今日ぶんを出した後、なので今日で正しい)。呼び出し側は
/// 「出すときだけ書く」でも「毎回書く」でも同じ状態になり、書き忘れで
/// 同じ日に何度も出る事故を防げる。
///
/// リセットの単位は連続記録と同じ端末ローカル日 (モジュールコメント参照)。
/// 日付キーの生成が同じなので、深夜 0 時をまたいだ瞬間に両方が同時に切り替わる。
pub fn daily_sheet_gate(last_shown_day: Option<&str>, today_key: &str) -> DailySheetGate {
    DailySheetGate {
        should_show: last_shown_day != Some(today_key),
        last_shown_day: today_key.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TODAY: &str = "2026-08-25";
    const YESTERDAY: &str = "2026-08-24";
    const LAST_WEEK: &str = "2026-08-18";

    fn cleared(day: &str, streak: i32, total: i32) -> GameStreakState {
        GameStreakState {
            streak,
            total_days: total,
            last_cleared_day: Some(day.to_string()),
        }
    }

    fn play(before: &GameRecord, streak: &GameStreakState, score: i32, out_of: i32) -> GameProgressUpdate {
        apply_result(before, streak, score, out_of, TODAY, YESTERDAY)
    }

    // MARK: - 記録の更新

    /// 初回プレイ: 直近も自己ベストも今回の結果になり、回数が 1 になる。
    /// バッジは出さない (比較相手が無い)。
    #[test]
    fn first_play_records_everything_but_shows_no_badge() {
        let got = play(&GameRecord::default(), &GameStreakState::default(), 3, 5);
        assert_eq!(
            got.record,
            GameRecord { last_score: 3, last_out_of: 5, best_score: 3, best_out_of: 5, play_count: 1 }
        );
        assert!(!got.is_new_best, "初回プレイで自己ベスト更新バッジが出ている");
        assert!(got.did_record);
    }

    /// 全問不正解でも初回は自己ベストとして残る (`best_rate` の `-1` センチネル)。
    /// ここが 0 スタートだと `best_out_of` が 0 のままハブが「—」を出し続ける。
    #[test]
    fn first_play_with_zero_score_still_sets_best() {
        let got = play(&GameRecord::default(), &GameStreakState::default(), 0, 5);
        assert_eq!(got.record.best_score, 0);
        assert_eq!(got.record.best_out_of, 5);
        assert_eq!(got.record.best_rate_percent(), Some(0));
    }

    /// 自己ベストは生スコアではなく率で比べる: 8/10 (0.8) より 5/5 (1.0) が上。
    #[test]
    fn best_is_compared_by_rate_not_raw_score() {
        let before = GameRecord { last_score: 8, last_out_of: 10, best_score: 8, best_out_of: 10, play_count: 1 };
        let got = play(&before, &GameStreakState::default(), 5, 5);
        assert_eq!((got.record.best_score, got.record.best_out_of), (5, 5));
        assert!(got.is_new_best);
    }

    /// 逆向きも同じ規則: 5/5 (1.0) の後に 9/10 (0.9) を出しても更新しない
    /// (生スコアは 9 > 5 だが率は下)。
    #[test]
    fn higher_raw_score_with_lower_rate_does_not_update_best() {
        let before = GameRecord { last_score: 5, last_out_of: 5, best_score: 5, best_out_of: 5, play_count: 1 };
        let got = play(&before, &GameStreakState::default(), 9, 10);
        assert_eq!((got.record.best_score, got.record.best_out_of), (5, 5));
        assert!(!got.is_new_best);
        // 直近と回数は更新される。
        assert_eq!((got.record.last_score, got.record.last_out_of, got.record.play_count), (9, 10, 2));
    }

    /// 同率は更新しない (先に出した記録を残す)。4/5 と 8/10 はどちらも 0.8。
    #[test]
    fn tie_rate_keeps_the_earlier_best() {
        let before = GameRecord { last_score: 4, last_out_of: 5, best_score: 4, best_out_of: 5, play_count: 1 };
        let got = play(&before, &GameStreakState::default(), 8, 10);
        assert_eq!((got.record.best_score, got.record.best_out_of), (4, 5));
        assert!(!got.is_new_best);
    }

    /// 全問正解を 2 回続けても 2 回目はバッジを出さない (1.0 > 1.0 は偽)。
    #[test]
    fn repeating_a_perfect_score_shows_no_badge() {
        let before = GameRecord { last_score: 5, last_out_of: 5, best_score: 5, best_out_of: 5, play_count: 1 };
        assert!(!play(&before, &GameStreakState::default(), 5, 5).is_new_best);
    }

    /// バッジ判定は **best を上書きする前** の値で行う。
    /// 返ってきた record の best は今回の結果に変わっているが、判定は旧 best 基準。
    #[test]
    fn badge_is_judged_against_the_record_before_the_update() {
        let before = GameRecord { last_score: 1, last_out_of: 5, best_score: 1, best_out_of: 5, play_count: 1 };
        let got = play(&before, &GameStreakState::default(), 4, 5);
        assert!(got.is_new_best, "旧 best (0.2) を超えたのにバッジが出ていない");
        assert_eq!((got.record.best_score, got.record.best_out_of), (4, 5));
    }

    // MARK: - 出題 0 問 (空プール・候補不足)

    /// 1 問も出せなかったセッションは丸ごと無視する。
    /// プレイ回数も連続記録も伸びない (遊んでいないので当然)。
    #[test]
    fn zero_out_of_records_nothing() {
        let before = GameRecord { last_score: 4, last_out_of: 5, best_score: 4, best_out_of: 5, play_count: 3 };
        let streak = cleared(YESTERDAY, 2, 9);
        let got = play(&before, &streak, 0, 0);
        assert!(!got.did_record);
        assert_eq!(got.record, before);
        assert_eq!(got.streak, streak);
        assert!(!got.is_new_best);
    }

    /// 負の満点 (壊れた入力) も同じく無視する。ゼロ除算もパニックもしない。
    #[test]
    fn negative_out_of_records_nothing() {
        let got = play(&GameRecord::default(), &GameStreakState::default(), 3, -5);
        assert!(!got.did_record);
        assert_eq!(got.record, GameRecord::default());
    }

    /// 壊れた保存値 (プレイ済みなのに best が空) でも原本の式どおりに答える。
    /// 挙動を「直す」のではなく、出荷済みの式をそのまま固定するためのテスト。
    #[test]
    fn degenerate_record_follows_the_shipped_formula() {
        let broken = GameRecord { last_score: 0, last_out_of: 0, best_score: 0, best_out_of: 0, play_count: 1 };
        // best_rate は -1 なので、0 点 (率 0) でも「更新」と判定される。
        let got = play(&broken, &GameStreakState::default(), 0, 0);
        assert!(got.is_new_best);
        assert!(!got.did_record, "出題 0 問なので保存はしない");
    }

    // MARK: - 連続達成日数

    /// 初達成は 1 日目から。
    #[test]
    fn streak_starts_at_one() {
        let got = play(&GameRecord::default(), &GameStreakState::default(), 1, 1);
        assert_eq!(got.streak, cleared(TODAY, 1, 1));
    }

    /// 昨日達成していれば +1。
    #[test]
    fn streak_continues_from_yesterday() {
        let got = play(&GameRecord::default(), &cleared(YESTERDAY, 4, 12), 1, 1);
        assert_eq!(got.streak, cleared(TODAY, 5, 13));
    }

    /// 間が空いたら 0 ではなく 1 から数え直す (今日ぶんは達成しているため)。
    /// 通算日数は途切れても増え続ける。
    #[test]
    fn streak_restarts_at_one_after_a_gap() {
        let got = play(&GameRecord::default(), &cleared(LAST_WEEK, 4, 12), 1, 1);
        assert_eq!(got.streak, cleared(TODAY, 1, 13));
    }

    /// 同じ日に何回遊んでも 1 日は 1 日 (連続日数も通算日数も動かない)。
    #[test]
    fn streak_counts_once_per_day() {
        let already = cleared(TODAY, 5, 13);
        let got = play(&GameRecord::default(), &already, 1, 1);
        assert_eq!(got.streak, already);
        // 記録そのものは 2 回目も更新される。
        assert!(got.did_record);
        assert_eq!(got.record.play_count, 1);
    }

    /// ラッパが前日算出に失敗して today と同じ日を渡してきても壊れない
    /// (iOS `previousDayKey` はカレンダー演算に失敗すると当日へフォールバックする)。
    /// 「昨日達成」判定が当日判定と重なるだけで、先の 1 日 1 回ガードが効く。
    #[test]
    fn previous_day_fallback_to_today_is_safe() {
        let got = apply_result(&GameRecord::default(), &cleared(LAST_WEEK, 4, 12), 1, 1, TODAY, TODAY);
        assert_eq!(got.streak, cleared(TODAY, 1, 13));

        let already = cleared(TODAY, 5, 13);
        let same_day = apply_result(&GameRecord::default(), &already, 1, 1, TODAY, TODAY);
        assert_eq!(same_day.streak, already);
    }

    // MARK: - 表示用の連続日数 / 今日の達成

    #[test]
    fn display_streak_shows_today_and_yesterday_as_alive() {
        assert_eq!(cleared(TODAY, 7, 20).display_streak(TODAY, YESTERDAY), 7);
        assert_eq!(cleared(YESTERDAY, 7, 20).display_streak(TODAY, YESTERDAY), 7);
    }

    /// 一昨日以前なら (保存値が 7 でも) 途切れているので 0。
    #[test]
    fn display_streak_is_zero_after_a_missed_day() {
        assert_eq!(cleared(LAST_WEEK, 7, 20).display_streak(TODAY, YESTERDAY), 0);
    }

    #[test]
    fn display_streak_is_zero_when_never_cleared() {
        assert_eq!(GameStreakState::default().display_streak(TODAY, YESTERDAY), 0);
    }

    #[test]
    fn did_clear_today_matches_only_todays_key() {
        assert!(cleared(TODAY, 1, 1).did_clear_today(TODAY));
        assert!(!cleared(YESTERDAY, 1, 1).did_clear_today(TODAY));
        assert!(!GameStreakState::default().did_clear_today(TODAY));
    }

    // MARK: - 自己ベストの率表示

    /// 端数は四捨五入 (原本 Swift の `.rounded()` と同じ)。
    #[test]
    fn best_rate_percent_rounds_to_nearest() {
        let pct = |s, o| GameRecord { best_score: s, best_out_of: o, ..GameRecord::default() }.best_rate_percent();
        assert_eq!(pct(1, 3), Some(33)); // 33.33…
        assert_eq!(pct(2, 3), Some(67)); // 66.66…
        assert_eq!(pct(5, 8), Some(63)); // 62.5 → 上へ
        assert_eq!(pct(3, 8), Some(38)); // 37.5 → 上へ
        assert_eq!(pct(5, 5), Some(100));
        assert_eq!(pct(0, 5), Some(0));
    }

    /// 記録が無いことは文言に落とさず None で返す (画面ごとに代替表示が違う)。
    #[test]
    fn best_rate_percent_is_none_without_a_record() {
        assert_eq!(GameRecord::default().best_rate_percent(), None);
        // 壊れた保存値 (負の満点) でもゼロ除算しない。
        let broken = GameRecord { best_score: 3, best_out_of: -1, ..GameRecord::default() };
        assert_eq!(broken.best_rate_percent(), None);
    }

    #[test]
    fn has_played_follows_play_count() {
        assert!(!GameRecord::default().has_played());
        assert!(GameRecord { play_count: 1, ..GameRecord::default() }.has_played());
    }

    // MARK: - 日替わりシートのゲート

    #[test]
    fn daily_sheet_shows_on_first_launch_ever() {
        assert_eq!(
            daily_sheet_gate(None, TODAY),
            DailySheetGate { should_show: true, last_shown_day: TODAY.to_string() }
        );
    }

    #[test]
    fn daily_sheet_shows_again_the_next_day() {
        assert_eq!(
            daily_sheet_gate(Some(YESTERDAY), TODAY),
            DailySheetGate { should_show: true, last_shown_day: TODAY.to_string() }
        );
    }

    /// 同じ日の 2 回目の起動では出さない。保存値は今日のままで変わらない。
    #[test]
    fn daily_sheet_does_not_repeat_within_a_day() {
        assert_eq!(
            daily_sheet_gate(Some(TODAY), TODAY),
            DailySheetGate { should_show: false, last_shown_day: TODAY.to_string() }
        );
    }

    /// 端末の日付を戻した場合も「今日ぶんは未表示」として出す (未来日の保存値 != 今日)。
    #[test]
    fn daily_sheet_shows_when_saved_day_is_in_the_future() {
        assert!(daily_sheet_gate(Some("2099-01-01"), TODAY).should_show);
    }
}
