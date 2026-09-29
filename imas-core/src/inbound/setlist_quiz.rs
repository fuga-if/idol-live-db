//! セトリ当てクイズの FFI 面。ロジックは domain::setlist_quiz。
//!
//! | 画面の操作 | 呼ぶもの |
//! |---|---|
//! | 出題設定 (ブランドを選ぶ) | [`SnapshotStore::setlist_quiz_pool_estimate`] |
//! | 「はじめる」 | [`SnapshotStore::setlist_quiz_session`] (全問まとめて生成) |
//! | 出題 / ヒントを開く / 解答 | [`setlist_quiz_hint_state`] |
//! | 曲をタップ | [`setlist_quiz_answer`] |
//! | 結果画面 | [`setlist_quiz_session_result`] |

use crate::domain::prng::SplitMix64;
use crate::domain::quiz_generation::{
    quiz_session_result, QuizAnswerOutcome, QuizSessionResult, QuizTally, SESSION_LENGTH,
};
use crate::domain::setlist_quiz::{
    self as sq, SetlistQuizHintKind, SetlistQuizHintState, SetlistQuizPoolEstimate,
    SetlistQuizQuestion, SETLIST_QUIZ_BASE_POINTS,
};
use crate::inbound::snapshot_store::{SnapshotError, SnapshotStore};

#[uniffi::export]
impl SnapshotStore {
    /// 出題できる公演数 (設定画面の「はじめる」を塞ぐ判定)。`brand_ids` 空 = 全ブランド。
    pub fn setlist_quiz_pool_estimate(
        &self,
        brand_ids: Vec<String>,
    ) -> Result<SetlistQuizPoolEstimate, SnapshotError> {
        let snap = self.current()?;
        Ok(sq::pool_estimate(&snap, &brand_ids))
    }

    /// 1 ゲームぶん ([`SESSION_LENGTH`] 問) の出題をまとめて生成する。
    pub fn setlist_quiz_session(
        &self,
        brand_ids: Vec<String>,
        seed: u64,
    ) -> Result<Vec<SetlistQuizQuestion>, SnapshotError> {
        let snap = self.current()?;
        Ok(sq::make_session(&snap, &brand_ids, SESSION_LENGTH, &mut SplitMix64(seed)))
    }
}

/// いまの獲得点・見せる範囲・歌唱メンバーを見せるか・2 択で消す選択肢・まだ開けるヒント。
#[uniffi::export]
pub fn setlist_quiz_hint_state(
    question: SetlistQuizQuestion,
    opened: Vec<SetlistQuizHintKind>,
    answered: bool,
) -> SetlistQuizHintState {
    sq::hint_state(&question, &opened, answered)
}

/// 曲をタップしたときの正誤判定・加点・集計。
#[uniffi::export]
pub fn setlist_quiz_answer(
    question: SetlistQuizQuestion,
    opened: Vec<SetlistQuizHintKind>,
    picked_song_id: String,
    before: QuizTally,
) -> QuizAnswerOutcome {
    sq::answer(&question, &opened, &picked_song_id, &before, SESSION_LENGTH)
}

/// セッション終了時のリザルト。
#[uniffi::export]
pub fn setlist_quiz_session_result(tally: QuizTally) -> QuizSessionResult {
    quiz_session_result(&tally, SETLIST_QUIZ_BASE_POINTS, SESSION_LENGTH)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_store;

    #[test]
    fn store_generates_a_full_session() {
        let store = bundle_store();
        assert!(store.setlist_quiz_pool_estimate(vec![]).unwrap().is_sufficient);
        let qs = store.setlist_quiz_session(vec![], 1).unwrap();
        assert_eq!(qs.len() as u32, SESSION_LENGTH);
    }
}
