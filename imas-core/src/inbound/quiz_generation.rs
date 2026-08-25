//! 4 択クイズ (アイドル当て / ソロ曲) の FFI 面。ロジックは domain::quiz_generation。
//!
//! 呼び出しは「1 ユーザー操作 = 1 回」に揃える:
//! - 画面を開く / ブランドを切り替える → `*_pool_estimate`
//! - ゲーム開始 (もう一度も含む) → `*_session` で **1 セッション分の出題をまとめて**受け取る
//! - ヒント表示の更新 → `*_hint_state`、選択肢をタップ → `*_answer`
//! - 結果を見る → `*_session_result` で今回の点・率・グレードと記録用の分母 `out_of` を得て、
//!   その `points` / `out_of` を `game_progress_apply_result` に渡して保存する。
//!   「自己ベスト更新！」は `apply_result` の `is_new_best`、表示する自己ベスト率は
//!   `game_progress_best_rate_percent(update.record)` (`None` なら今回の率で代用)。
//!   **自己ベストの規則はコア内でも `game_progress` 側にしか無い**ので、
//!   `*_session_result` は自己ベストを引数に取らない (順序を間違えようがない)。
//!
//! 出題数 (`SESSION_LENGTH`) と 1 問の素点は規則なのでコア側の定数を使い、
//! 引数には出さない (両 OS が別々の値を持てないようにする)。
//! `seed` の調達 (実行時はシステム乱数、テストは固定値) はラッパの責務。

use crate::domain::prng::SplitMix64;
use crate::domain::quiz_generation::{
    self as quiz, IdolQuizFact, IdolQuizHintState, IdolQuizIdolRef, IdolQuizPoolEstimate,
    IdolQuizQuestion, QuizAnswerOutcome, QuizSessionResult, QuizTally,
    SongQuizOriginalArtistRow, SongQuizSingerRef, SongSingerQuizHintState,
    SongSingerQuizPoolEstimate, SongSingerQuizQuestion, IDOL_QUIZ_BASE_POINTS, SESSION_LENGTH,
    SONG_QUIZ_MAX_POINTS,
};

/// 1 セッションの出題数 (進捗ヘッダの「第 n / N 問」表示用)。
#[uniffi::export]
pub fn quiz_session_length() -> u32 {
    SESSION_LENGTH
}

/// 保存文字列 (カンマ区切り) → 出題ブランド id 列。空文字列 = 全ブランド対象。
#[uniffi::export]
pub fn quiz_brand_ids_decode(raw: String) -> Vec<String> {
    quiz::quiz_brand_ids_decode(&raw)
}

/// 出題ブランド id 列 → 保存文字列。
#[uniffi::export]
pub fn quiz_brand_ids_encode(brand_ids: Vec<String>) -> String {
    quiz::quiz_brand_ids_encode(&brand_ids)
}

// ---------------------------------------------------------------------------
// アイドル当てクイズ
// ---------------------------------------------------------------------------

/// 出題設定画面の候補数。ゲーム本体と同じ母集団条件で数えるので、
/// 「開始できるのに候補不足で始まる」ズレが起きない。
#[uniffi::export]
pub fn idol_quiz_pool_estimate(
    idols: Vec<IdolQuizIdolRef>,
    selected_brand_ids: Vec<String>,
) -> IdolQuizPoolEstimate {
    quiz::idol_quiz_pool_estimate(&idols, &selected_brand_ids)
}

/// 1 ゲーム分の出題をまとめて生成する (問題ごとに呼ばない)。
/// 返る index は引数 `idols` を指す。候補不足なら空。
#[uniffi::export]
pub fn idol_quiz_session(
    idols: Vec<IdolQuizIdolRef>,
    selected_brand_ids: Vec<String>,
    seed: u64,
) -> Vec<IdolQuizQuestion> {
    quiz::idol_quiz_session(
        &idols,
        &selected_brand_ids,
        SESSION_LENGTH,
        &mut SplitMix64(seed),
    )
}

/// 出題カードの開示範囲と、まだ開けるヒント一覧。
#[uniffi::export]
pub fn idol_quiz_hint_state(
    facts: Vec<IdolQuizFact>,
    opened_fact_indices: Vec<u32>,
    answered: bool,
) -> IdolQuizHintState {
    quiz::idol_quiz_hint_state(&facts, &opened_fact_indices, answered, IDOL_QUIZ_BASE_POINTS)
}

