//! メンバーカラー合わせ (色当てゲーム) の FFI 面。ロジックは domain::color_match。
//!
//! 画面の 1 操作ごとに 1 呼び出しで済む粒度に切ってある:
//!
//! | 画面の操作 | 呼ぶもの |
//! |---|---|
//! | 画面を開く (DB 読み込み後) | [`color_match_build_pools`] |
//! | 出題ブランドをトグル | [`color_match_effective_pool`] |
//! | 「はじめる」 | [`color_match_start_game`] (全問まとめて生成) |
//! | 「判定する」 | [`color_match_judge_round`] (行の正誤も HEX 表示もここで返す) |
//! | 結果画面 | [`color_match_accuracy_percent`] |
//!
//! 出題ごと・行ごとに呼ぶ形は禁止 (FFI 境界の規約)。難易度セグメントの index
//! 0 / 1 / 2 は [`ColorMatchDifficulty`] の Easy / Normal / Hard にそのまま対応する。
//!
//! エクスポートを増減したら、末尾のテストの checksum 一覧と、共有の
//! tests/ffi_surface.rs の一覧の **両方** に反映すること。片方だけだと
//! 抜けが Swift/Kotlin ラッパのリンク時まで表に出ない。

use crate::domain::color_match::{
    ColorMatchAssignment, ColorMatchBrandRef, ColorMatchDifficulty, ColorMatchIdol,
    ColorMatchIdolSource, ColorMatchJudgement, ColorMatchPools, ColorMatchRound,
};

/// アイドル / ブランドの一覧から出題母集団一式を組む (画面ロード時に 1 回)。
///
/// 外部ゲスト演者・コラボ枠・色未設定の除外、色の重複排除、ブランドごとの
/// 出題可否 (4 人以上) の判断はすべてここで行う。呼び出し側は結果を保持しておき、
/// ブランド選択が変わるたびに [`color_match_effective_pool`] へ渡す。
#[uniffi::export]
pub fn color_match_build_pools(
    idols: Vec<ColorMatchIdolSource>,
    brands: Vec<ColorMatchBrandRef>,
) -> ColorMatchPools {
    crate::domain::color_match::build_pools(&idols, &brands)
}

/// 選択中のブランドから実際の出題母集団を引く (未選択なら全ブランド)。
///
/// 件数が [`crate::domain::color_match::MIN_POOL_SIZE`] 未満なら開始できない
/// (呼び出し側が「はじめる」を塞ぐ)。描画のたびではなく、ブランド選択が
/// 変わったときだけ呼んで結果を保持すること。
#[uniffi::export]
pub fn color_match_effective_pool(
    pools: ColorMatchPools,
    selected_brand_ids: Vec<String>,
) -> Vec<ColorMatchIdol> {
    crate::domain::color_match::effective_pool(&pools, &selected_brand_ids)
}

/// 1 ゲームぶん (全 `question_count` 問) の出題をまとめて生成する。
///
/// 問題ごとに FFI を呼ぶ形を避けるため、開始操作 1 回でここまで引き切る。
/// `seed` の調達 (実行時はシステム乱数、テストでは固定値) は各 OS のラッパが担う。
#[uniffi::export]
pub fn color_match_start_game(
    pool: Vec<ColorMatchIdol>,
    difficulty: ColorMatchDifficulty,
    question_count: u32,
    seed: u64,
) -> Vec<ColorMatchRound> {
    let mut rng = crate::domain::prng::SplitMix64(seed);
    crate::domain::color_match::make_rounds(&pool, difficulty, question_count, &mut rng)
}

/// 1 問の答え合わせ。行ごとの正誤・正解数・出題数・正解色の表示文字列をまとめて返す。
///
/// `members` は [`color_match_start_game`] が返した出題メンバーをそのまま渡す。
/// 呼び出し側は `score` / `out_of` をセッションの通算に足していく。
#[uniffi::export]
pub fn color_match_judge_round(
    members: Vec<ColorMatchIdol>,
    assignments: Vec<ColorMatchAssignment>,
) -> ColorMatchJudgement {
    crate::domain::color_match::judge_round(&members, &assignments)
}

