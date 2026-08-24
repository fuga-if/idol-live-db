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