/// 選択肢をタップしたときの正誤判定・加点・集計。
#[uniffi::export]
pub fn idol_quiz_answer(
    facts: Vec<IdolQuizFact>,
    opened_fact_indices: Vec<u32>,
    picked_idol_id: String,
    answer_idol_id: String,
    before: QuizTally,
) -> QuizAnswerOutcome {
    quiz::idol_quiz_answer(
        &facts,
        &opened_fact_indices,
        &picked_idol_id,
        &answer_idol_id,
        &before,
        SESSION_LENGTH,
        IDOL_QUIZ_BASE_POINTS,
    )
}

/// セッション終了時のリザルト (今回ぶんだけ)。自己ベストは含まない
/// — 保存と更新判定は `game_progress_apply_result` の担当 (モジュールコメント参照)。
#[uniffi::export]
pub fn idol_quiz_session_result(tally: QuizTally) -> QuizSessionResult {
    quiz::quiz_session_result(&tally, IDOL_QUIZ_BASE_POINTS, SESSION_LENGTH)
}

// ---------------------------------------------------------------------------
// ソロ曲クイズ
// ---------------------------------------------------------------------------

/// 出題設定画面の候補数 (曲数 / 歌手数)。`rows` はソロ曲の原唱 (role='original') 全行。
#[uniffi::export]
pub fn song_singer_quiz_pool_estimate(
    rows: Vec<SongQuizOriginalArtistRow>,
    singers: Vec<SongQuizSingerRef>,
    selected_brand_ids: Vec<String>,
) -> SongSingerQuizPoolEstimate {
    quiz::song_singer_quiz_pool_estimate(&rows, &singers, &selected_brand_ids)
}

/// 1 ゲーム分の出題をまとめて生成する。返る index は引数 `singers` を指す。
#[uniffi::export]
pub fn song_singer_quiz_session(
    rows: Vec<SongQuizOriginalArtistRow>,
    singers: Vec<SongQuizSingerRef>,
    selected_brand_ids: Vec<String>,
    seed: u64,
) -> Vec<SongSingerQuizQuestion> {
    quiz::song_singer_quiz_session(
        &rows,
        &singers,
        &selected_brand_ids,
        SESSION_LENGTH,
        &mut SplitMix64(seed),
    )
}

/// ジャケット/プレビューの開示段階と、次に開けるヒント。
#[uniffi::export]
pub fn song_singer_quiz_hint_state(
    revealed: u32,
    has_preview: bool,
    answered: bool,
) -> SongSingerQuizHintState {
    quiz::song_singer_quiz_hint_state(revealed, has_preview, answered)
}

/// 選択肢をタップしたときの正誤判定・加点・集計。
#[uniffi::export]
pub fn song_singer_quiz_answer(
    revealed: u32,
    picked_idol_id: String,
    answer_idol_id: String,
    before: QuizTally,
) -> QuizAnswerOutcome {
    quiz::song_singer_quiz_answer(
        revealed,
        &picked_idol_id,
        &answer_idol_id,
        &before,
        SESSION_LENGTH,
    )
}

