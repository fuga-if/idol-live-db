import Foundation

/// 画像一括インポート用の「型紙」JSON を組み立てる。
///
/// 本体は imas-core (Rust) の `domain/image_template_json.rs`。
/// キー順の保持・`JSONSerialization` 互換のエスケープ (`\/` を含む) の
/// 設計意図とテストはそちらに記載。
///
/// ここが担うのはタプル → 射影 Record (`ImageTemplatePair`) の詰め替えだけ。
/// 名前一覧を 1 回の FFI 呼び出しで渡し、完成した JSON 文字列を受け取る。
func imageTemplateJSON(pairs: [(String, String)]) -> String {
    imageTemplateJson(pairs: pairs.map { ImageTemplatePair(key: $0.0, value: $0.1) })
}
