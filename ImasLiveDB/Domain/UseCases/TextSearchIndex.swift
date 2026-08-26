import Foundation

/// 一覧の絞り込み用に前処理した検索カタログの補助。
///
/// 本体は imas-core (Rust) の `domain/text_search_index.rs` にあり、
/// `TextSearchCatalog` (生成バインディング) として公開される。
/// バイト列前処理・部分列探索 (UTF-8 先頭バイトの性質) や
/// 「大文字小文字以外は畳まない」境界の設計意図もそちらに記載。
///
/// 旧 `TextSearchIndex` は曲ごとに索引を持ち打鍵ごとに全曲 `matches()` を呼ぶ設計
/// だったが、FFI 越しにそれをやると打鍵ごとに 2,000+ 回の境界越えになる。
/// カタログは全項目を 1 回で前処理し、**1 打鍵 = `matchingIndices` 1 呼び出し**で
/// 当たった項目の index 列が返る。呼び出し側は手元の配列を index で引く。
/// Rust 化後も 1 呼び出し O(総バイト数) は不変 (境界コストは定数)。
///
/// ここが担うのは nil 混じりフィールド列の整形だけ。
extension TextSearchCatalog {
    /// 1 項目 = フィールド列 (nil は落とす) でカタログを一括構築する (読み込み時の 1 回だけ)。
    /// 空文字のフィールドは Rust 側で索引から外れるので、ここでは nil だけ除けばよい。
    convenience init(fieldsPerItem: [[String?]]) {
        self.init(items: fieldsPerItem.map { $0.compactMap { $0 } })
    }
}

/// あいまい一致 (「もしかして」) の候補集合。
///
/// 本体は imas-core (Rust) の `domain/fuzzy_search.rs`。`TextSearchCatalog` が
/// 部分一致 (contains) しか見ないので、打ち間違い・カタカナ/ひらがな・音引きの揺れは
/// そこで 0 件になる。編集距離で「だいたい合っている」候補を拾うのがこちら。
///
/// ## なぜ綴りを 1 件につき複数渡すか
/// 編集距離は漢字とかなを寄せられない (「願」と「ねが」を同一視する術がない)。
/// 曲名だけを渡すと、ひらがなで打つ人は漢字の曲名に永久に当たらない。
/// `songs.title_kana` の読みを 2 本目の綴りとして併せて渡すことで
/// 「おねがいしんでれら」→「お願い！シンデレラ」が当たるようになる。
///
/// ## 呼び出し規約
/// `TextSearchCatalog` と同じく **1 打鍵 = 1 FFI 呼び出し**。全件ぶんの綴りを 1 回渡し、
/// 当たった項目の添字列を受け取る。呼び出し側は手元の配列を添字で引く
/// (添字は「渡した配列の添字」なので、綴り表と一覧の並びは必ず同じにすること)。
struct FuzzySearchCatalog: Sendable {
    /// 一覧と同じ並び。1 件 = その件を指す綴りの列 (曲名・読み・別名…)。
    private let spellings: [[String]]

    /// 1 項目 = 綴り列 (nil / 空白のみは落とす) で構築する (読み込み時の 1 回だけ)。
    init(spellingsPerItem: [[String?]]) {
        spellings = spellingsPerItem.map { fields in
            fields.compactMap { field in
                let trimmed = field?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        }
    }

    var isEmpty: Bool { spellings.isEmpty }

    /// あいまい候補の添字を、**既に出ている添字を除いて**返す。
    ///
    /// コアは部分一致で拾えた件も `exact` として上位に返す。それらは呼び出し側で既に
    /// 一覧に出ているので、その席のぶんだけ多めに引いてから間引く
    /// (`limit` は並べ替えの後に効くため、素朴に `limit` だけ引くと全部が既出で埋まる)。
    ///
    /// ⚠️ `shown` が大きいと引く量も増える。「部分一致で十分見つかっているときは
    /// そもそも呼ばない」(`FuzzySearchTuning.suggestThreshold`) 前提の API。
    func extraIndices(needle: String, excluding shown: Set<Int>, limit: Int) -> [Int] {
        guard !spellings.isEmpty, limit > 0 else { return [] }
        // clamping: 呼び出し側が閾値を掛け忘れても、変換で trap させない。
        let hits = fuzzyMatchesMulti(haystacks: spellings, needle: needle,
                                     limit: UInt32(clamping: shown.count + limit))
        var extras: [Int] = []
        for hit in hits {
            let index = Int(hit.index)
            guard !shown.contains(index), spellings.indices.contains(index) else { continue }
            extras.append(index)
            if extras.count >= limit { break }
        }
        return extras
    }
}

/// 「もしかして」の出し方の調整値。
///
/// `@MainActor` 型の static にすると FFI を回す detached task から触れないので、
/// 隔離のないここに置く。
enum FuzzySearchTuning {
    /// 部分一致がこれより多く当たっているときは「もしかして」を足さない。
    ///
    /// 打った通りの曲が 30 件も出ている画面の末尾に候補を積んでも、読まれずノイズになる。
    /// あいまい検索が効くのは「打ったのに出てこない」ときだけ。
    static let suggestThreshold = 30

    /// 追加する候補の上限。
    static let limit = 20

    /// 入力が落ち着いたと見なすまでの待ち。
    ///
    /// 全件ぶんの編集距離は 3,000 曲で 20ms 前後かかる。打鍵ごとに回すと入力が渋るので、
    /// 手が止まってから 1 回だけ引く。部分一致 (0.1ms) は待たせずその場で出す。
    static let debounce: Duration = .milliseconds(250)
}
