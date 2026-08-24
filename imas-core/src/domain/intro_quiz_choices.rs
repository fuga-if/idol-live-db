//! イントロクイズの 4 択を組み立てる規則。
//!
//! ## なぜ 1 か所に置くか
//!
//! 1 人用 (iOS `IntroGameSession` / Android `IntroDonGameScreen`) と対戦
//! (iOS `IntroPartySession` / Android `IntroDonPartyScreen`) が同じ選択肢生成を
//! 別々に持っていて、実装が 1 文字違わずコピーされていた。片方だけ直すと
//! 一方のモードだけ壊れた選択肢が出る。さらに iOS と Android でも同文のコピーが
//! あったので、Rust に一本化して両 OS で共有する。
//!
//! ## なぜタイトルでユニーク化するか
//!
//! 同名異曲 (別バージョン・リミックス等) が pool に複数あると、不正解として
//! 正解と同じタイトルが並びうる。そうなると「正しい答えを選んだのに不正解」に
//! なるので、**タイトル**で重複を落とす (曲 ID ではなく)。
//!
//! ## なぜ NFC 正規化して比較するか
//!
//! 原本 Swift の `Set<String>` / `==` は Unicode 正準等価 (NFC の「ガ」と
//! NFD の「カ + ゛」を同一視) で比較する。Rust の `str` 比較はバイト同値なので、
//! そのまま移植すると表現違いの同名タイトルを別物と数え、「見た目が同じ選択肢が
//! 2 つ並ぶ」(コミット 340823b が直したバグ) がデータ次第で再発する。出荷 DB には
//! 現に NFD のタイトルが混在するため、比較の鍵だけ NFC に揃える (表示は原文のまま)。
//!
//! ## FFI 境界の形
//!
//! エンティティ全体は渡さず、必要な (id, title) だけの射影 [`IntroQuizSongRef`] を受ける。
//! 出題ごとにループで FFI を呼ぶ形を避けるため、1 ゲームぶんの出題をまとめて生成する
//! バッチ ([`make_choices_batch`]) を一次 API とする。乱数はシード注入の SplitMix64 で、
//! シードの調達 (実行時はシステム乱数) は各プラットフォームの薄いラッパが担う。

use std::borrow::Cow;
use std::collections::HashSet;

use unicode_normalization::{is_nfc_quick, IsNormalized, UnicodeNormalization};

use crate::domain::prng::SplitMix64;

/// 選択肢生成に必要な曲の射影。エンティティ全体を FFI に通さないための最小形。
#[derive(uniffi::Record, Clone, Debug)]
pub struct IntroQuizSongRef {
    pub id: String,
    /// 表示タイトル。選択肢の実体であり、重複排除の鍵でもある。
    pub title: String,
}

/// Swift の String == (正準等価) に合わせた比較キー。NFC 済みならそのまま借用し、
/// NFD 等の未正規化表現だけ NFC へ正規化して所有する (クイックチェックで確定できない
/// `Maybe` も正規化側に倒す)。
fn nfc_key(s: &str) -> Cow<'_, str> {
    match is_nfc_quick(s.chars()) {
        IsNormalized::Yes => Cow::Borrowed(s),
        IsNormalized::No | IsNormalized::Maybe => Cow::Owned(s.nfc().collect()),
    }
}

/// 不正解の候補 (pool 内 index)。正解自身・正解と同じタイトル・既出タイトルを除く。
/// 比較はすべて正準等価 (NFC 正規化キー、モジュールコメント参照)。
/// 順序は `pool` のまま (シャッフルしない) ので、規則だけを単体で検証できる。
pub fn wrong_candidate_indices(answer: &IntroQuizSongRef, pool: &[IntroQuizSongRef]) -> Vec<u32> {
    let answer_id = nfc_key(&answer.id);
    let mut seen_titles: HashSet<Cow<'_, str>> = HashSet::from([nfc_key(&answer.title)]);
    pool.iter()
        .enumerate()
        // 正解そのもの (同じ id) はタイトルを「既出」に数えず素通しで除く (原本 Swift の guard と同順)。
        .filter(|(_, candidate)| {
            nfc_key(&candidate.id) != answer_id && seen_titles.insert(nfc_key(&candidate.title))
        })
        .map(|(i, _)| i as u32)
        .collect()
}

