import Foundation

/// 一覧の絞り込み用に前処理した検索テキスト。
///
/// `String.contains` を使わないのは、Swift の `String` が書記素クラスタ単位で走るから。
/// 日本語だと極端に遅く、2,000 曲を打鍵ごとに舐める用途では効いてくる (実測):
///
/// | やり方 | 2,000 曲 1 打鍵 |
/// |---|---|
/// | 毎回 `lowercased()` + `String.contains` (曲名・よみ) | 1.38 ms |
/// | 事前に小文字化 + `String.contains` | 5.66 ms (対象を 4 つに増やした場合) |
/// | 事前に小文字化 + `range(of:options:.literal)` | 1.47 ms (同上) |
/// | **事前に小文字化した UTF-8 バイト列 + 部分列探索** | **0.11 ms** (同上) |
///
/// 下ごしらえは読み込み時の 1 回だけ (2,000 曲で約 5.5ms / 0.5MB)。`load` は元々
/// DB クエリと出演者マップの解決で数十 ms 掛かっているので誤差に収まる。
///
/// ⚠️ 大文字小文字の畳み込み**以外**はしない (ひらがな↔カタカナ、濁点、全角半角)。
/// 既存の絞り込みと同じ当たり方を保つため。緩めるなら検索側とまとめて変えること。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
struct TextSearchIndex: Sendable {
    /// 小文字化済みの UTF-8 バイト列。照合したい単位ごとに 1 本持つ。
    ///
    /// 連結して 1 本にしないのは、境界をまたいだ偽陽性を避けるため
    /// (「A」と「B」を繋ぐと "AB" が当たってしまう)。
    private let fields: [[UInt8]]

    init(_ texts: [String?]) {
        fields = texts.compactMap { text in
            guard let text, !text.isEmpty else { return nil }
            return Array(text.lowercased().utf8)
        }
    }

    /// 前処理済みの検索語。打鍵ごとに作り直すのは 1 個だけなので安い。
    struct Needle: Sendable {
        let bytes: [UInt8]
        var isEmpty: Bool { bytes.isEmpty }

        init(_ text: String) {
            bytes = Array(text.lowercased().utf8)
        }
    }

    /// いずれかの単位に検索語を含むか。空の検索語は「絞り込まない」= true。
    func matches(_ needle: Needle) -> Bool {
        guard !needle.isEmpty else { return true }
        for field in fields where Self.contains(field, needle.bytes) { return true }
        return false
    }

    /// 素朴な部分列探索。
    ///
    /// UTF-8 は先頭バイトと継続バイトの範囲が重ならないので、バイト列としての一致が
    /// そのまま文字列としての一致になる (途中のバイトから始まる偽の一致が起きない)。
    /// 検索語は数文字なので Boyer-Moore 等を持ち込む必要はない。
    static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        let first = needle[0]
        let last = haystack.count - needle.count
        var i = 0
        while i <= last {
            if haystack[i] == first {
                var j = 1
                while j < needle.count && haystack[i + j] == needle[j] { j += 1 }
                if j == needle.count { return true }
            }
            i += 1
        }
        return false
    }
}
