//! イントロドンの 1 ゲームの規則: 始められるか・何問出すか・点とコンボ・自己ベスト。
//!
//! 両 OS に写経されていた (iOS `IntroGameSession` / `IntroPartySession`、Android
//! `IntroDonGameScreen` / `IntroDonPartyScreen` / `IntroDonBestStore`)。
//! 自己ベストの**保存先とキー** (iOS の UserDefaults / Android の SharedPreferences) は
//! 端末に残る識別子なので各 OS のまま。ここは「更新するか」だけを決める。
//! 出題の候補 (`intro_quiz_choices`) と出題可否 (`is_quiz_playable`) は別のモジュール。

/// 4 択なので、候補の曲が 4 曲に満たなければ始めない。
pub const INTRO_MIN_POOL_SIZE: u32 = 4;

/// ゲームの形。何問出すかと、答えた後の進み方が変わる。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum IntroSessionKind {
    /// 決めた問題数を出す (イントロ・超イントロ・パーティー)。
    Standard,
    /// 制限時間内に何問答えられるか。候補を全部並べておく。
    Rush,
    /// 全曲チャレンジ。候補を全部出してタイムを競う。
    AllSongs,
}

/// 何問出すか。候補が 4 曲に満たなければ `None` (始めない)。
/// ラッシュと全曲チャレンジは候補を全部、それ以外は決めた問題数 (候補より多ければ候補の数)。
pub fn question_count(kind: IntroSessionKind, pool_size: u32, requested: u32) -> Option<u32> {
    if pool_size < INTRO_MIN_POOL_SIZE {
        return None;
    }
    Some(match kind {
        IntroSessionKind::Rush | IntroSessionKind::AllSongs => pool_size,
        IntroSessionKind::Standard => requested.min(pool_size),
    })
}

/// 点とコンボ。
#[derive(uniffi::Record, Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct IntroScore {
    pub score: u32,
    pub combo: u32,
    pub best_combo: u32,
}

/// 1 問答えた (または飛ばした) 後の点とコンボ。正解なら点とコンボが 1 つ増え、
/// 不正解・飛ばしはコンボが 0 に戻る (点はそのまま)。
pub fn score_after_answer(current: IntroScore, correct: bool) -> IntroScore {
    if correct {
        let combo = current.combo + 1;
        IntroScore { score: current.score + 1, combo, best_combo: current.best_combo.max(combo) }
    } else {
        IntroScore { combo: 0, ..current }
    }
}

/// 自己ベストの点を更新するか (前の記録より多いときだけ。同点は更新しない)。
pub fn is_new_best_score(score: u32, previous_best: u32) -> bool {
    score > previous_best
}

/// 全曲チャレンジの自己ベストのタイムを更新するか。記録が無い (`0`) か、前より速いとき。
/// 単位は前の記録と揃っていれば何でもよい (iOS は秒、Android はミリ秒)。
pub fn is_new_best_time(elapsed: f64, previous_best: f64) -> bool {
    elapsed > 0.0 && (previous_best == 0.0 || elapsed < previous_best)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn needs_four_songs_and_counts_by_kind() {
        assert_eq!(question_count(IntroSessionKind::Standard, 3, 10), None);
        assert_eq!(question_count(IntroSessionKind::Standard, 4, 10), Some(4));
        assert_eq!(question_count(IntroSessionKind::Standard, 50, 10), Some(10));
        assert_eq!(question_count(IntroSessionKind::Rush, 50, 10), Some(50));
        assert_eq!(question_count(IntroSessionKind::AllSongs, 300, 10), Some(300));
    }

    #[test]
    fn correct_answers_build_a_combo_and_misses_reset_it() {
        let mut s = IntroScore::default();
        for correct in [true, true, false, true] {
            s = score_after_answer(s, correct);
        }
        assert_eq!(s, IntroScore { score: 3, combo: 1, best_combo: 2 });
    }

    #[test]
    fn best_score_needs_a_strictly_higher_score() {
        assert!(is_new_best_score(5, 4));
        assert!(!is_new_best_score(4, 4), "同点は更新しない");
        assert!(!is_new_best_score(0, 0), "0 点は記録にしない");
    }

    #[test]
    fn best_time_is_the_fastest_non_zero_time() {
        assert!(is_new_best_time(90.5, 0.0), "初めての記録");
        assert!(is_new_best_time(80.0, 90.5));
        assert!(!is_new_best_time(95.0, 90.5));
        assert!(!is_new_best_time(0.0, 90.5), "0 は記録にしない");
    }
}