/// 1 問分の選択肢。正解 1 つ + 不正解 `wrong_count` 個を混ぜて返す。
///
/// 候補が足りなければその分だけ少ない選択肢になる (正解は必ず含む)。
pub fn make_choices(
    answer: &IntroQuizSongRef,
    pool: &[IntroQuizSongRef],
    wrong_count: u32,
    rng: &mut SplitMix64,
) -> Vec<String> {
    // 原本 Swift と同じ 2 段シャッフル:
    // 1. 候補全体をシャッフルして先頭 wrong_count 件を採る (どの不正解が出るかの抽選)
    // 2. 正解を足してもう一度シャッフル (正解の位置が固定されないように)
    let mut wrongs = wrong_candidate_indices(answer, pool);
    rng.shuffle(&mut wrongs);
    wrongs.truncate(wrong_count as usize);
    let mut choices: Vec<String> = wrongs
        .into_iter()
        .map(|i| pool[i as usize].title.clone())
        .collect();
    choices.push(answer.title.clone());
    rng.shuffle(&mut choices);
    choices
}

/// 1 ゲームぶんの出題全件の選択肢をまとめて生成する (戻り値は `answers` と同順・同数)。
///
/// 呼び出し側 (ゲーム開始処理) は出題曲を選んだあと、この 1 回で全問の 4 択を得る。
/// 出題ごとに `make_choices` をループで呼ぶと FFI 呼び出しが出題数 × pool 射影ぶんに
/// 膨らむので、境界を跨ぐのはこのバッチだけにする。
pub fn make_choices_batch(
    answers: &[IntroQuizSongRef],
    pool: &[IntroQuizSongRef],
    wrong_count: u32,
    rng: &mut SplitMix64,
) -> Vec<Vec<String>> {
    answers
        .iter()
        .map(|answer| make_choices(answer, pool, wrong_count, rng))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn song(id: &str, title: &str) -> IntroQuizSongRef {
        IntroQuizSongRef { id: id.into(), title: title.into() }
    }

    /// pool 内 index 列をタイトル列に引き直す (テストの読みやすさ用)。
    fn titles_at(pool: &[IntroQuizSongRef], indices: &[u32]) -> Vec<String> {
        indices.iter().map(|&i| pool[i as usize].title.clone()).collect()
    }

    // --- wrong_candidate_indices (規則そのもの) ---

    /// 正解と同じタイトルの別バージョンは不正解候補にしない。
    /// ここが壊れると「正解を選んだのに不正解」になる。
    #[test]
    fn excludes_same_title_different_song() {
        let answer = song("s1", "READY!!");
        let pool = [
            answer.clone(),
            song("s2", "READY!! (M@STER VERSION)"),
            song("s3", "READY!!"),
        ];
        let titles = titles_at(&pool, &wrong_candidate_indices(&answer, &pool));
        assert!(!titles.contains(&"READY!!".to_string()));
        assert_eq!(titles, vec!["READY!! (M@STER VERSION)"]);
    }

    /// 正解そのもの (同じ id) は候補から外す。
    #[test]
    fn excludes_answer_itself() {
        let answer = song("s1", "GO MY WAY!!");
        let pool = [answer.clone(), song("s2", "蒼い鳥")];
        assert_eq!(wrong_candidate_indices(&answer, &pool), vec![1]);
    }

    /// 不正解どうしのタイトル重複も落とす (同じ選択肢が 2 つ並ばない)。
    #[test]
    fn deduplicates_among_wrong_candidates() {
        let answer = song("s1", "自転車");
        let pool = [song("s2", "隣に…"), song("s3", "隣に…"), song("s4", "オーバーマスター")];
        assert_eq!(
            titles_at(&pool, &wrong_candidate_indices(&answer, &pool)),
            vec!["隣に…", "オーバーマスター"]
        );
    }

    /// 順序は pool のまま (シャッフルは make_choices 側の責務)。
    #[test]
    fn wrong_candidates_keep_pool_order() {
        let answer = song("s0", "答え");
        let pool: Vec<_> = (1..=5).map(|i| song(&format!("s{i}"), &format!("曲{i}"))).collect();
        assert_eq!(wrong_candidate_indices(&answer, &pool), vec![0, 1, 2, 3, 4]);
    }

    #[test]
    fn empty_pool_yields_no_candidates() {
        assert!(wrong_candidate_indices(&song("s1", "答え"), &[]).is_empty());
    }

    // --- Unicode 正準等価 (Swift の String == との互換) ---

    /// 正解と正準等価 (NFC/NFD 表現違い) なタイトルは候補にしない。
    /// バイト比較だと見た目が同じ「ヴァン」が選択肢に 2 つ並ぶ (340823b の再発)。
    #[test]
    fn excludes_canonically_equivalent_title() {
        let answer = song("s1", "ヴァン"); // NFC (U+30F4)
        let pool = [
            answer.clone(),
            song("s2", "ウ\u{3099}ァン"), // NFD (U+30A6 + U+3099)、見た目は同じ「ヴァン」
            song("s3", "別の曲"),
        ];
        assert_eq!(titles_at(&pool, &wrong_candidate_indices(&answer, &pool)), vec!["別の曲"]);
    }

    /// 不正解どうしの NFC/NFD 重複も落とす。残るのは最初の 1 件で、表示は原文のまま
    /// (正規化した文字列に置き換えない)。
    #[test]
    fn deduplicates_canonically_equivalent_wrong_candidates() {
        let answer = song("s1", "答え");
        let pool = [
            song("s2", "ムケ\u{3099}ンタ\u{3099}イ"), // NFD (出荷 DB に実在する表現)
            song("s3", "ムゲンダイ"),                    // NFC の同名
            song("s4", "別の曲"),
        ];
        assert_eq!(
            titles_at(&pool, &wrong_candidate_indices(&answer, &pool)),
            vec!["ムケ\u{3099}ンタ\u{3099}イ", "別の曲"]
        );
    }

    /// id の比較も正準等価。表現違いの同一 id は「正解そのもの」として素通しされ、
    /// そのタイトルは既出に数えない (後続の同題別曲は候補に残る = Swift の guard と同じ)。
    #[test]
    fn canonically_equivalent_id_is_skipped_without_consuming_title() {
        let answer = song("id_ガ", "答え"); // id は NFC の「ガ」入り
        let pool = [
            song("id_カ\u{3099}", "別題"), // 同 id の NFD 表現 → 正解そのもの扱い
            song("s2", "別題"),             // 別 id の同題 → 既出扱いにならず候補に残る
        ];
        assert_eq!(wrong_candidate_indices(&answer, &pool), vec![1]);
    }

    /// 症状レベルの回帰: NFC/NFD 混在 pool で何度出題しても、正規化して見比べると
    /// 同じタイトルが 2 つ並ぶことはない。
    #[test]
    fn make_never_produces_visually_duplicate_titles_across_normalization_forms() {
        let answer = song("s1", "ヴァン");
        let pool = [
            answer.clone(),
            song("s2", "ウ\u{3099}ァン"),
            song("s3", "ムゲンダイ"),
            song("s4", "ムケ\u{3099}ンタ\u{3099}イ"),
            song("s5", "別の曲"),
        ];
        for seed in 0..40 {
            let choices = make_choices(&answer, &pool, 3, &mut SplitMix64(seed));
            let unique: HashSet<String> =
                choices.iter().map(|t| nfc_key(t).into_owned()).collect();
            assert_eq!(unique.len(), choices.len(), "正規化すると同じ選択肢が並ぶ: {choices:?}");
        }
    }

    // --- make_choices (出題される 4 択) ---

    fn ten_song_pool() -> Vec<IntroQuizSongRef> {
        (1..=10).map(|i| song(&format!("s{i}"), &format!("曲{i}"))).collect()
    }

    #[test]
    fn make_returns_four_unique_choices_including_answer() {
        let answer = song("s0", "答え");
        let choices = make_choices(&answer, &ten_song_pool(), 3, &mut SplitMix64(42));

        assert_eq!(choices.len(), 4);
        let unique: HashSet<&String> = choices.iter().collect();
        assert_eq!(unique.len(), 4, "同じ選択肢が 2 つ並んではいけない: {choices:?}");
        assert!(choices.contains(&"答え".to_string()), "正解は必ず選択肢に入る");
    }

    /// 候補が足りなくても落ちず、正解は必ず残る (ブランド曲数が少ない設定への備え)。
    #[test]
    fn make_with_too_few_candidates() {
        let answer = song("s0", "答え");
        let mut choices = make_choices(&answer, &[song("s1", "曲1")], 3, &mut SplitMix64(7));
        choices.sort();
        assert_eq!(choices, vec!["曲1", "答え"]);
    }

    /// pool が空でも正解 1 つは返る。
    #[test]
    fn make_with_empty_pool() {
        assert_eq!(
            make_choices(&song("s0", "答え"), &[], 3, &mut SplitMix64(7)),
            vec!["答え"]
        );
    }

    /// 正解の位置が固定されない (常に末尾なら位置で当てられてしまう)。
    #[test]
    fn answer_position_varies() {
        let answer = song("s0", "答え");
        let pool = ten_song_pool();
        let positions: HashSet<usize> = (0..40)
            .map(|seed| {
                let choices = make_choices(&answer, &pool, 3, &mut SplitMix64(seed));
                choices.iter().position(|t| t == "答え").expect("正解が選択肢にない")
            })
            .collect();
        assert!(positions.len() > 1, "正解の位置が固定されている: {positions:?}");
    }

    /// 同名異曲がある実データ相当の pool でも、選択肢にタイトル重複が出ない。
    #[test]
    fn make_never_produces_duplicate_titles() {
        let answer = song("s0", "READY!!");
        let pool = [
            song("s1", "READY!!"),
            song("s2", "READY!!"),
            song("s3", "CHANGE!!!!"),
            song("s4", "CHANGE!!!!"),
            song("s5", "M@STERPIECE"),
        ];
        for seed in 0..40 {
            let choices = make_choices(&answer, &pool, 3, &mut SplitMix64(seed));
            let unique: HashSet<&String> = choices.iter().collect();
            assert_eq!(unique.len(), choices.len(), "重複した選択肢: {choices:?}");
            assert!(choices.contains(&"READY!!".to_string()));
        }
    }

    /// wrong_count = 0 なら正解だけが返る (境界値)。
    #[test]
    fn make_with_zero_wrong_count() {
        assert_eq!(
            make_choices(&song("s0", "答え"), &ten_song_pool(), 0, &mut SplitMix64(1)),
            vec!["答え"]
        );
    }

    // --- make_choices_batch (1 ゲーム = 1 呼び出し) ---

    /// 出題と同順・同数で返り、各問に自分の正解が入り、重複もない。
    #[test]
    fn batch_returns_choices_per_answer_in_order() {
        let pool = ten_song_pool();
        let answers = [pool[0].clone(), pool[4].clone(), pool[9].clone()];
        let all = make_choices_batch(&answers, &pool, 3, &mut SplitMix64(42));

        assert_eq!(all.len(), answers.len());
        for (answer, choices) in answers.iter().zip(&all) {
            assert_eq!(choices.len(), 4);
            assert!(choices.contains(&answer.title), "{} が自分の設問の選択肢にない", answer.title);
            let unique: HashSet<&String> = choices.iter().collect();
            assert_eq!(unique.len(), choices.len(), "重複した選択肢: {choices:?}");
        }
    }

    #[test]
    fn batch_with_no_answers_returns_empty() {
        assert!(make_choices_batch(&[], &ten_song_pool(), 3, &mut SplitMix64(1)).is_empty());
    }

    /// シード注入の意味: 同じシードなら (プラットフォームによらず) 同じ出題になる。
    #[test]
    fn batch_same_seed_gives_same_result() {
        let pool = ten_song_pool();
        let answers = [pool[2].clone(), pool[7].clone()];
        assert_eq!(
            make_choices_batch(&answers, &pool, 3, &mut SplitMix64(42)),
            make_choices_batch(&answers, &pool, 3, &mut SplitMix64(42))
        );
    }

    /// 前の設問のシャッフルが後の設問に波及して固定化しない (rng を通しで使う)。
    #[test]
    fn batch_questions_are_not_identical_when_pool_allows_variety() {
        let pool = ten_song_pool();
        let answers = [pool[0].clone(), pool[0].clone()];
        let variety: HashSet<Vec<String>> = (0..40)
            .flat_map(|seed| make_choices_batch(&answers, &pool, 3, &mut SplitMix64(seed)))
            .collect();
        assert!(variety.len() > 1, "全設問の選択肢が毎回同一になっている");
    }
}