/// 結果画面の正答率 (%)。1 問も出ていなければ 0。
#[uniffi::export]
pub fn color_match_accuracy_percent(total_correct: u32, total_answered: u32) -> u32 {
    crate::domain::color_match::accuracy_percent(total_correct, total_answered)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::color_match as domain;

    // このモジュールが FFI 面に出している関数の checksum シンボル一覧。
    //
    // UniFFI は export 属性を付けた関数ごとに、引数なしの
    // `uniffi_imas_core_checksum_func_<関数名>` を no_mangle で生成する。ここで
    // extern 宣言して実際に呼ぶことで、「エクスポートが消えた / 改名された」を
    // リンクエラーとして検出する (iOS `ColorMatchGameView.swift` / Android
    // `ColorMatchGameScreen.kt` が参照する生成シンボルが揃っていることの Rust 側の保証)。
    //
    // なぜ tests/ffi_surface.rs の集中一覧だけに任せないか: 別ファイルの一覧は
    // エクスポートを足したときの追記を忘れても「テスト緑」のまま通ってしまい、
    // Swift/Kotlin ラッパのリンク時まで発覚しない (回帰: Phase 8 sync の 20 関数、
    // および本モジュールの 5 関数が、いずれも未登録のまま「テスト緑」と報告された)。
    // エクスポート本体と同じファイルに置けば、関数を触る差分とこの一覧を触る差分が
    // 必ず同じ場所に並ぶので乖離しにくい。
    extern "C" {
        fn uniffi_imas_core_checksum_func_color_match_build_pools() -> u16;
        fn uniffi_imas_core_checksum_func_color_match_effective_pool() -> u16;
        fn uniffi_imas_core_checksum_func_color_match_start_game() -> u16;
        fn uniffi_imas_core_checksum_func_color_match_judge_round() -> u16;
        fn uniffi_imas_core_checksum_func_color_match_accuracy_percent() -> u16;
    }

    /// 上の一覧に並べたシンボルの数。`every_export_in_this_module_is_listed` の基準値。
    const DECLARED_CHECKSUMS: usize = 5;

    /// 一覧の各シンボルを実際に呼ぶ。呼び出せること自体がリンク成功の証明で、
    /// 戻り値は署名を変えれば変わる値なので固定しない。
    #[test]
    fn every_listed_export_has_an_ffi_checksum_symbol() {
        let checksums = unsafe {
            [
                uniffi_imas_core_checksum_func_color_match_build_pools(),
                uniffi_imas_core_checksum_func_color_match_effective_pool(),
                uniffi_imas_core_checksum_func_color_match_start_game(),
                uniffi_imas_core_checksum_func_color_match_judge_round(),
                uniffi_imas_core_checksum_func_color_match_accuracy_percent(),
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
        let exported = include_str!("color_match.rs").matches(attribute).count();
        assert_eq!(
            exported, DECLARED_CHECKSUMS,
            "エクスポートを増減したら上の checksum 一覧と DECLARED_CHECKSUMS も直すこと。\
             一覧に無い関数は改名・削除してもこのテストが緑のまま通り、\
             Swift/Kotlin ラッパのリンク時まで発覚しない"
        );
    }

    // MARK: - 委譲の疎通

    /// 実データを模した 2 ブランド (765AS 5 人 / シンデレラ 4 人)。
    fn sources() -> Vec<ColorMatchIdolSource> {
        [
            ("haruka", "765as", "#e22b30", 1),
            ("chihaya", "765as", "#2743d2", 2),
            ("miki", "765as", "#b4e04b", 3),
            ("yukiho", "765as", "#d9c8b7", 4),
            ("yayoi", "765as", "#f39939", 5),
            ("uzuki", "cinderella", "#e75f8e", 1),
            ("rin", "cinderella", "#2e93d0", 2),
            ("mio", "cinderella", "#f8b301", 3),
            ("mika", "cinderella", "#a5487e", 4),
        ]
        .into_iter()
        .map(|(id, brand_id, color, sort_order)| ColorMatchIdolSource {
            id: id.into(),
            brand_id: brand_id.into(),
            color: Some(color.into()),
            is_external: false,
            sort_order,
        })
        .collect()
    }

    fn brands() -> Vec<ColorMatchBrandRef> {
        [("765as", 1), ("cinderella", 2)]
            .into_iter()
            .map(|(id, sort_order)| ColorMatchBrandRef { id: id.into(), sort_order })
            .collect()
    }

    fn ids(idols: &[ColorMatchIdol]) -> Vec<&str> {
        idols.iter().map(|i| i.id.as_str()).collect()
    }

    #[test]
    fn build_pools_delegates_to_the_domain_rule() {
        let pools = color_match_build_pools(sources(), brands());

        assert_eq!(pools, domain::build_pools(&sources(), &brands()));
        // 委譲先を取り違えても Vec を返す限り型は通るので、中身の形も見る。
        assert_eq!(pools.all_colored.len(), 9);
        assert_eq!(ids(&pools.brand_pools[1].members), vec!["uzuki", "rin", "mio", "mika"]);
    }

    #[test]
    fn effective_pool_delegates_and_honours_the_selection() {
        let pools = color_match_build_pools(sources(), brands());
        let selected = vec!["cinderella".to_string()];

        let picked = color_match_effective_pool(pools.clone(), selected.clone());

        assert_eq!(picked, domain::effective_pool(&pools, &selected));
        assert_eq!(ids(&picked), vec!["uzuki", "rin", "mio", "mika"]);
        // 未選択は「全ブランド」。空 Vec を「誰も選ばれていない = 母集団も空」と
        // 取り違えると、ブランド未選択のまま始められなくなる。
        assert_eq!(color_match_effective_pool(pools, vec![]).len(), 9);
    }

    /// この層で唯一「委譲だけではない」処理 = 受け取った seed で PRNG を起こす部分を固定する。
    ///
    /// seed 以外 (question_count 等) を種にしてしまっても型は通るので、
    /// 「seed が変われば出題も変わる」「同じ seed なら同じ出題」の両方を見る。
    #[test]
    fn start_game_seeds_the_prng_with_the_given_seed() {
        let pool = color_match_build_pools(sources(), brands()).all_colored;
        let run = |seed| color_match_start_game(pool.clone(), ColorMatchDifficulty::Normal, 3, seed);

        assert_eq!(run(42), run(42), "同じ seed なら同じゲームになること");
        assert_ne!(run(42), run(43), "seed 以外を種にしていないこと");

        let mut rng = crate::domain::prng::SplitMix64(42);
        assert_eq!(run(42), domain::make_rounds(&pool, ColorMatchDifficulty::Normal, 3, &mut rng));
    }

    /// 出題数と難易度が素通りしていること (どちらも取り違えても型が通る)。
    #[test]
    fn start_game_passes_question_count_and_difficulty_through() {
        let pool = color_match_build_pools(sources(), brands()).all_colored;

        let rounds = color_match_start_game(pool.clone(), ColorMatchDifficulty::Hard, 4, 7);
        assert_eq!(rounds.len(), 4);
        assert!(rounds.iter().all(|round| round.members.len() == 6));

        let easy = color_match_start_game(pool, ColorMatchDifficulty::Easy, 1, 7);
        assert_eq!(easy[0].members.len(), 4);
    }

    #[test]
    fn judge_round_delegates_with_labels() {
        let members = vec![
            ColorMatchIdol { id: "haruka".into(), color: Some("#e22b30".into()) },
            ColorMatchIdol { id: "chihaya".into(), color: Some("#2743d2".into()) },
        ];
        let assignments = vec![
            // 表記ゆれを吸収する規則が委譲先に乗っていること (大文字 + `#` 無し)。
            ColorMatchAssignment { idol_id: "haruka".into(), hex: "E22B30".into() },
            ColorMatchAssignment { idol_id: "chihaya".into(), hex: "#f39939".into() },
        ];

        let judged = color_match_judge_round(members.clone(), assignments.clone());

        assert_eq!(judged, domain::judge_round(&members, &assignments));
        assert_eq!(judged.correct, vec![true, false]);
        assert_eq!(judged.score, 1);
        assert_eq!(judged.out_of, 2);
        assert_eq!(judged.correct_hex_labels, vec!["#E22B30", "#2743D2"]);
    }

    /// 引数はどちらも u32 なので、入れ替えてもコンパイルが通ってしまう。
    /// 入れ替わると正答率が 25% ではなく 400% になり、結果画面が壊れる。
    #[test]
    fn accuracy_percent_delegates_without_swapping_the_arguments() {
        assert_eq!(color_match_accuracy_percent(1, 4), 25);
        assert_eq!(color_match_accuracy_percent(0, 0), 0);
        assert_eq!(color_match_accuracy_percent(7, 12), domain::accuracy_percent(7, 12));
    }
}
