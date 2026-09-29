//! Driven (secondary) アダプタ層: ポートの裏の具体実装。
//! ここだけが rusqlite に依存してよい (domain は依存しない)。
// db/community.sql を読むのは Web 出面の書き出しだけなので、アプリのビルドには入れない。
#[cfg(feature = "web-export")]
pub mod community_loader;
pub mod sqlite_loader;

pub mod schema_apply;