/// セッション終了時のリザルト (今回ぶんだけ。自己ベストは `game_progress_apply_result` 側)。
#[uniffi::export]
pub fn song_singer_quiz_session_result(tally: QuizTally) -> QuizSessionResult {
    quiz::quiz_session_result(&tally, SONG_QUIZ_MAX_POINTS, SESSION_LENGTH)
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::domain::game_progress::{GameRecord, GameStreakState};
    use crate::inbound::game_progress::{game_progress_apply_result, game_progress_best_rate_percent};

    const TODAY: &str = "2026-08-25";
    const YESTERDAY: &str = "2026-08-24";

    fn singer(id: &str, brand: &str) -> SongQuizSingerRef {
        SongQuizSingerRef { id: id.into(), brand_id: brand.into(), is_external: false }
    }

    fn row(song: &str, idol: &str) -> SongQuizOriginalArtistRow {
        SongQuizOriginalArtistRow { song_id: song.into(), idol_id: idol.into() }
    }

    /// リザルト画面が踏む 3 手 (リザルト → 保存 → 保存後の自己ベストを読む) を
    /// FFI 関数だけで組み、表示に出る 2 値を返す。
    fn finish(
        tally: QuizTally,
        before: GameRecord,
    ) -> (QuizSessionResult, bool, i32) {
        let result = idol_quiz_session_result(tally);
        let update = game_progress_apply_result(
            before,
            GameStreakState::default(),
            result.points as i32,
            result.out_of as i32,
            TODAY.to_string(),
            YESTERDAY.to_string(),
        );
        // 記録が無ければ今回の率で代用する (iOS `QuizResultView.bestRate` と同じ)。
        let best_rate = game_progress_best_rate_percent(update.record)
            .unwrap_or(result.rate_percent as i32);
        (result, update.is_new_best, best_rate)
    }

    /// 「保存 → 保存後の値でリザルトを組む」というラッパの自然な書き方で、
    /// 自己ベスト更新バッジと自己ベスト率が正しく出ること。
    ///
    /// 以前は `*_session_result` が記録前の自己ベストを引数に取り、更新判定も自前で
    /// 持っていたため、保存後の値を渡すと `is_new_best` が恒久的に false になった。
    /// FFI 面から自己ベスト引数を外し、判定は `game_progress_apply_result` だけが返す。
    #[test]
    fn result_and_progress_compose_without_an_ordering_trap() {
        let before = GameRecord { best_score: 50, best_out_of: 100, play_count: 3, ..GameRecord::default() };
        let tally = QuizTally { asked: 10, correct: 9, points: 90 };

        let (result, is_new_best, best_rate) = finish(tally.clone(), before.clone());
        assert_eq!(result.max_points, 100);
        assert_eq!(result.out_of, 100, "保存に渡す分母は解答数ぶん");
        assert_eq!(result.rate_percent, 90);
        assert!(is_new_best, "保存後にリザルトを組むと更新バッジが消えた");
        assert_eq!(best_rate, 90);

        // 保存後の記録で同じ点をもう一度出せば同率 = 更新ではない。
        let saved = game_progress_apply_result(
            before,
            GameStreakState::default(),
            90,
            100,
            TODAY.to_string(),
            YESTERDAY.to_string(),
        );
        let (_, again_new_best, again_rate) = finish(tally, saved.record);
        assert!(!again_new_best);
        assert_eq!(again_rate, 90);
    }

    /// 初プレイは更新バッジを出さず、自己ベスト表示は今回の率になる。
    #[test]
    fn first_play_shows_this_session_rate_without_the_badge() {
        let (result, is_new_best, best_rate) =
            finish(QuizTally { asked: 10, correct: 10, points: 100 }, GameRecord::default());
        assert_eq!(result.rate_percent, 100);
        assert!(!is_new_best);
        assert_eq!(best_rate, 100);
    }

    /// ソロ曲クイズの見積りとゲーム本体が同じ条件を見る。
    /// `master.sqlite` のブランド 961 (ソロ曲 4 曲 / 原唱歌手 2 名) は
    /// 「不足表示なのに 10 問始まり、全問 2 択」になっていた。
    #[test]
    fn song_setup_estimate_and_session_agree_on_the_pool() {
        let singers = vec![singer("a", "961"), singer("b", "961")];
        let rows = vec![row("s1", "a"), row("s2", "b"), row("s3", "a"), row("s4", "b")];

        let estimate = song_singer_quiz_pool_estimate(rows.clone(), singers.clone(), vec![]);
        assert_eq!(estimate.song_count, 4);
        assert_eq!(estimate.singer_count, 2);
        assert!(!estimate.is_sufficient);
        assert!(
            song_singer_quiz_session(rows, singers, vec![], 1).is_empty(),
            "設定画面が不足と言う母集団でゲームだけが始まった"
        );
    }

    /// 歌手が 4 人揃えば従来どおり 10 問・4 択で始まる (上の修正で塞ぎすぎていないこと)。
    #[test]
    fn song_session_still_starts_with_four_singers() {
        let singers: Vec<_> = (0..4).map(|i| singer(&format!("a{i}"), "cg")).collect();
        let rows: Vec<_> = (0..4).map(|i| row(&format!("s{i}"), &format!("a{i}"))).collect();

        assert!(song_singer_quiz_pool_estimate(rows.clone(), singers.clone(), vec![]).is_sufficient);
        let questions = song_singer_quiz_session(rows, singers, vec![], 1);
        assert_eq!(questions.len(), quiz_session_length() as usize);
        for q in questions {
            assert_eq!(q.choices.len(), 4);
            assert!(q.choices.contains(&q.answer));
        }
    }
}
