import Foundation

/// イントロクイズの 4 択を組み立てる規則。
///
/// 規則本体は imas-core (Rust) の `domain/intro_quiz_choices.rs` にあり、Android の
/// イントロドンと同じ実装を共有する。なぜタイトルでユニーク化するか (同名異曲対策) 等の
/// 設計意図もそちらに記載。
///
/// ここが担うのは「シードの調達」と「`Song` → (id, title) 射影」だけ。
/// 出題ごとにループで FFI を呼ばないよう、1 ゲームぶんの出題をまとめて
/// 1 呼び出しで生成する (バッチのみを公開し、設問単位の呼び口は置かない)。
enum IntroQuizChoices {
    /// 出題曲それぞれの選択肢 (正解 1 + 不正解 `wrongCount`) をまとめて生成する。
    /// 戻り値は `answers` と同順・同数。候補が足りない設問はその分だけ少ない選択肢になる
    /// (正解は必ず含む)。
    ///
    /// - Parameter generator: シード調達源。テストから固定乱数を差せるようにするため。
    static func makeAll<G: RandomNumberGenerator>(
        for answers: [Song],
        pool: [Song],
        wrongCount: Int = 3,
        using generator: inout G
    ) -> [[String]] {
        introQuizChoicesBatch(
            answers: answers.map { IntroQuizSongRef(id: $0.id, title: $0.title) },
            pool: pool.map { IntroQuizSongRef(id: $0.id, title: $0.title) },
            // 負の wrongCount は 0 (正解のみ) に丸める。境界の型合わせのみで判定はしない。
            wrongCount: UInt32(clamping: wrongCount),
            seed: generator.next()
        )
    }

    /// 実行時用 (システム乱数でシードを調達)。
    static func makeAll(for answers: [Song], pool: [Song], wrongCount: Int = 3) -> [[String]] {
        var generator = SystemRandomNumberGenerator()
        return makeAll(for: answers, pool: pool, wrongCount: wrongCount, using: &generator)
    }
}
