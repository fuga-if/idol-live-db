//! イントロクイズ選択肢生成の FFI 面。ロジックは domain::intro_quiz_choices。

use crate::domain::intro_quiz_choices::IntroQuizSongRef;

/// 出題曲それぞれの 4 択をまとめて生成する (1 ゲーム開始 = 1 呼び出し)。
///
/// 戻り値は `answers` と同順・同数。出題ごとにループで呼ぶ形 (要素ごと FFI) を
/// 避けるため、出題全件と pool の (id, title) 射影を一度に受ける (FFI 境界の規約)。
/// `seed` の調達 (実行時はシステム乱数、テストでは固定値) はラッパが担う。
#[uniffi::export]
pub fn intro_quiz_choices_batch(
    answers: Vec<IntroQuizSongRef>,
    pool: Vec<IntroQuizSongRef>,
    wrong_count: u32,
    seed: u64,
) -> Vec<Vec<String>> {
    let mut rng = crate::domain::prng::SplitMix64(seed);
    crate::domain::intro_quiz_choices::make_choices_batch(&answers, &pool, wrong_count, &mut rng)
}
