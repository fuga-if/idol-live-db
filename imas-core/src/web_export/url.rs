//! URL 規約と id の安全化。本体は [`crate::domain::web_path`]。
//!
//! 出面の書き出しだけでなく、アプリが組む「公開サイトの曲ページへの共有リンク」
//! ([`crate::domain::share_text::lyric_share_url`]) も同じ規約で URL を作る。
//! アプリのビルドには web-export が入らないので、規約は domain に置いてここから引く
//! (同じパスを 2 通りに書ける状態を作らない)。

pub use crate::domain::web_path::*;
