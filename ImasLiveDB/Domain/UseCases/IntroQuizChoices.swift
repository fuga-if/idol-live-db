import Foundation

/// イントロクイズの 4 択を組み立てる規則。
///
/// ## なぜ 1 か所に置くか
///
/// 1 人用 (`IntroGameSession`) と対戦 (`IntroPartySession`) が同じ選択肢生成を
/// 別々に持っていて、実装が 1 文字違わずコピーされていた。片方だけ直すと
/// 一方のモードだけ壊れた選択肢が出る。
///
/// ## なぜタイトルでユニーク化するか
///
/// 同名異曲 (別バージョン・リミックス等) が pool に複数あると、不正解として
/// 正解と同じタイトルが並びうる。そうなると「正しい答えを選んだのに不正解」に
/// なるので、**タイトル**で重複を落とす (曲 ID ではなく)。
enum IntroQuizChoices {
    /// 不正解の候補。正解自身・正解と同じタイトル・既出タイトルを除く。
    /// 順序は `pool` のまま (シャッフルしない) ので、規則だけを単体で検証できる。
    static func wrongCandidates(for song: Song, pool: [Song]) -> [Song] {
        var seenTitles: Set<String> = [song.title]
        return pool.filter { candidate in
            guard candidate.id != song.id, !seenTitles.contains(candidate.title) else { return false }
            seenTitles.insert(candidate.title)
            return true
        }
    }

    /// 出題する選択肢。正解 1 つ + 不正解 `wrongCount` 個を混ぜて返す。
    ///
    /// 候補が足りなければその分だけ少ない選択肢になる (正解は必ず含む)。
    /// - Parameter generator: テストから固定乱数を差せるようにするための乱数源。
    static func make<G: RandomNumberGenerator>(
        for song: Song,
        pool: [Song],
        wrongCount: Int = 3,
        using generator: inout G
    ) -> [String] {
        let wrongs = wrongCandidates(for: song, pool: pool)
            .shuffled(using: &generator)
            .prefix(wrongCount)
            .map(\.title)
        return (wrongs + [song.title]).shuffled(using: &generator)
    }

    /// 実行時用 (システム乱数)。
    static func make(for song: Song, pool: [Song], wrongCount: Int = 3) -> [String] {
        var generator = SystemRandomNumberGenerator()
        return make(for: song, pool: pool, wrongCount: wrongCount, using: &generator)
    }
}
