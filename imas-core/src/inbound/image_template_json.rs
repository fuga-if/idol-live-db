//! 画像テンプレート JSON の FFI 面。ロジックは domain::image_template_json。

use crate::domain::image_template_json::ImageTemplatePair;

/// 画像一括インポート用の型紙 JSON を組み立てる。
///
/// 名前一覧を (key, value) の射影 Record で 1 回だけ渡し、完成した JSON 文字列を
/// 1 回で受け取る (1 ユーザー操作 = 1 FFI 呼び出しの規約)。
/// エスケープは Darwin の `JSONSerialization` と 1 バイトも違わない互換実装
/// (詳細は domain 側のドキュメント参照)。
#[uniffi::export]
pub fn image_template_json(pairs: Vec<ImageTemplatePair>) -> String {
    crate::domain::image_template_json::image_template_json(&pairs)
}
